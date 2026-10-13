import Foundation
import SwiftUI
import UIKit
import ChessMeCore
import CryptoKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var library = LibrarySnapshot()
    @Published var selectedWindow: ReviewWindow = .day
    @Published var reviewCutoff = Date()
    @Published var showPaywall = false
    @Published var showCloudSetup = false
    @Published var cloudAccount: CloudAccount?
    @Published var cloudAccessVerified = false
    @Published var cloudSetupError: String?
    @Published var cloudIsConnecting = false
    @Published var cloudIsRefreshing = false
    @Published var cloudDownloadError: String?
    @Published var cloudLastRefreshed: Date?
    var cloudPollingSchedule = CloudPollingSchedule()
    @Published var cloudBatchMessage: String?
    @Published var cloudBatchSubmitting = false
    var cloudAccountID: String?
    var cloudBatchTask: Task<Void, Never>?
    @Published var showConnection = false
    @Published var selectedTab = 0
    @Published var activeLesson: MoveFinding?
    @Published var sessionTab: Int?
    @Published var puzzlesLoading = false
    @Published var puzzleNotice: String?
    @Published var automaticPuzzleMatching = UserDefaults.standard.object(forKey: "puzzles.automaticMatching") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(automaticPuzzleMatching, forKey: "puzzles.automaticMatching")
            if automaticPuzzleMatching { schedulePuzzleMatches() } else { cancelPuzzleMatches() }
        }
    }
    @Published var puzzleTargetRating = UserDefaults.standard.object(forKey: "puzzles.targetRating") as? Int ?? 1200 {
        didSet { UserDefaults.standard.set(puzzleTargetRating, forKey: "puzzles.targetRating") }
    }
    @Published var automaticPuzzleLevel = UserDefaults.standard.object(forKey: "puzzles.automaticLevel") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(automaticPuzzleLevel, forKey: "puzzles.automaticLevel")
            if automaticPuzzleLevel {
                if let account = authentication.account { adoptPuzzleLevel(from: account, force: true) }
                else if let rating = library.lichessPuzzleRating { puzzleTargetRating = rating }
            }
        }
    }
    @Published private(set) var syncMessage: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var session: [MoveFinding] = []
    @Published private(set) var sessionIndex = 0
    @Published var sessionFinished = false
    @Published private(set) var sessionOutcomes: [String: String] = [:]
    @Published var engineConfiguration: DeviceEngineConfiguration = AppModel.savedEngineConfiguration() {
        didSet { if let data = try? JSONEncoder().encode(engineConfiguration) { UserDefaults.standard.set(data, forKey: "analysis.device.configuration") } }
    }
    @Published var overnightSettings = AppModel.savedOvernightSettings() {
        didSet {
            if let data = try? JSONEncoder().encode(overnightSettings) { UserDefaults.standard.set(data, forKey: "analysis.overnight.settings") }
            deviceAnalysis.preferencesChanged()
        }
    }
    @Published var deviceAnalysisDepth = 0
    lazy var deviceAnalysis = DeviceAnalysisCoordinator(model: self, schedulerEnabled: !usesEphemeralLibrary && !ProcessInfo.processInfo.arguments.contains("--ui-testing"))
    @Published var cloudEngineConfiguration = CloudEngineConfiguration.saved() {
        didSet { cloudEngineConfiguration.save() }
    }
    @Published var notice: String?
    @Published private(set) var isImporting = false
    @Published private(set) var isAnalyzing = false
    @Published private(set) var progress = 0.0
    @Published private(set) var progressMessage = ""
    @Published private(set) var cloudIsRunning = false
    @Published var publicUsername = ""
    let authentication = LichessAuthentication()
    let subscriptions = SubscriptionStore()
    let cloud: CloudAnalysisService
    let puzzleService: PuzzleService
    let lichessService: LichessService
    var puzzleMatchTask: Task<Void, Never>?
    var puzzleMatchGeneration = UUID()
    private var storage: LocalLibrary?
    private var recoveryStorage: LocalLibrary?
    private var storageInitializationFailed = false
    private var didPrepare = false
    private var libraryBeforeDemo: LibrarySnapshot?
    private let usesEphemeralLibrary: Bool
    private var clockFetches: [String: Task<ChessGame, Error>] = [:]

    init(previewLibrary: LibrarySnapshot? = nil, puzzleService: PuzzleService = PuzzleService(), lichessService: LichessService = LichessService(), cloud: CloudAnalysisService = CloudAnalysisService()) {
        self.cloud = cloud
        self.puzzleService = puzzleService
        self.lichessService = lichessService
        usesEphemeralLibrary = previewLibrary != nil
        if let previewLibrary { library = previewLibrary; return }
        do {
            let storage = try LocalLibrary()
            do {
                library = try storage.load()
                self.storage = storage
            } catch {
                recoveryStorage = storage
                notice = "Your saved library could not be opened. It has not been deleted. New imports are paused until you recover it or explicitly delete local data in Settings. \(error.localizedDescription)"
            }
        } catch {
            storageInitializationFailed = true
            notice = "Your saved library could not be opened. It has not been deleted. \(error.localizedDescription)"
        }
        _ = deviceAnalysis
    }

    var isDemo: Bool { library.isDemo }
    private static func savedOvernightSettings() -> OvernightAnalysisSettings {
        guard let data = UserDefaults.standard.data(forKey: "analysis.overnight.settings"),
              let value = try? JSONDecoder().decode(OvernightAnalysisSettings.self, from: data) else { return OvernightAnalysisSettings() }
        return value
    }
    func deepConfiguration(_ level: LocalAnalysisLevel) -> DeviceEngineConfiguration {
        var configuration = DeviceEngineConfiguration()
        configuration.engine = .stockfish
        configuration.depth = level.depth
        configuration.secondsPerPosition = level.secondsPerDecision
        configuration.memoryMB = DeviceAnalysisCoordinator.hardware.cacheMegabytes(for: level)
        configuration.searchNodeLimit = level.nodeLimit
        configuration.engineThreads = DeviceAnalysisCoordinator.hardware.engineThreads
        return configuration
    }
    func nightEstimate(_ level: LocalAnalysisLevel) -> LocalAnalysisNightEstimate {
        // Use recent game lengths so short bullet games and long rapid games
        // have different capacity estimates without asking the user to choose.
        let counts: [Double] = isDemo ? [] : windowGames.prefix(20).compactMap { game in
            guard let document = try? game.mainline(), !document.moves.isEmpty else { return nil }
            let initialSide = (game.initialFEN ?? document.initialFEN).flatMap { try? ChessPosition(fen: $0).sideToMove } ?? .white
            let count = document.moves.count / 2 + (document.moves.count % 2 == 1 && initialSide == game.playerSide ? 1 : 0)
            return count > 0 ? Double(count) : nil
        }
        let decisions = counts.isEmpty ? 40 : counts.reduce(0, +) / Double(counts.count)
        return LocalAnalysisNightEstimate(configuration: deepConfiguration(level), typicalDecisions: decisions,
                                          hardwareIdentifier: DeviceAnalysisCoordinator.hardware.modelIdentifier,
                                          engineVersion: StockfishEngine.version, timings: library.localAnalysisTimings ?? [])
    }
    func recordLocalAnalysisTiming(_ timing: LocalAnalysisTiming) {
        guard !isDemo else { return }
        updateLibrary { snapshot in
            var timings = snapshot.localAnalysisTimings ?? []
            timings.append(timing)
            snapshot.localAnalysisTimings = Array(timings.suffix(60))
        }
    }
    func analyzeOnDevice(gameID: String) {
        guard !isImporting, !cloudIsRunning, let game = windowGames.first(where: { $0.id == gameID }) else { return }
        guard selectedWindow == .day || subscriptions.isPro else { showPaywall = true; return }
        let level = DeviceAnalysisCoordinator.hardware.bounded(overnightSettings.level)
        if let job = localAnalysisJob(for: gameID), job.state != .completed {
            deviceAnalysis.enqueue(games: [game], configuration: job.configuration, level: job.level, requiresPro: selectedWindow != .day)
        } else {
            deviceAnalysis.enqueue(games: [game], configuration: deepConfiguration(level), level: level, requiresPro: selectedWindow != .day)
        }
    }
    func localAnalysisJob(for gameID: String) -> LocalAnalysisJob? {
        let jobs = (library.localAnalysisJobs ?? []).filter { $0.gameID == gameID && $0.level != nil }
        return jobs.last { $0.state == .running }
            ?? jobs.last { $0.isPending && !$0.nightOnly }
            ?? jobs.last { $0.isPending }
            ?? jobs.last { $0.state == .paused || $0.state == .failed }
            ?? jobs.last { $0.state == .completed }
    }
    func completeDeviceReview(for gameID: String, covering configuration: DeviceEngineConfiguration) -> GameAnalysis? {
        let version = LocalAnalyzer(options: configuration.options).engineVersion
        let jobs = (library.localAnalysisJobs ?? []).filter {
            $0.gameID == gameID && $0.configuration.covers(configuration) &&
            $0.checkpoint?.source == "device" && $0.checkpoint?.gameID == gameID &&
            $0.checkpoint?.isComplete == true && $0.checkpoint?.engineVersion == version
        }.sorted {
            if $0.configuration.depth != $1.configuration.depth { return $0.configuration.depth > $1.configuration.depth }
            return ($0.checkpoint?.completedAt ?? .distantPast) > ($1.checkpoint?.completedAt ?? .distantPast)
        }
        return jobs.first?.checkpoint ?? (library.analyses + (library.analysisHistory ?? [])).first {
            $0.gameID == gameID && $0.isComplete && $0.source == "device" &&
            $0.engineVersion == version && $0.configurationID == configuration.options.configurationID
        }
    }
    func gameAnalysis(for gameID: String) -> GameAnalysis? {
        if let saved = library.analyses.first(where: { $0.gameID == gameID }) { return saved }
        return (library.localAnalysisJobs ?? []).filter { $0.gameID == gameID }
            .compactMap(\.checkpoint).sorted { $0.completedAt > $1.completedAt }.first
    }
    func deviceReviewAction(for gameID: String) -> String? {
        let review = gameAnalysis(for: gameID)
        if let job = localAnalysisJob(for: gameID) {
            switch job.state {
            case .running: return nil
            case .queued: return job.nightOnly ? (review?.isComplete == true ? "Start deeper review now" : "Analyze now on this device") : nil
            case .paused, .failed: return "Resume on this device"
            case .completed: break
            }
        }
        let level = DeviceAnalysisCoordinator.hardware.bounded(overnightSettings.level)
        if completeDeviceReview(for: gameID, covering: deepConfiguration(level)) != nil { return nil }
        return review?.isComplete == true ? "Analyze deeper on this device" : "Analyze on this device"
    }
    func reconcileLocalAnalysisResults() {
        let saved = Dictionary(library.analyses.map { ($0.gameID, $0) }, uniquingKeysWith: { first, _ in first })
        for job in library.localAnalysisJobs ?? [] {
            if let checkpoint = job.checkpoint, checkpoint.gameID == job.gameID, checkpoint.source == "device", checkpoint.isComplete {
                if let existing = saved[job.gameID], existing.isComplete, existing.completedAt >= checkpoint.completedAt {
                    completeCoveredJobs(using: checkpoint, configuration: job.configuration)
                    continue
                }
                acceptDeviceCheckpoint(checkpoint)
            }
        }
    }
    func deviceAnalysisState(running: Bool, progress: Double, message: String) {
        isAnalyzing = running; self.progress = progress; progressMessage = message
    }
    func acceptDeviceCheckpoint(_ analysis: GameAnalysis) {
        // Keep a complete cloud/older review visible until its replacement is complete.
        if !analysis.isComplete, library.analyses.contains(where: { $0.gameID == analysis.gameID && $0.isComplete }) { return }
        if analysis.isComplete, let job = library.localAnalysisJobs?.first(where: { $0.checkpoint == analysis }),
           let covered = completeDeviceReview(for: analysis.gameID, covering: job.configuration) {
            saveAnalysis(covered)
            let configuration = library.localAnalysisJobs?.first(where: { $0.checkpoint == covered && $0.configuration.options.configurationID == covered.configurationID })?.configuration ?? job.configuration
            completeCoveredJobs(using: covered, configuration: configuration)
            return
        }
        saveAnalysis(analysis)
    }
    private func completeCoveredJobs(using review: GameAnalysis, configuration: DeviceEngineConfiguration) {
        guard review.isComplete, review.engineVersion == LocalAnalyzer(options: configuration.options).engineVersion else { return }
        updateLibrary { snapshot in
            for index in (snapshot.localAnalysisJobs ?? []).indices {
                guard let job = snapshot.localAnalysisJobs?[index], job.gameID == review.gameID,
                      job.state != .completed, configuration.covers(job.configuration) else { continue }
                snapshot.localAnalysisJobs?[index].checkpoint = review
                snapshot.localAnalysisJobs?[index].state = .completed
                snapshot.localAnalysisJobs?[index].message = "Review ready"
            }
        }
    }
    var effectiveEngineConfiguration: DeviceEngineConfiguration {
        engineConfiguration.bounded(forMemoryMB: Int(ProcessInfo.processInfo.physicalMemory / 1_048_576), lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
    private static func savedEngineConfiguration() -> DeviceEngineConfiguration {
        let data = UserDefaults.standard.data(forKey: "analysis.device.configuration")
        let value = data.flatMap { try? JSONDecoder().decode(DeviceEngineConfiguration.self, from: $0) }
        // Old builds only offered the original Swift engines. Adopt Arasan once;
        // subsequent explicit choices continue to persist normally.
        if !UserDefaults.standard.bool(forKey: "analysis.arasanMigration") {
            UserDefaults.standard.set(true, forKey: "analysis.arasanMigration")
            let configuration = DeviceEngineConfiguration()
            if let encoded = try? JSONEncoder().encode(configuration) { UserDefaults.standard.set(encoded, forKey: "analysis.device.configuration") }
            return configuration
        }
        var configuration = value ?? DeviceEngineConfiguration()
        if !UserDefaults.standard.bool(forKey: "analysis.depth21Migration") {
            UserDefaults.standard.set(true, forKey: "analysis.depth21Migration")
            if configuration.engine == .arasan && [14, 18].contains(configuration.depth) {
                configuration.depth = 21
                if let encoded = try? JSONEncoder().encode(configuration) { UserDefaults.standard.set(encoded, forKey: "analysis.device.configuration") }
            }
        }
        if !UserDefaults.standard.bool(forKey: "analysis.stockfishMigration") {
            UserDefaults.standard.set(true, forKey: "analysis.stockfishMigration")
            if configuration.engine == .arasan && configuration.depth == 21 && configuration.secondsPerPosition == 3 {
                configuration.engine = .stockfish
                if let encoded = try? JSONEncoder().encode(configuration) { UserDefaults.standard.set(encoded, forKey: "analysis.device.configuration") }
            }
        }
        return configuration
    }
    var hasUnreadableLibrary: Bool { recoveryStorage != nil }
    var canSaveLibrary: Bool { !storageInitializationFailed && !hasUnreadableLibrary }
    var windowGames: [ChessGame] {
        library.games.filter { $0.playedAt >= selectedWindow.since(now: reviewCutoff) && $0.playedAt <= reviewCutoff }
            .sorted { $0.playedAt > $1.playedAt }
    }
    var windowAnalyses: [GameAnalysis] {
        let ids = Set(windowGames.map(\.id))
        return library.analyses.filter { ids.contains($0.gameID) }
    }
    var allPuzzles: [MoveFinding] { library.analyses.flatMap(\.findings).filter(\.isPuzzle) }
    var allDuePuzzles: [MoveFinding] {
        allPuzzles.filter { finding in (library.practice.first { $0.findingID == finding.id }?.dueAt ?? .distantPast) <= Date() }
    }
    var findings: [MoveFinding] {
        windowAnalyses.flatMap(\.findings).sorted { $0.centipawnLoss > $1.centipawnLoss }
    }
    var puzzles: [MoveFinding] { findings.filter(\.isPuzzle) }
    var duePuzzles: [MoveFinding] {
        puzzles.filter { finding in
            guard let record = library.practice.first(where: { $0.findingID == finding.id }) else { return true }
            return record.dueAt <= Date()
        }
    }
    var completedGames: Int { windowAnalyses.filter(\.isComplete).count }
    var pendingGames: Int { max(0, windowGames.count - completedGames) }
    var themes: [(name: String, count: Int)] {
        Dictionary(grouping: findings, by: \.theme).map { ($0.key, $0.value.count) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }
    var practiceCount: Int { library.practice.reduce(0) { $0 + $1.correctCount + $1.failedCount + ($1.assistedCount ?? 0) } }
    var isBusy: Bool { isImporting || isAnalyzing || cloudIsRunning || cloudBatchSubmitting }

    func updateLibrary(_ changes: (inout LibrarySnapshot) -> Void) { changes(&library) }

    func prepare() async {
        guard !didPrepare else { return }
        didPrepare = true
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing") {
            library = LibrarySnapshot()
            storage = nil
            recoveryStorage = nil
            storageInitializationFailed = false
            if arguments.contains("--reset-engine") { engineConfiguration = DeviceEngineConfiguration() }
            if arguments.contains("--reset-local-analysis") { overnightSettings = OvernightAnalysisSettings() }
            #if DEBUG
            if let data = ProcessInfo.processInfo.environment["CHESSME_UI_TEST_LIBRARY"]?.data(using: .utf8),
               let fixture = try? JSONDecoder().decode(LibrarySnapshot.self, from: data), fixture.isDemo {
                library = fixture
                reviewCutoff = Date()
                return
            }
            #endif
        }
        if arguments.contains("--demo") { loadDemo() }
        _ = deviceAnalysis
        if !arguments.contains("--ui-testing") {
            await authentication.restore()
            if let account = authentication.account { adoptPuzzleLevel(from: account) }
            await subscriptions.load()
            schedulePuzzleMatches()
            deviceAnalysis.preferencesChanged()
            deviceAnalysis.sceneChanged(active: UIApplication.shared.applicationState == .active)
        }
    }

    func select(_ window: ReviewWindow) {
        guard !isImporting, !isSyncing else { return }
        guard window == .day || subscriptions.isPro else { showPaywall = true; return }
        selectedWindow = window
        reviewCutoff = Date()
        if overnightSettings.enabled { deviceAnalysis.preferencesChanged() }
    }

    func loadDemo() {
        guard !isBusy else { return }
        cancelPuzzleMatches()
        if !library.isDemo { libraryBeforeDemo = library }
        library = LibrarySnapshot(games: DemoContent.games(now: Date()), isDemo: true)
        library.puzzleRecommendations = [PuzzleRecommendationSet(gameID: "demo-example", analysisSignature: "demonstration", rating: 1760,
                                                               matches: DemoContent.puzzleExamples.map { PuzzleMatch(puzzle: $0, matchedThemes: ["mate"]) }, matchedAt: Date())]
        reviewCutoff = Date()
        selectedWindow = .day
        notice = nil
        syncMessage = nil
        persist()
        analyzePending()
    }

    func exitDemo() {
        guard !isBusy else { return }
        cancelPuzzleMatches()
        library = libraryBeforeDemo ?? LibrarySnapshot()
        libraryBeforeDemo = nil
        activeLesson = nil
        reviewCutoff = Date()
        notice = nil
        syncMessage = nil
    }

    func syncCompletedGames() async {
        guard !isBusy, !isSyncing else { return }
        guard !isDemo else { syncMessage = "Sample games are already loaded."; return }
        guard authentication.account != nil || library.lastSyncedUsername != nil else { showConnection = true; return }
        isSyncing = true
        defer { isSyncing = false }
        if await importGames(username: authentication.account == nil ? library.lastSyncedUsername : nil) {
            analyzePending()
        }
    }

    @discardableResult
    func importGames(username: String? = nil) async -> Bool {
        guard !isBusy else { return false }
        guard recoveryStorage == nil else { notice = ImportFailure.libraryUnreadable.localizedDescription; return false }
        guard !storageInitializationFailed else { notice = ImportFailure.storageUnavailable.localizedDescription; return false }
        guard selectedWindow == .day || subscriptions.isPro else { showPaywall = true; return false }
        let window = selectedWindow
        isImporting = true
        notice = nil
        syncMessage = nil
        progressMessage = "Reading completed games from Lichess…"
        var incremental: [ChessGame] = []
        defer {
            mergeImported(incremental)
            persist()
            isImporting = false
        }
        do {
            let target: String
            let token: String?
            if let username {
                target = username.trimmingCharacters(in: .whitespacesAndNewlines)
                token = nil
            } else {
                guard let account = authentication.account else { showConnection = true; return false }
                target = account.username
                token = try authentication.accessToken()
            }
            let existingIDs = Set(library.games.map(\.id))
            let result = try await lichessService.importGames(username: target, window: window, accessToken: token, consented: true, now: Date(), onGame: { [weak self] game in
                incremental.append(game)
                if incremental.count >= 100 {
                    self?.mergeImported(incremental)
                    incremental.removeAll(keepingCapacity: true)
                    self?.persist()
                }
            }, onProgress: { [weak self] count in
                self?.progressMessage = "Imported \(count) completed games…"
            })
            mergeImported(result.games)
            incremental.removeAll()
            library.importedAt = Date()
            library.lastSyncedUsername = username != nil ? target : nil
            library.skippedGames = result.skippedGames
            library.coverageNote = result.isComplete ? "\(window.shortLabel) import complete for finished standard live games." : (result.reachedLimit ? "\(window.shortLabel) import limited to the most recent 20,000 games. Select a smaller period to review more of your archive." : "\(window.shortLabel) import is partial because some exports could not be read. Completed records have been saved.")
            reviewCutoff = Date()
            let saved = persist()
            progressMessage = saved ? "Import saved" : "Import received, but could not be saved"
            if result.games.isEmpty {
                syncMessage = result.isComplete ? "No completed games in this period." : "No readable games · partial import"
            } else if saved {
                let newCount = result.games.filter { !existingIDs.contains($0.id) }.count
                syncMessage = "\(result.games.count) \(result.games.count == 1 ? "game" : "games") synced · \(newCount) new\(result.isComplete ? "" : " · partial import")"
            }
            if automaticPuzzleLevel, let profile = try? await lichessService.profile(username: target) {
                adoptPuzzleLevel(from: profile)
            } else if let account = authentication.account, account.username.caseInsensitiveCompare(target) == .orderedSame {
                adoptPuzzleLevel(from: account)
            }
            return saved
        } catch {
            notice = error.localizedDescription
            library.coverageNote = "Import interrupted. Games received before the interruption have been saved."
            return false
        }
    }

    func analyzePending(gameID: String? = nil, deep: Bool = false) {
        guard !isImporting, !cloudIsRunning else { return }
        guard selectedWindow == .day || subscriptions.isPro else { showPaywall = true; return }
        if deep, let gameID { analyzeOnDevice(gameID: gameID); return }
        let configuration = effectiveEngineConfiguration
        let options = configuration.options
        let engineVersion = LocalAnalyzer(options: options).engineVersion
        let complete = Set(library.analyses.filter { $0.isComplete && ($0.source == "cloud" || ($0.engineVersion == engineVersion && $0.configurationID == options.configurationID)) }.map(\.gameID))
        let pending = windowGames.filter { game in gameID == nil ? !complete.contains(game.id) : game.id == gameID }
        deviceAnalysis.enqueue(games: pending, configuration: configuration, requiresPro: selectedWindow != .day)
        if overnightSettings.enabled { deviceAnalysis.preferencesChanged() }
    }

    func pauseAnalysis() { deviceAnalysis.pause() }

    func recordPractice(_ finding: MoveFinding, correct: Bool, assisted: Bool = false) {
        var record = library.practice.first { $0.findingID == finding.id } ?? PracticeRecord(findingID: finding.id, correctCount: 0, failedCount: 0, dueAt: Date(), lastPracticedAt: Date())
        if correct && assisted { record.assistedCount = (record.assistedCount ?? 0) + 1; record.streak = 0 }
        else if correct { record.correctCount += 1; record.streak = (record.streak ?? 0) + 1 }
        else { record.failedCount += 1; record.streak = 0 }
        let days = correct && !assisted ? min(30, pow(2.0, Double(min(max(0, (record.streak ?? 1) - 1), 5)))) : 1
        record.dueAt = Date().addingTimeInterval(days * 86_400)
        record.lastPracticedAt = Date()
        library.practice.removeAll { $0.findingID == finding.id }
        library.practice.append(record)
        sessionOutcomes[finding.id] = correct ? (assisted ? "Guided" : "Solved") : "Retry"
        persist()
    }

    func nextLesson(after finding: MoveFinding? = nil) -> MoveFinding? {
        let ordered = duePuzzles.isEmpty ? puzzles : duePuzzles
        guard let finding, let index = ordered.firstIndex(where: { $0.id == finding.id }) else { return ordered.first }
        return ordered.indices.contains(index + 1) ? ordered[index + 1] : nil
    }

    func startSession(allSaved: Bool = false, theme: String? = nil) {
        sessionTab = selectedTab
        let due = allSaved ? allDuePuzzles : duePuzzles
        let candidates = due.isEmpty ? (allSaved ? allPuzzles : puzzles) : due
        let groups = Dictionary(grouping: candidates, by: \.theme)
        let focus = theme ?? groups.keys.sorted { (groups[$0]?.count ?? 0) > (groups[$1]?.count ?? 0) }.first
        let pool = candidates.sorted {
            if ($0.theme == focus) != ($1.theme == focus) { return $0.theme == focus }
            if $0.centipawnLoss != $1.centipawnLoss { return $0.centipawnLoss > $1.centipawnLoss }
            return $0.id < $1.id
        }
        var perGame: [String: Int] = [:]
        session = Array(pool.filter { finding in
            guard perGame[finding.gameID, default: 0] < 2 else { return false }
            perGame[finding.gameID, default: 0] += 1
            return true
        }.prefix(6))
        sessionIndex = 0
        sessionFinished = false
        sessionOutcomes = [:]
        activeLesson = session.first
    }

    func openLesson(_ finding: MoveFinding) {
        sessionTab = selectedTab
        let following = allPuzzles.filter { $0.id != finding.id }.sorted {
            if ($0.theme == finding.theme) != ($1.theme == finding.theme) { return $0.theme == finding.theme }
            return $0.centipawnLoss > $1.centipawnLoss
        }
        session = [finding] + Array(following.prefix(5))
        sessionIndex = 0
        sessionFinished = false
        sessionOutcomes = [:]
        activeLesson = finding
    }

    func advanceSession() {
        guard sessionIndex + 1 < session.count else { sessionFinished = true; return }
        sessionIndex += 1
        activeLesson = session[sessionIndex]
    }

    func previousSessionPosition() {
        guard sessionIndex > 0 else { return }
        sessionFinished = false
        sessionIndex -= 1
        activeLesson = session[sessionIndex]
    }

    func endSession() { activeLesson = nil; sessionTab = nil; session = []; sessionIndex = 0; sessionFinished = false; sessionOutcomes = [:] }

    private func saveAnalysis(_ analysis: GameAnalysis) {
        if library.analyses.first(where: { $0.gameID == analysis.gameID }) == analysis { return }
        if let previous = library.analyses.first(where: { $0.gameID == analysis.gameID }),
           previous.source != analysis.source || previous.configurationID != analysis.configurationID || previous.engineVersion != analysis.engineVersion {
            var history = library.analysisHistory ?? []
            history.removeAll { $0.gameID == previous.gameID && $0.source == previous.source && $0.configurationID == previous.configurationID && $0.engineVersion == previous.engineVersion }
            history.append(previous)
            library.analysisHistory = history
        }
        library.analyses.removeAll { $0.gameID == analysis.gameID }
        library.analyses.append(analysis)
        if analysis.isComplete { schedulePuzzleMatches() }
    }

    func deleteLocalData() {
        guard !isBusy else { notice = "Pause analysis before deleting your library."; return }
        deviceAnalysis.clear()
        cancelPuzzleMatches(); endSession(); resetCloudAccess()
        syncMessage = nil
        if library.isDemo { library = LibrarySnapshot(isDemo: true); notice = "Sample games cleared. Your saved library is unchanged."; return }
        if usesEphemeralLibrary { library = LibrarySnapshot(); return }
        do {
            let localStorage = try storage ?? recoveryStorage ?? LocalLibrary()
            try localStorage.delete()
            storage = localStorage
            recoveryStorage = nil
            storageInitializationFailed = false
            library = LibrarySnapshot()
            notice = "Your local games and practice history have been deleted."
        } catch { notice = error.localizedDescription }
    }

    func removeGamesForConnectedAccount() {
        guard !isBusy, !isDemo, canSaveLibrary, let username = authentication.account?.username else { return }
        let ids = Set(library.games.filter { $0.username.lowercased() == username.lowercased() }.map(\.id))
        let relatedAnalyses = library.analyses + (library.analysisHistory ?? [])
        let findingIDs = Set(relatedAnalyses.filter { ids.contains($0.gameID) }.flatMap(\.findings).map(\.id))
        cancelPuzzleMatches(); endSession()
        library.favoriteGameIDs?.removeAll { ids.contains($0) }
        library.favoriteFindings?.removeAll { ids.contains($0.gameID) }
        let puzzleIDs = Set((library.puzzleRecommendations ?? []).filter { ids.contains($0.gameID) }.flatMap(\.matches).map { $0.puzzle.id })
        library.puzzleRecommendations?.removeAll { ids.contains($0.gameID) }
        library.favoritePuzzles?.removeAll { puzzleIDs.contains($0.id) }
        library.practice.removeAll { puzzleIDs.contains($0.findingID.replacingOccurrences(of: "lichess-puzzle-", with: "")) }
        library.localAnalysisJobs?.removeAll { ids.contains($0.gameID) }
        library.games.removeAll { ids.contains($0.id) }
        library.analyses.removeAll { ids.contains($0.gameID) }
        library.analysisHistory?.removeAll { ids.contains($0.gameID) }
        library.practice.removeAll { findingIDs.contains($0.findingID) }
        clearCloudReviewReferences(accountID: username)
        persist()
    }

    @discardableResult
    func persist() -> Bool {
        guard !library.isDemo, !usesEphemeralLibrary else { return true }
        guard let storage else {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return true }
            notice = "Your latest changes could not be saved because local storage is unavailable."
            return false
        }
        do { try storage.save(library); return true }
        catch { notice = "Your latest changes could not be saved: \(error.localizedDescription)"; return false }
    }

    func importPGN(_ text: String, username: String) throws {
        guard !isBusy else { throw ImportFailure.busy }
        guard recoveryStorage == nil else { throw ImportFailure.libraryUnreadable }
        guard !storageInitializationFailed else { throw ImportFailure.storageUnavailable }
        guard selectedWindow == .day || subscriptions.isPro else { showPaywall = true; return }
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ImportFailure.missingPlayer }
        let document = try PGNDocument(text)
        if let variant = document.headers["Variant"], variant.caseInsensitiveCompare("Standard") != .orderedSame {
            throw ImportFailure.unsupportedVariant
        }
        guard let result = document.result, result != "*" else { throw ImportFailure.unfinished }
        _ = try document.replay()
        let white = document.headers["White"] ?? "White"
        let black = document.headers["Black"] ?? "Black"
        let side: Side
        if name.caseInsensitiveCompare(white) == .orderedSame { side = .white }
        else if name.caseInsensitiveCompare(black) == .orderedSame { side = .black }
        else { throw ImportFailure.playerMismatch }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy.MM.dd HH:mm:ss"
        let dateString = "\(document.headers["UTCDate"] ?? document.headers["Date"] ?? "") \(document.headers["UTCTime"] ?? "00:00:00")"
        guard let started = formatter.date(from: dateString) else { throw ImportFailure.missingDate }
        guard selectedWindow.contains(started, now: Date()) else { throw ImportFailure.outsideWindow }
        let id = "pgn-" + SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        let game = ChessGame(id: id, username: name, white: white, black: black, playedAt: started, playerSide: side, moves: document.moves.joined(separator: " "), pgn: text, initialFEN: document.initialFEN, status: result == "1/2-1/2" ? "draw" : "resign", clockData: document.clockData)
        if library.isDemo { library = libraryBeforeDemo ?? LibrarySnapshot(); libraryBeforeDemo = nil }
        library.games.removeAll { $0.id == id }
        library.games.append(game)
        library.importedAt = Date()
        library.coverageNote = "Manually imported PGN. This does not establish provider account ownership."
        reviewCutoff = Date()
        notice = "PGN imported. Start a local review when you're ready."
        persist()
    }

    enum ImportFailure: LocalizedError {
        case busy, missingPlayer, unfinished, playerMismatch, missingDate, outsideWindow, unsupportedVariant, libraryUnreadable, storageUnavailable
        var errorDescription: String? {
            switch self {
            case .busy: "Finish or pause your current import or analysis first."
            case .missingPlayer: "Enter the player name exactly as it appears in the PGN."
            case .unfinished: "Import a completed game with a final PGN result."
            case .playerMismatch: "The player name must match the White or Black PGN header."
            case .missingDate: "Include a valid Date or UTCDate header so the game can be placed in your review window."
            case .outsideWindow: "This game started outside the selected review period. Choose a matching window first."
            case .unsupportedVariant: "Only standard chess is supported. This PGN declares a different variant."
            case .libraryUnreadable: "The saved library cannot be read. Recover it or explicitly delete local data in Settings before importing new games."
            case .storageUnavailable: "Local storage is unavailable, so new games cannot be saved. Check your iPhone's available storage and reopen chess-me."
            }
        }
    }

    private func mergeImported(_ games: [ChessGame]) {
        guard !games.isEmpty else { return }
        if library.isDemo { library = libraryBeforeDemo ?? LibrarySnapshot(); libraryBeforeDemo = nil }
        var merged = Dictionary(uniqueKeysWithValues: library.games.map { ($0.id, $0) })
        for game in games {
            if let previous = merged[game.id], !previous.hasSameMainline(as: game) {
                library.analyses.removeAll { $0.gameID == game.id }
                library.puzzleRecommendations?.removeAll { $0.gameID == game.id }
            }
            if let previous = merged[game.id], previous.hasSameMainline(as: game), game.clockData == nil, let clocks = previous.clockData {
                merged[game.id] = game.withClockData(clocks, fetchedAt: previous.clockDataFetchedAt ?? Date())
            } else { merged[game.id] = game }
        }
        library.games = Array(merged.values).sorted { $0.playedAt > $1.playedAt }
    }

    /// Old libraries predate clock imports. Fetch only the opened game, share an
    /// in-flight export, and keep existing analysis and practice records intact.
    func loadGameClocks(gameID: String) async throws {
        guard !isDemo, canSaveLibrary, let game = library.games.first(where: { $0.id == gameID }),
              game.url != nil, game.isFinished, game.clockData == nil, game.clockDataFetchedAt == nil else { return }
        let task: Task<ChessGame, Error>
        if let pending = clockFetches[gameID] { task = pending }
        else {
            let service = lichessService
            task = Task { try await service.reviewedGame(gameID: gameID, username: game.username) }
            clockFetches[gameID] = task
        }
        defer { clockFetches[gameID] = nil }
        let exported = try await task.value
        guard !isDemo, canSaveLibrary, let index = library.games.firstIndex(where: { $0.id == gameID }),
              library.games[index].username == game.username, library.games[index].hasSameMainline(as: exported),
              library.games[index].clockDataFetchedAt == nil else { return }
        library.games[index] = library.games[index].withClockData(exported.clockData, fetchedAt: Date())
        guard persist() else { throw LichessError.invalidResponse }
    }

    func enhanceInCloud(game: ChessGame) async {
        guard !isBusy else { return }
        guard cloudIsReady else { showCloudSetup = true; return }
        cloudIsRunning = true
        defer { cloudIsRunning = false }
        do { try await submitCloudReview(game: game) }
        catch { cloudSetupError = error.localizedDescription; notice = error.localizedDescription }
    }

    func cloudReview(for gameID: String) -> CloudReviewRecord? {
        guard let accountID = authentication.account?.username.lowercased(), !isDemo else { return nil }
        return library.cloudReviews?.last { $0.gameID == gameID && $0.accountID == accountID }
    }

    var cloudQueueRefreshID: String {
        let accountID = authentication.account?.username.lowercased() ?? ""
        return "\(accountID):\(isDemo):\(hasCloudConsent):\(cloudEnabled)"
    }

    func refreshCloudReviews(consented: Bool = false, automatically: Bool = false) async {
        guard cloud.isConfigured, !isDemo, canSaveLibrary,
              let accountID = authentication.account?.username.lowercased(),
              consented || library.cloudReviewAccounts?.contains(accountID) == true else { return }
        if automatically {
            guard cloudEnabled || currentCloudReviews.contains(where: { $0.isPending || $0.needsAcknowledgement }),
                  cloudPollingSchedule.canRefresh() else { return }
        }
        guard !cloudIsRefreshing else { return }
        cloudIsRefreshing = true
        var downloadError: String?
        defer { cloudIsRefreshing = false }
        do {
            if consented {
                var accounts = library.cloudReviewAccounts ?? []
                if !accounts.contains(accountID) { accounts.append(accountID) }
                library.cloudReviewAccounts = accounts
                guard persist() else { return }
            }
            let jobs = try await cloud.jobs(lichessToken: authentication.accessToken())
            guard authentication.account?.username.lowercased() == accountID, !isDemo, hasCloudConsent else { return }
            for job in jobs {
                guard !Task.isCancelled, authentication.account?.username.lowercased() == accountID, !isDemo, hasCloudConsent else { return }
                do {
                    if job.result != nil && !library.games.contains(where: { $0.id == job.game_id }) {
                        let game = try await lichessService.reviewedGame(gameID: job.game_id, username: accountID)
                        guard authentication.account?.username.lowercased() == accountID, !isDemo, canSaveLibrary else { return }
                        if !library.games.contains(where: { $0.id == game.id }) { library.games.append(game) }
                    }
                    try receiveCloudJob(job, accountID: accountID)
                } catch is CancellationError { return }
                catch {
                    // One unavailable game must not block other paid downloads.
                    // Its result stays unacknowledged for a later retry.
                    downloadError = "A cloud review could not be downloaded. Other reviews will still be saved. Try refreshing. \(error.localizedDescription)"
                }
            }
            let available = Set(jobs.map(\.job_id))
            for index in (library.cloudReviews ?? []).indices {
                if library.cloudReviews![index].accountID == accountID && library.cloudReviews![index].isPending &&
                    !available.contains(library.cloudReviews![index].id) && library.cloudReviews![index].deadlineAt < Date() {
                    library.cloudReviews![index].state = "failed"
                    library.cloudReviews![index].errorCode = "job_expired"
                }
            }
            if persist() { await acknowledgeSavedCloudReviews(accountID: accountID) }
            cloudLastRefreshed = Date()
            if hasCloudConsent {
                cloudAccount = try await cloud.account(lichessToken: authentication.accessToken(), consented: true)
                cloudAccountID = accountID
            }
            cloudDownloadError = downloadError
            if let downloadError {
                cloudPollingSchedule.failed(CloudError.invalidResponse, retryAt: await cloud.nextRetryAt)
                if !automatically { notice = downloadError }
            } else {
                cloudPollingSchedule.succeeded(pending: currentCloudReviews.contains { $0.isPending || $0.needsAcknowledgement })
            }
        } catch is CancellationError { }
        catch {
            cloudPollingSchedule.failed(error, retryAt: await cloud.nextRetryAt)
            cloudDownloadError = error.localizedDescription
            if !automatically { notice = error.localizedDescription }
        }
    }

    func receiveCloudJob(_ job: CloudAnalysisJob, accountID: String) throws {
        if let response = job.result {
            guard let game = library.games.first(where: { $0.id == job.game_id }) else { throw CloudError.invalidResponse }
            let result = try response.analysis(for: game)
            if !library.analyses.contains(where: { $0.gameID == game.id && $0.source == "cloud" && $0.completedAt == result.completedAt }) {
                saveAnalysis(result)
            }
        }
        var reviews = library.cloudReviews ?? []
        reviews.removeAll { $0.id == job.job_id || ($0.gameID == job.game_id && $0.accountID == accountID) }
        reviews.append(CloudReviewRecord(job: job, accountID: accountID))
        library.cloudReviews = reviews
        if ["failed", "cancelled"].contains(job.state) {
            library.cloudSubmissionKeys = library.cloudSubmissionKeys?.filter { !$0.key.hasPrefix("\(accountID):\(job.game_id):") }
        }
    }

    func acknowledgeSavedCloudReviews(accountID: String) async {
        // Preview and demonstration libraries are not durable user downloads.
        guard !usesEphemeralLibrary, storage != nil, !isDemo, hasCloudConsent else { return }
        let reviews = (library.cloudReviews ?? []).filter { $0.accountID == accountID && $0.needsAcknowledgement }
        for review in reviews {
            guard !Task.isCancelled, authentication.account?.username.lowercased() == accountID, !isDemo else { return }
            do {
                try await cloud.acknowledgeSavedReview(review, lichessToken: authentication.accessToken()) {
                    guard self.persist() else { throw CocoaError(.fileWriteUnknown) }
                }
                guard authentication.account?.username.lowercased() == accountID, !isDemo, hasCloudConsent else { return }
                if let index = library.cloudReviews?.firstIndex(where: { $0.id == review.id && $0.accountID == accountID && $0.resultToken == review.resultToken }) {
                    library.cloudReviews![index].deliveryAcknowledged = true
                    _ = persist()
                }
            } catch is CancellationError { return }
            catch {
                // The review is already on disk. Retry the receipt on the next
                // refresh or launch; a failed acknowledgement loses no analysis.
                notice = "Your cloud review is saved on this iPhone. Download confirmation will retry when the service is available."
            }
        }
    }

    func cancelCloudReview(gameID: String) async {
        guard hasCloudConsent, let review = cloudReview(for: gameID), review.isPending else { return }
        do {
            let job = try await cloud.cancel(jobID: review.id, lichessToken: authentication.accessToken())
            guard authentication.account?.username.lowercased() == review.accountID else { return }
            try receiveCloudJob(job, accountID: review.accountID)
            _ = persist()
            await refreshCloudReviews()
        } catch { cloudDownloadError = error.localizedDescription; notice = error.localizedDescription }
    }

    func clearCloudReviewReferences(accountID: String) {
        library.cloudReviews?.removeAll { $0.accountID == accountID.lowercased() }
        library.cloudReviewAccounts?.removeAll { $0 == accountID.lowercased() }
        library.cloudEnabledAccounts?.removeAll { $0 == accountID.lowercased() }
        if library.cloudBatch?.accountID == accountID.lowercased() { library.cloudBatch = nil }
        library.cloudSubmissionKeys = library.cloudSubmissionKeys?.filter { !$0.key.hasPrefix(accountID.lowercased() + ":") }
        resetCloudAccess()
        _ = persist()
    }
}
