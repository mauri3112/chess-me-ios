import Foundation

/// Ties engine work to the visible study and yields to saved-game reviews.
struct AnalysisWorkspaceLifecycle {
    enum Event {
        case appeared(active: Bool, reviewRunning: Bool)
        case disappeared
        case activeChanged(Bool)
        case reviewRunningChanged(Bool)
        case configurationChanged
        case requested
        case stopped
    }
    enum Effect: Equatable { case none, start, stop }
    private(set) var requested = false
    private(set) var visible = false
    private var active = false
    private var reviewRunning = false
    private var eligible: Bool { requested && visible && active && !reviewRunning }
    var waitingForReview: Bool { requested && visible && active && reviewRunning }

    mutating func handle(_ event: Event) -> Effect {
        let wasEligible = eligible
        var restart = false
        switch event {
        case let .appeared(active, reviewRunning):
            visible = true; self.active = active; self.reviewRunning = reviewRunning
        case .disappeared: visible = false
        case let .activeChanged(value): active = value
        case let .reviewRunningChanged(value): reviewRunning = value
        case .configurationChanged: restart = true
        case .requested: requested = true; restart = true
        case .stopped: requested = false
        }
        if eligible { return !wasEligible || restart ? .start : .none }
        return wasEligible ? .stop : .none
    }
}
