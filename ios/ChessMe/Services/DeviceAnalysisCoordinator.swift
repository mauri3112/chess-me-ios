import Foundation
import UIKit
import BackgroundTasks
import ChessMeCore

@MainActor
final class DeviceAnalysisCoordinator {
    static let overnightIdentifier = "com.chessme.app.analysis.overnight"
    private weak var model: AppModel?
    private var worker: Task<Void, Never>?
    private var backgroundTask: BGTask?
    private var graceTask: UIBackgroundTaskIdentifier = .invalid
    private var observers: [NSObjectProtocol] = []
    private var isActive = true
    private var activeJobID: String?
    private var withinDecisionProgress = 0.0
    private var continuedIdentifier: String?
    private var continuedRequestPending = false
    private var systemJobIDs = Set<String>()
    private var memoryPressureUntil: Date?
    private var memoryRecovery: Task<Void, Never>?
    private let schedulerEnabled: Bool

    init(model: AppModel, schedulerEnabled: Bool = true) {
        self.model = model; self.schedulerEnabled = schedulerEnabled
        isActive = UIApplication.shared.applicationState != .background
        if schedulerEnabled {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.overnightIdentifier, using: nil) { [weak self] task in
                Task { @MainActor in await self?.accept(task) }
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
        if model.library.localAnalysisJobs?.isEmpty == false { _ = model.persist() }
    }

    static var hardware: LocalAnalysisHardware {
        #if targetEnvironment(simulator)
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

    func enqueue(games: [ChessGame], configuration: DeviceEngineConfiguration, level: LocalAnalysisLevel? = nil,
                 nightOnly: Bool = false, requiresPro: Bool = false) {
        guard let model, model.canSaveLibrary else { return }
        if let level, !Self.hardware.supports(level) { model.notice = level.requirement; return }
        model.updateLibrary { snapshot in
            var jobs = snapshot.localAnalysisJobs ?? []
            for game in games where game.isFinished {
                let signature = configuration.options.configurationID
                if let existing = jobs.firstIndex(where: { $0.gameID == game.id && $0.configuration.options.configurationID == signature }) {
                    if !nightOnly {
                        jobs[existing].nightOnly = false
                        jobs[existing].requiresPro = requiresPro
                        if [.paused, .failed].contains(jobs[existing].state) { jobs[existing].state = .queued; jobs[existing].message = nil }
                    }
                    continue
                }
                let alreadyReviewed = (snapshot.analyses + (snapshot.analysisHistory ?? [])).first {
                    $0.gameID == game.id && $0.source == "device" && $0.configurationID == signature &&
                    $0.engineVersion == LocalAnalyzer(options: configuration.options).engineVersion
                }
                var job = LocalAnalysisJob(gameID: game.id, configuration: configuration, level: level, nightOnly: nightOnly, requiresPro: requiresPro)
                job.checkpoint = alreadyReviewed
                if alreadyReviewed?.isComplete == true { job.state = .completed }
                jobs.append(job)
            }
            snapshot.localAnalysisJobs = jobs
        }
        guard model.persist() else { return }
        if !nightOnly, continuedIdentifier != nil {
            systemJobIDs.formUnion((model.library.localAnalysisJobs ?? []).filter { $0.isPending && !$0.nightOnly }.map(\.id))
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
        else if isActive { start() }
    }

    func preferencesChanged() {
        guard let model else { return }
        if model.overnightSettings.enabled {
            let level = Self.hardware.bounded(model.overnightSettings.level)
            guard Self.hardware.supports(level) else { model.notice = LocalAnalysisLevel.balanced.requirement; return }
            let configuration = model.deepConfiguration(level)
            if let activeJobID, let current = model.library.localAnalysisJobs?.first(where: { $0.id == activeJobID }),
               current.nightOnly && current.configuration != configuration { worker?.cancel() }
            model.updateLibrary { snapshot in
                snapshot.localAnalysisJobs?.removeAll { $0.nightOnly && $0.state != .completed && $0.configuration != configuration }
            }
            enqueue(games: model.windowGames, configuration: configuration, level: level,
                    nightOnly: true, requiresPro: model.selectedWindow != .day)
        } else {
            if let activeJobID, model.library.localAnalysisJobs?.first(where: { $0.id == activeJobID })?.nightOnly == true {
                worker?.cancel()
            }
            model.updateLibrary { $0.localAnalysisJobs?.removeAll { $0.nightOnly && $0.state != .completed } }
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
            continuedIdentifier = identifier
            systemJobIDs = Set(eligibleManualJobs.map(\.id))
            // Continued processing handlers may be registered after application launch.
            let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
                Task { @MainActor in await self?.accept(task) }
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

    private func accept(_ task: BGTask) async {
        if #available(iOS 26.0, *), task is BGContinuedProcessingTask { continuedRequestPending = false }
        guard backgroundTask == nil else { task.setTaskCompleted(success: false); return }
        backgroundTask = task
        // A granted processing task replaces the short UIKit grace period.
        // Its old expiration must not cancel the longer-running review.
        if graceTask != .invalid { UIApplication.shared.endBackgroundTask(graceTask); graceTask = .invalid }
        task.expirationHandler = { [weak self] in
            Task { @MainActor in self?.interrupt("Waiting for iOS to resume. Completed decisions are saved.") }
        }
        await model?.subscriptions.refreshEntitlements()
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
        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical { return "Waiting for your device to cool down." }
        if job.level != nil && ProcessInfo.processInfo.isLowPowerModeEnabled { return "Waiting for Low Power Mode to turn off." }
        if job.nightOnly {
            guard model.overnightSettings.enabled else { return "Overnight analysis is off." }
            guard OvernightAnalysisSettings.isNight(Date()) else { return "Waiting for tonight, after 10 pm." }
            guard [.charging, .full].contains(UIDevice.current.batteryState) else { return "Waiting for charging." }
            if #available(iOS 26.0, *), backgroundTask is BGContinuedProcessingTask {
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
        memoryRecovery = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            self?.memoryPressureUntil = nil
            self?.conditionsChanged()
        }
    }

    private func start() {
        guard worker == nil, let model, !model.isImporting, !model.cloudIsRunning else { return }
        let jobs = model.library.localAnalysisJobs ?? []
        guard nextJob() != nil else {
            for job in jobs where job.state == .queued { mutate(job.id) { $0.message = waitingReason(for: job) } }
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
        model.deviceAnalysisState(running: true, progress: 0, message: "Starting on-device analysis")
        var successful = true
        defer {
            worker = nil; activeJobID = nil
            model.deviceAnalysisState(running: false, progress: model.progress, message: model.progressMessage)
            model.schedulePuzzleMatches()
            if #available(iOS 26.0, *), backgroundTask is BGContinuedProcessingTask {
                successful = successful && !systemJobIDs.isEmpty && (model.library.localAnalysisJobs ?? [])
                    .filter { systemJobIDs.contains($0.id) }.allSatisfy { $0.state == .completed }
            }
            finishBackground(success: successful)
            scheduleOvernight()
        }
        while !Task.isCancelled {
            guard let job = nextJob() else { break }
            guard let game = model.library.games.first(where: { $0.id == job.gameID }), game.isFinished else {
                mutate(job.id) { $0.state = .failed; $0.message = "Only saved, finished games can be analyzed." }
                _ = model.persist(); successful = false; continue
            }
            activeJobID = job.id; withinDecisionProgress = 0
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
            do {
                let work = Task.detached(priority: .utility) { [weak self] in
                    try LocalAnalyzer(options: workOptions).analyze(game: game, previousAnalysis: checkpoint,
                        cancellation: { Task.isCancelled }, evaluationUpdate: { snapshot in
                            Task { @MainActor [weak self] in
                                guard let self, self.activeJobID == job.id else { return }
                                let depthProgress = Double(snapshot.completedDepth) / Double(workOptions.maximumDepth) * 0.45
                                let workProgress = Double(snapshot.nodes) / Double(max(1, workOptions.searchNodeLimit ?? 3_000_000)) * 0.45
                                self.withinDecisionProgress = max(self.withinDecisionProgress, min(0.9, depthProgress + workProgress))
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
                mutate(job.id) {
                    $0.checkpoint = analysis
                    $0.state = analysis.isComplete ? .completed : .queued
                    $0.message = analysis.isComplete ? "Review ready" : "\(analysis.analyzedPlies)/\(analysis.totalPlies) decisions saved"
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
            } catch {
                successful = false
                if Task.isCancelled {
                    mutate(job.id) { if $0.state == .running { $0.state = .queued }; if $0.state != .paused { $0.message = "Waiting to resume. Completed decisions are saved." } }
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
        if let activeJobID { mutate(activeJobID) { $0.message = reason } }
        _ = model?.persist()
        worker?.cancel()
        if worker == nil { finishBackground(success: false) }
    }

    private func updateSystemProgress() {
        guard #available(iOS 26.0, *), let task = backgroundTask as? BGContinuedProcessingTask, let model else { return }
        let jobs = (model.library.localAnalysisJobs ?? []).filter { systemJobIDs.contains($0.id) }
        task.progress.totalUnitCount = Int64(max(1, jobs.count) * 1_000)
        let done = jobs.reduce(0.0) { total, job in
            let additional = job.id == activeJobID ? withinDecisionProgress / Double(max(1, job.checkpoint?.totalPlies ?? 40)) : 0
            return total + min(1, job.progress + additional)
        }
        task.progress.completedUnitCount = max(task.progress.completedUnitCount, Int64(done * 1_000))
        task.updateTitle("Analyzing your games", subtitle: model.progressMessage)
    }

    private func finishBackground(success: Bool) {
        backgroundTask?.setTaskCompleted(success: success)
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
