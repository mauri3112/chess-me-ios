import Foundation
import UIKit
import BackgroundTasks
import ChessMeCore

@MainActor
final class DeviceAnalysisCoordinator {
    static let overnightIdentifier = "com.chessme.app.analysis.overnight"
    private weak var model: AppModel?
    private var worker: Task<Void, Never>?
    private var backgroundTask: (any AnalysisBackgroundTask)?
    private var graceTask: UIBackgroundTaskIdentifier = .invalid
    private var observers: [NSObjectProtocol] = []
    private var isActive = true
    private var activeJobID: String?
    private var withinDecisionProgress = 0.0
    private var activeJobTotalDecisions = 40
    private var interruptionReason: String?
    private var continuedIdentifier: String?
    private var continuedRequestPending = false
    private var systemJobIDs = Set<String>()
    private var completedContinuedRequests: [String] = []
    private var lastSystemSubtitle: String?
    private var memoryPressureUntil: Date?
    private var memoryRecovery: Task<Void, Never>?
    private let schedulerEnabled: Bool
    private let availableMemoryMB: () -> Int?

    init(model: AppModel, schedulerEnabled: Bool = true,
         availableMemoryMB: @escaping () -> Int? = { StockfishEngine.availableMemoryMegabytes }) {
        self.model = model; self.schedulerEnabled = schedulerEnabled; self.availableMemoryMB = availableMemoryMB
        isActive = UIApplication.shared.applicationState != .background
        if schedulerEnabled {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.overnightIdentifier, using: nil) { [weak self] task in
                Task { @MainActor in await self?.accept(SystemAnalysisBackgroundTask(task)) }
            }
            UIDevice.current.isBatteryMonitoringEnabled = true
            for name in [UIDevice.batteryStateDidChangeNotification, ProcessInfo.thermalStateDidChangeNotification,
                         NSNotification.Name.NSProcessInfoPowerStateDidChange] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.conditionsChanged() }
                })
            }
            observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleMemoryPressure() }
            })
        }
        model.updateLibrary { snapshot in
            for index in (snapshot.localAnalysisJobs ?? []).indices { snapshot.localAnalysisJobs?[index].recoverAfterInterruption() }
        }
        model.reconcileLocalAnalysisResults()
        if model.library.localAnalysisJobs?.isEmpty == false { _ = model.persist() }
    }

    static var hardware: LocalAnalysisHardware {
        #if targetEnvironment(simulator)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--local-analysis-base-iphone15") {
            return LocalAnalysisHardware(modelIdentifier: "iPhone15,4", memoryMB: 6_144)
        }
        #endif
        return LocalAnalysisHardware(modelIdentifier: "Simulator", memoryMB: 8_192, isSimulator: true)
        #else
        var system = utsname()
        uname(&system)
        let machineCapacity = MemoryLayout.size(ofValue: system.machine)
        let identifier = withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: machineCapacity) { String(cString: $0) }
        }
        return LocalAnalysisHardware(modelIdentifier: identifier, memoryMB: Int(ProcessInfo.processInfo.physicalMemory / 1_048_576))
        #endif
    }

    @discardableResult
    func enqueue(games: [ChessGame], configuration: DeviceEngineConfiguration, level: LocalAnalysisLevel? = nil,
                 nightOnly: Bool = false, requiresPro: Bool = false, scheduledByUser: Bool = false) -> Bool {
        guard let model, model.canSaveLibrary else { return false }
        if let level, !Self.hardware.supports(level) { model.notice = level.requirement; return false }
        let completed = Dictionary(games.compactMap { game in
            model.completeDeviceReview(for: game.id, covering: configuration).map { (game.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
        model.updateLibrary { snapshot in
            var jobs = snapshot.localAnalysisJobs ?? []
            for game in games where game.isFinished {
                let signature = configuration.options.configurationID
                if let existing = jobs.firstIndex(where: { $0.gameID == game.id && $0.matches(configuration: configuration, level: level) }) {
                    if scheduledByUser && jobs[existing].state != .completed {
                        jobs[existing].nightOnly = nightOnly
                        jobs[existing].scheduledByUser = true
                        jobs[existing].requiresPro = requiresPro
                        if [.paused, .failed].contains(jobs[existing].state) { jobs[existing].state = .queued; jobs[existing].message = nil }
                    }
                    if let ready = completed[game.id] {
                        jobs[existing].checkpoint = ready; jobs[existing].state = .completed; jobs[existing].message = "Review ready"
                    }
                    if !nightOnly {
                        jobs[existing].nightOnly = false
                        jobs[existing].requiresPro = requiresPro
                        if [.paused, .failed].contains(jobs[existing].state) { jobs[existing].state = .queued; jobs[existing].message = nil }
                    }
                    continue
                }
                let alreadyReviewed = completed[game.id] ?? (snapshot.analyses + (snapshot.analysisHistory ?? [])).first {
                    $0.gameID == game.id && $0.source == "device" && $0.configurationID == signature &&
                    $0.engineVersion == LocalAnalyzer(options: configuration.options).engineVersion
                }
                var job = LocalAnalysisJob(gameID: game.id, configuration: configuration, level: level, nightOnly: nightOnly, requiresPro: requiresPro)
                job.scheduledByUser = scheduledByUser
                job.checkpoint = alreadyReviewed
                if alreadyReviewed?.isComplete == true { job.state = .completed; job.message = "Review ready" }
                jobs.append(job)
            }
            snapshot.localAnalysisJobs = jobs
        }
        guard model.persist() else { return false }
        if !nightOnly, continuedIdentifier != nil {
            systemJobIDs.formUnion((model.library.localAnalysisJobs ?? []).filter {
                $0.isPending && !$0.nightOnly && waitingReason(for: $0) == nil
            }.map(\.id))
        }
        scheduleOvernight()
        if !nightOnly {
            if let worker, let activeJobID, model.library.localAnalysisJobs?.first(where: { $0.id == activeJobID })?.nightOnly == true {
                worker.cancel()
                Task { [weak self] in
                    await worker.value
                    self?.startUserWork()
                }
            } else { startUserWork() }
        }
        else if isActive { conditionsChanged() }
        return true
    }

    func preferencesChanged() {
        guard let model else { return }
        // Ordinary automatic jobs created by older builds must adopt the same
        // speed policy as new imports. Explicit game selections keep their budget.
        let automaticJobs = (model.library.localAnalysisJobs ?? []).filter { $0.isPending && $0.level == nil && $0.scheduledByUser != true }
        var replacements: [(game: ChessGame, configuration: DeviceEngineConfiguration, requiresPro: Bool)] = []
        for job in automaticJobs {
            guard let game = model.library.games.first(where: { $0.id == job.gameID }) else { continue }
            let configuration = model.automaticConfiguration(for: game)
            guard !job.matches(configuration: configuration, level: nil) else { continue }
            mutate(job.id) { $0.state = .paused; $0.message = "Replaced by your automatic review settings. Saved decisions are retained." }
            replacements.append((game, configuration, job.requiresPro))
        }
        if let activeJobID, automaticJobs.contains(where: { $0.id == activeJobID }),
           replacements.contains(where: { replacement in automaticJobs.contains { $0.id == activeJobID && $0.gameID == replacement.game.id } }), let currentWorker = worker {
            currentWorker.cancel()
            Task { [weak self] in await currentWorker.value; self?.startUserWork() }
        }
        for replacement in replacements {
            enqueue(games: [replacement.game], configuration: replacement.configuration, requiresPro: replacement.requiresPro)
        }

        if model.overnightSettings.enabled {
            let level = Self.hardware.bounded(model.overnightSettings.level)
            guard Self.hardware.supports(level) else { model.notice = LocalAnalysisLevel.balanced.requirement; return }
            let configuration = model.deepConfiguration(level)
            if let activeJobID, let current = model.library.localAnalysisJobs?.first(where: { $0.id == activeJobID }),
               current.nightOnly && current.scheduledByUser != true && (!current.matches(configuration: configuration, level: level) || model.library.games.first(where: { $0.id == current.gameID }).map({ !model.allowsAutomaticDeepReview($0) }) == true) { worker?.cancel() }
            let eligibleIDs = Set(model.windowGames.filter { model.allowsAutomaticDeepReview($0) }.map(\.id))
            model.updateLibrary { snapshot in
                snapshot.localAnalysisJobs?.removeAll { $0.nightOnly && $0.scheduledByUser != true && $0.state != .completed && (!$0.matches(configuration: configuration, level: level) || !eligibleIDs.contains($0.gameID)) }
            }
            enqueue(games: model.windowGames.filter { model.allowsAutomaticDeepReview($0) }, configuration: configuration, level: level,
                    nightOnly: true, requiresPro: model.selectedWindow != .day)
        } else {
            if let activeJobID, model.library.localAnalysisJobs?.first(where: { $0.id == activeJobID }).map({ $0.nightOnly && $0.scheduledByUser != true }) == true {
                worker?.cancel()
            }
            model.updateLibrary { $0.localAnalysisJobs?.removeAll { $0.nightOnly && $0.scheduledByUser != true && $0.state != .completed } }
            _ = model.persist()
            scheduleOvernight()
        }
    }

    func sceneChanged(active: Bool) {
        isActive = active
        if active {
            if graceTask != .invalid { UIApplication.shared.endBackgroundTask(graceTask); graceTask = .invalid }
            conditionsChanged()
            startUserWork()
        }
        else {
            scheduleOvernight()
            if worker != nil, backgroundTask == nil, graceTask == .invalid, schedulerEnabled {
                graceTask = UIApplication.shared.beginBackgroundTask(withName: "Save chess analysis") { [weak self] in
                    Task { @MainActor in
                        guard let self, self.backgroundTask == nil, self.graceTask != .invalid else { return }
                        self.interrupt("Waiting for iOS to resume. Completed decisions are saved.")
                    }
                }
            }
        }
    }

    func pause() {
        guard let model else { return }
        model.updateLibrary { snapshot in
            for index in (snapshot.localAnalysisJobs ?? []).indices where snapshot.localAnalysisJobs?[index].isPending == true {
                snapshot.localAnalysisJobs?[index].state = .paused
                snapshot.localAnalysisJobs?[index].message = "Paused by you. Completed decisions are saved."
            }
        }
        _ = model.persist()
        worker?.cancel()
        if let continuedIdentifier { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: continuedIdentifier) }
        scheduleOvernight()
    }

    func clear() {
        worker?.cancel()
        if schedulerEnabled { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.overnightIdentifier) }
        if let continuedIdentifier { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: continuedIdentifier) }
    }

    private func startUserWork() {
        let eligibleManualJobs = (model?.library.localAnalysisJobs ?? []).filter { $0.isPending && !$0.nightOnly && waitingReason(for: $0) == nil }
        if schedulerEnabled, isActive, backgroundTask == nil, !continuedRequestPending, !eligibleManualJobs.isEmpty, #available(iOS 26.0, *) {
            let identifier = "com.chessme.app.analysis.continued." + UUID().uuidString
            prepareContinuedRequest(identifier: identifier, jobIDs: Set(eligibleManualJobs.map(\.id)))
            // Continued processing handlers may be registered after application launch.
            let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
                Task { @MainActor in await self?.accept(SystemAnalysisBackgroundTask(task)) }
            }
            if registered {
                continuedRequestPending = true
                let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Analyzing your games", subtitle: "On-device review")
                request.strategy = .fail
                do { try BGTaskScheduler.shared.submit(request) }
                catch {
                    continuedRequestPending = false
                    model?.notice = "iOS could not grant continuous background time. Analysis can run here and resume while charging."
                }
            } else {
                model?.notice = "iOS could not register background analysis. Completed decisions will still be saved."
            }
        }
        start()
    }

    func prepareContinuedRequest(identifier: String, jobIDs: Set<String>) {
        continuedIdentifier = identifier
        systemJobIDs = jobIDs
        lastSystemSubtitle = nil
    }

    func accept(_ task: any AnalysisBackgroundTask) async {
        if task.isContinued {
            // A grant may arrive after foreground work completed and a newer
            // batch started. Never attach an old grant to that newer worker.
            guard task.identifier == continuedIdentifier else {
                let finished = completedContinuedRequests.contains(task.identifier)
                if finished { task.progress.totalUnitCount = 1; task.progress.completedUnitCount = 1 }
                task.complete(success: finished)
                return
            }
            continuedRequestPending = false
        }
        guard backgroundTask == nil else { task.complete(success: false); return }
        backgroundTask = task
        // A granted processing task replaces the short UIKit grace period.
        // Its old expiration must not cancel the longer-running review.
        if graceTask != .invalid { UIApplication.shared.endBackgroundTask(graceTask); graceTask = .invalid }
        let identifier = task.identifier
        task.onExpiration { [weak self] in
            Task { @MainActor in
                guard let self, self.backgroundTask?.identifier == identifier else { return }
                self.interrupt("Waiting for iOS to resume. Completed decisions are saved.")
            }
        }
        await model?.subscriptions.refreshEntitlements()
        guard backgroundTask?.identifier == identifier else { return }
        updateSystemProgress()
        start()
        if worker == nil {
            let finished = !systemJobIDs.isEmpty && (model?.library.localAnalysisJobs ?? []).filter { systemJobIDs.contains($0.id) }.allSatisfy { $0.state == .completed }
            finishBackground(success: finished); scheduleOvernight()
        }
    }

    private func waitingReason(for job: LocalAnalysisJob) -> String? {
        guard let model else { return "Library unavailable" }
        if job.requiresPro && !model.subscriptions.isPro { return "Pro access is needed to resume this review." }
        if let level = job.level, !Self.hardware.supports(level) { return level.requirement }
        if let memoryPressureUntil, Date() < memoryPressureUntil { return "Waiting for device memory to recover." }
        if job.configuration.engine == .stockfish,
           LocalAnalysisMemoryPolicy.cacheMegabytes(requested: job.configuration.memoryMB, availableToAppMB: availableMemoryMB()) == nil {
            return LocalAnalysisResourceError.insufficientMemory.localizedDescription
        }
        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical { return "Waiting for your device to cool down." }
        if job.level != nil && ProcessInfo.processInfo.isLowPowerModeEnabled { return "Waiting for Low Power Mode to turn off." }
        if job.nightOnly {
            guard job.scheduledByUser == true || model.overnightSettings.enabled else { return "Overnight analysis is off." }
            guard OvernightAnalysisSettings.isNight(Date()) else { return "Waiting for tonight, after 10 pm." }
            guard [.charging, .full].contains(UIDevice.current.batteryState) else { return "Waiting for charging." }
            if backgroundTask?.isContinued == true {
                return "Waiting for the overnight processing window."
            }
        }
        if !isActive && backgroundTask == nil && graceTask == .invalid { return "Waiting for background processing time." }
        return nil
    }

    private func conditionsChanged() {
        guard let model else { return }
        if let activeJobID, let job = model.library.localAnalysisJobs?.first(where: { $0.id == activeJobID }),
           let reason = waitingReason(for: job) { interrupt(reason) }
        else { start() }
        scheduleOvernight()
    }

    private func handleMemoryPressure() {
        memoryPressureUntil = Date().addingTimeInterval(60)
        interrupt("Waiting for device memory to recover. Completed decisions are saved.")
        memoryRecovery?.cancel()
        memoryRecovery = nil
        scheduleMemoryRecovery()
    }

    private func scheduleMemoryRecovery() {
        guard memoryRecovery == nil else { return }
        memoryRecovery = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            self?.memoryPressureUntil = nil
            self?.memoryRecovery = nil
            self?.conditionsChanged()
        }
    }

    private func start() {
        guard worker == nil, let model, !model.isImporting, !model.cloudIsRunning else { return }
        let jobs = model.library.localAnalysisJobs ?? []
        guard nextJob() != nil else {
            for job in jobs where job.state == .queued { mutate(job.id) { $0.message = waitingReason(for: job) } }
            if jobs.contains(where: { $0.state == .queued && $0.configuration.engine == .stockfish &&
                LocalAnalysisMemoryPolicy.cacheMegabytes(requested: $0.configuration.memoryMB, availableToAppMB: availableMemoryMB()) == nil }) {
                Task.detached(priority: .utility) { StockfishEngine.trimMemory() }
                scheduleMemoryRecovery()
            }
            _ = model.persist()
            return
        }
        // Publish admission synchronously so callers cannot mistake a queued
        // worker for idle and begin an overlapping import.
        model.deviceAnalysisState(running: true, progress: 0, message: "Starting on-device analysis")
        worker = Task { [weak self] in await self?.process() }
    }

    private func nextJob() -> LocalAnalysisJob? {
        let eligible = (model?.library.localAnalysisJobs ?? []).filter { $0.state == .queued && waitingReason(for: $0) == nil }
        // A deep review selected by the player goes before bulk imports and
        // automatic overnight work. Searches remain serial and checkpointed.
        return eligible.first { !$0.nightOnly && $0.level != nil }
            ?? eligible.first { !$0.nightOnly }
            ?? eligible.first
    }

    private func process() async {
        guard let model else { return }
        interruptionReason = nil
        model.deviceAnalysisState(running: true, progress: 0, message: "Starting on-device analysis")
        var successful = true
        defer {
            worker = nil; activeJobID = nil
            model.deviceAnalysisState(running: false, progress: model.progress, message: model.progressMessage)
            model.schedulePuzzleMatches()
            if backgroundTask?.isContinued == true {
                successful = successful && !systemJobIDs.isEmpty && (model.library.localAnalysisJobs ?? [])
                    .filter { systemJobIDs.contains($0.id) }.allSatisfy { $0.state == .completed }
            }
            finishBackground(success: successful)
            scheduleOvernight()
        }
        while !Task.isCancelled {
            guard let job = nextJob() else { break }
            if let ready = model.completeDeviceReview(for: job.gameID, covering: job.configuration) {
                mutate(job.id) { $0.checkpoint = ready; $0.state = .completed; $0.message = "Review ready" }
                model.acceptDeviceCheckpoint(ready)
                guard model.persist() else {
                    mutate(job.id) { $0.state = .paused; $0.message = "Review paused because the checkpoint could not be saved." }
                    successful = false
                    break
                }
                updateSystemProgress()
                continue
            }
            guard let game = model.library.games.first(where: { $0.id == job.gameID }), game.isFinished else {
                mutate(job.id) { $0.state = .failed; $0.message = "Only saved, finished games can be analyzed." }
                _ = model.persist(); successful = false; continue
            }
            activeJobID = job.id; withinDecisionProgress = 0
            activeJobTotalDecisions = (try? GameReplay(game: game).positions.dropLast().filter { $0.sideToMove == game.playerSide }.count) ?? 40
            model.deviceAnalysisDepth = 0
            mutate(job.id) { $0.state = .running; $0.message = "Analyzing with \(job.configuration.engine.title)" }
            guard model.persist() else {
                mutate(job.id) { $0.state = .paused; $0.message = "Review paused because the checkpoint could not be saved." }
                successful = false; break
            }
            var options = job.configuration.options
            options.maximumPositions = 1
            let workOptions = options
            let checkpoint = job.checkpoint
            model.deviceAnalysisState(running: true, progress: job.progress, message: "Analyzing \(game.label)")
            let decisionStarted = ProcessInfo.processInfo.systemUptime
            do {
                let work = Task.detached(priority: .utility) { [weak self] in
                    try LocalAnalyzer(options: workOptions).analyze(game: game, previousAnalysis: checkpoint,
                        cancellation: { Task.isCancelled }, evaluationUpdate: { snapshot in
                            Task { @MainActor [weak self] in
                                guard let self, self.activeJobID == job.id else { return }
                                let depthProgress = Double(snapshot.completedDepth) / Double(workOptions.maximumDepth) * 0.45
                                let workProgress = Double(snapshot.nodes) / Double(max(1, workOptions.searchNodeLimit ?? 3_000_000)) * 0.45
                                let timeProgress = (snapshot.elapsedSeconds ?? 0) / max(0.01, workOptions.timeLimitSeconds ?? 3) * 0.9
                                self.withinDecisionProgress = max(self.withinDecisionProgress, min(0.9, max(depthProgress + workProgress, timeProgress)))
                                self.model?.deviceAnalysisDepth = snapshot.completedDepth
                                self.updateSystemProgress()
                            }
                        })
                }
                let analysis = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
                try Task.checkCancellation()
                guard analysis.isComplete || analysis.analyzedPlies > (checkpoint?.analyzedPlies ?? 0) else {
                    throw ChessError.invalidPGN("The engine made no further progress.")
                }
                let elapsed = ProcessInfo.processInfo.systemUptime - decisionStarted
                let completedDecisions = analysis.analyzedPlies - (checkpoint?.analyzedPlies ?? 0)
                mutate(job.id) {
                    $0.checkpoint = analysis
                    $0.processingSeconds = ($0.processingSeconds ?? 0) + elapsed
                    $0.timedDecisions = ($0.timedDecisions ?? 0) + completedDecisions
                    $0.state = analysis.isComplete ? .completed : .queued
                    $0.message = analysis.isComplete ? "Review ready" : "\(analysis.analyzedPlies)/\(analysis.totalPlies) decisions saved"
                }
                if analysis.isComplete, job.configuration.engine == .stockfish, let level = job.level,
                   let finished = model.library.localAnalysisJobs?.first(where: { $0.id == job.id }),
                   finished.timedDecisions == analysis.totalPlies, let seconds = finished.processingSeconds {
                    model.recordLocalAnalysisTiming(LocalAnalysisTiming(level: level,
                        configurationID: job.configuration.options.configurationID, engineVersion: analysis.engineVersion,
                        hardwareIdentifier: Self.hardware.modelIdentifier, decisions: analysis.totalPlies, seconds: seconds))
                }
                model.acceptDeviceCheckpoint(analysis)
                let message = analysis.isComplete ? "Your on-device review is ready" : "\(analysis.analyzedPlies)/\(analysis.totalPlies) decisions saved"
                model.deviceAnalysisState(running: true, progress: Double(analysis.analyzedPlies) / Double(max(1, analysis.totalPlies)), message: message)
                guard model.persist() else {
                    mutate(job.id) { $0.state = .paused; $0.message = "Review paused because the checkpoint could not be saved." }
                    successful = false; break
                }
                withinDecisionProgress = 0
                updateSystemProgress()
                if !analysis.isComplete, let reason = waitingReason(for: job) { mutate(job.id) { $0.message = reason }; successful = false }
            } catch LocalAnalysisResourceError.insufficientMemory {
                successful = false
                mutate(job.id) { $0.state = .queued }
                handleMemoryPressure()
                break
            } catch {
                successful = false
                if Task.isCancelled {
                    let reason = interruptionReason ?? "Waiting to resume. Completed decisions are saved."
                    mutate(job.id) { if $0.state == .running { $0.state = .queued }; if $0.state != .paused { $0.message = reason } }
                    _ = model.persist(); break
                }
                mutate(job.id) { $0.state = .failed; $0.message = error.localizedDescription }
                model.notice = error.localizedDescription
                _ = model.persist()
            }
        }
    }

    private func mutate(_ id: String, _ change: (inout LocalAnalysisJob) -> Void) {
        model?.updateLibrary { snapshot in
            guard let index = snapshot.localAnalysisJobs?.firstIndex(where: { $0.id == id }) else { return }
            change(&snapshot.localAnalysisJobs![index])
        }
    }

    private func interrupt(_ reason: String) {
        interruptionReason = reason
        if let activeJobID { mutate(activeJobID) { $0.message = reason } }
        _ = model?.persist()
        worker?.cancel()
        if worker == nil { finishBackground(success: false) }
    }

    private func updateSystemProgress() {
        guard let model else { return }
        if let activeJobID, let job = model.library.localAnalysisJobs?.first(where: { $0.id == activeJobID }) {
            let fraction = min(1, job.progress + withinDecisionProgress / Double(max(1, job.checkpoint?.totalPlies ?? activeJobTotalDecisions)))
            model.deviceAnalysisState(running: true, progress: fraction, message: model.progressMessage)
        }
        guard let task = backgroundTask, task.isContinued else { return }
        let jobs = (model.library.localAnalysisJobs ?? []).filter { systemJobIDs.contains($0.id) }
        task.progress.totalUnitCount = Int64(max(1, jobs.count) * 1_000)
        let done = jobs.reduce(0.0) { total, job in
            let additional = job.id == activeJobID ? withinDecisionProgress / Double(max(1, job.checkpoint?.totalPlies ?? activeJobTotalDecisions)) : 0
            return total + min(1, job.progress + additional)
        }
        task.progress.completedUnitCount = max(task.progress.completedUnitCount, Int64(done * 1_000))
        let games = Dictionary(grouping: jobs, by: \.gameID)
        let completed = games.values.filter { $0.allSatisfy { $0.state == .completed || $0.checkpoint?.isComplete == true } }.count
        let subtitle = completed == games.count ? "Reviewed \(completed)/\(games.count) games" : "Reviewing game \(completed + 1)/\(games.count)"
        if subtitle != lastSystemSubtitle {
            task.updateTitle("Analyzing your games", subtitle: subtitle)
            lastSystemSubtitle = subtitle
        }
    }

    private func finishBackground(success: Bool) {
        if success, let identifier = continuedIdentifier, !systemJobIDs.isEmpty,
           (model?.library.localAnalysisJobs ?? []).filter({ systemJobIDs.contains($0.id) }).allSatisfy({ $0.state == .completed }) {
            completedContinuedRequests.append(identifier)
            completedContinuedRequests = Array(completedContinuedRequests.suffix(12))
        }
        if success, let task = backgroundTask, task.isContinued {
            task.progress.totalUnitCount = max(1, task.progress.totalUnitCount)
            task.progress.completedUnitCount = task.progress.totalUnitCount
        }
        backgroundTask?.complete(success: success)
        backgroundTask = nil
        if continuedRequestPending, let continuedIdentifier { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: continuedIdentifier) }
        continuedRequestPending = false
        continuedIdentifier = nil
        if !isActive || memoryPressureUntil != nil { Task.detached(priority: .utility) { StockfishEngine.trimMemory() } }
        if graceTask != .invalid { UIApplication.shared.endBackgroundTask(graceTask); graceTask = .invalid }
    }

    private func scheduleOvernight() {
        guard schedulerEnabled, let model else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.overnightIdentifier)
        let jobs = (model.library.localAnalysisJobs ?? []).filter(\.isPending)
        guard !jobs.isEmpty else { return }
        let request = BGProcessingTaskRequest(identifier: Self.overnightIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = jobs.allSatisfy(\.nightOnly) ? OvernightAnalysisSettings.nextOpportunity(after: Date()) : Date().addingTimeInterval(60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { model.notice = "Background analysis is unavailable right now. Open chess-me to resume saved work." }
    }
}
