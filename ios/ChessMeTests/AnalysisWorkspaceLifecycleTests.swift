import XCTest
@testable import ChessMe

final class AnalysisWorkspaceLifecycleTests: XCTestCase {
    func testHiddenConfigurationAndForegroundChangesDoNotRestartSearch() {
        var lifecycle = AnalysisWorkspaceLifecycle()
        XCTAssertEqual(lifecycle.handle(.appeared(active: true, reviewRunning: false)), .none)
        XCTAssertEqual(lifecycle.handle(.requested), .start)
        XCTAssertEqual(lifecycle.handle(.disappeared), .stop)
        XCTAssertEqual(lifecycle.handle(.configurationChanged), .none)
        XCTAssertEqual(lifecycle.handle(.activeChanged(false)), .none)
        XCTAssertEqual(lifecycle.handle(.activeChanged(true)), .none)
        XCTAssertTrue(lifecycle.requested)
        XCTAssertEqual(lifecycle.handle(.appeared(active: true, reviewRunning: false)), .start)
    }

    func testReviewStartingStopsSearchAndCompletionResumesRequestedStudy() {
        var lifecycle = AnalysisWorkspaceLifecycle()
        _ = lifecycle.handle(.appeared(active: true, reviewRunning: false))
        XCTAssertEqual(lifecycle.handle(.requested), .start)
        XCTAssertEqual(lifecycle.handle(.reviewRunningChanged(true)), .stop)
        XCTAssertTrue(lifecycle.waitingForReview)
        XCTAssertEqual(lifecycle.handle(.configurationChanged), .none)
        XCTAssertEqual(lifecycle.handle(.reviewRunningChanged(false)), .start)
        XCTAssertFalse(lifecycle.waitingForReview)
    }

    func testRequestDuringReviewWaitsAndExplicitStopCancelsResume() {
        var lifecycle = AnalysisWorkspaceLifecycle()
        _ = lifecycle.handle(.appeared(active: true, reviewRunning: true))
        XCTAssertEqual(lifecycle.handle(.requested), .none)
        XCTAssertTrue(lifecycle.waitingForReview)
        XCTAssertEqual(lifecycle.handle(.stopped), .none)
        XCTAssertFalse(lifecycle.requested)
        XCTAssertFalse(lifecycle.waitingForReview)
        XCTAssertEqual(lifecycle.handle(.reviewRunningChanged(false)), .none)
    }

    func testReviewCompletionWhileHiddenOrInactiveCannotStartSearch() {
        var lifecycle = AnalysisWorkspaceLifecycle()
        _ = lifecycle.handle(.appeared(active: true, reviewRunning: false))
        _ = lifecycle.handle(.requested)
        _ = lifecycle.handle(.reviewRunningChanged(true))
        _ = lifecycle.handle(.disappeared)
        XCTAssertEqual(lifecycle.handle(.reviewRunningChanged(false)), .none)
        XCTAssertEqual(lifecycle.handle(.appeared(active: false, reviewRunning: false)), .none)
        XCTAssertEqual(lifecycle.handle(.configurationChanged), .none)
        XCTAssertEqual(lifecycle.handle(.activeChanged(true)), .start)
    }

    func testReappearanceUsesCurrentBusyStateAndConfigurationRestartsVisibleSearch() {
        var lifecycle = AnalysisWorkspaceLifecycle()
        _ = lifecycle.handle(.appeared(active: true, reviewRunning: false))
        _ = lifecycle.handle(.requested)
        XCTAssertEqual(lifecycle.handle(.configurationChanged), .start)
        _ = lifecycle.handle(.disappeared)
        XCTAssertEqual(lifecycle.handle(.appeared(active: true, reviewRunning: true)), .none)
        XCTAssertTrue(lifecycle.waitingForReview)
        XCTAssertEqual(lifecycle.handle(.reviewRunningChanged(false)), .start)
        XCTAssertEqual(lifecycle.handle(.activeChanged(false)), .stop)
        XCTAssertEqual(lifecycle.handle(.configurationChanged), .none)
    }
}
