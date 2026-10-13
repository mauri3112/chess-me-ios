import Foundation
import BackgroundTasks

@MainActor
protocol AnalysisBackgroundTask: AnyObject {
    var identifier: String { get }
    var isContinued: Bool { get }
    var progress: Progress { get }
    func onExpiration(_ handler: @escaping @Sendable () -> Void)
    func updateTitle(_ title: String, subtitle: String)
    func complete(success: Bool)
}

@MainActor
final class SystemAnalysisBackgroundTask: AnalysisBackgroundTask {
    private let task: BGTask
    private let fallbackProgress = Progress(totalUnitCount: 0)
    init(_ task: BGTask) { self.task = task }
    var identifier: String { task.identifier }
    var isContinued: Bool {
        if #available(iOS 26.0, *) { return task is BGContinuedProcessingTask }
        return false
    }
    var progress: Progress {
        if #available(iOS 26.0, *), let continued = task as? BGContinuedProcessingTask { return continued.progress }
        return fallbackProgress
    }
    func onExpiration(_ handler: @escaping @Sendable () -> Void) { task.expirationHandler = handler }
    func updateTitle(_ title: String, subtitle: String) {
        if #available(iOS 26.0, *), let continued = task as? BGContinuedProcessingTask {
            continued.updateTitle(title, subtitle: subtitle)
        }
    }
    func complete(success: Bool) { task.setTaskCompleted(success: success) }
}
