import XCTest
import ChessMeCore
@testable import ChessMe

private actor InsightsCalculationGate {
    private var requests: [(InsightsReportInput, CheckedContinuation<LearningInsights, Never>)] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func calculate(_ input: InsightsReportInput) async -> LearningInsights {
        await withCheckedContinuation { continuation in
            requests.append((input, continuation))
            let ready = waiters.filter { $0.0 <= requests.count }
            waiters.removeAll { $0.0 <= requests.count }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForRequests(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func finish(_ index: Int) {
        let (input, continuation) = requests[index]
        continuation.resume(returning: LearningInsights(games: input.games, analyses: input.analyses,
                                                        review: input.review, username: input.username))
    }
}

@MainActor
final class InsightsReportControllerTests: XCTestCase {
    private func input(_ count: Int) -> InsightsReportInput {
        let games = (0..<count).map {
            ChessGame(id: "insights-\($0)", username: "Learner", white: "Learner", black: "Partner",
                      playedAt: Date(), playerSide: .white, moves: "e4 e5", status: "resign", result: .whiteWin)
        }
        return InsightsReportInput(games: games, analyses: [], review: ReviewLibrary(), username: "Learner")
    }

    func testOlderSamePlayerCalculationCannotOverwriteNewerEvidence() async {
        let gate = InsightsCalculationGate()
        let controller = InsightsReportController { await gate.calculate($0) }
        let old = input(1), latest = input(2)
        let first = Task { await controller.refresh(old) }
        await gate.waitForRequests(1)
        let second = Task { await controller.refresh(latest) }
        await gate.waitForRequests(2)
        await gate.finish(1)
        await second.value
        XCTAssertEqual(controller.report(for: latest)?.results.games, 2)
        await gate.finish(0)
        await first.value
        XCTAssertEqual(controller.report(for: latest)?.results.games, 2)
        XCTAssertNil(controller.report(for: old))
    }

    func testDeletionHidesPublishedEvidenceAndRejectsPendingOldSnapshot() async {
        let gate = InsightsCalculationGate()
        let controller = InsightsReportController { await gate.calculate($0) }
        let original = input(1), deleted = input(0)
        let first = Task { await controller.refresh(original) }
        await gate.waitForRequests(1)
        await gate.finish(0)
        await first.value
        XCTAssertNotNil(controller.report(for: original))
        XCTAssertNil(controller.report(for: deleted), "Deleted evidence must disappear before replacement work starts")
        let pending = Task { await controller.refresh(original) }
        await gate.waitForRequests(2)
        let replacement = Task { await controller.refresh(deleted) }
        await gate.waitForRequests(3)
        await gate.finish(2)
        await replacement.value
        await gate.finish(1)
        await pending.value
        XCTAssertEqual(controller.report(for: deleted)?.results.games, 0)
        XCTAssertNil(controller.report(for: original))
    }

    func testCancellationRejectsCalculationThatIgnoresCancellation() async {
        let gate = InsightsCalculationGate()
        let controller = InsightsReportController { await gate.calculate($0) }
        let snapshot = input(1)
        let request = Task { await controller.refresh(snapshot) }
        await gate.waitForRequests(1)
        request.cancel()
        await gate.finish(0)
        await request.value
        XCTAssertNil(controller.report)
        XCTAssertNil(controller.report(for: snapshot))
    }

    func testLeavingScreenClearsReportAndInvalidatesPendingWork() async {
        let gate = InsightsCalculationGate()
        let controller = InsightsReportController { await gate.calculate($0) }
        let snapshot = input(1)
        let request = Task { await controller.refresh(snapshot) }
        await gate.waitForRequests(1)
        controller.cancel()
        await gate.finish(0)
        await request.value
        XCTAssertNil(controller.report)
    }

    func testEvidenceIdentityTracksAttemptsEvenWhenGamesAndPlayerStaySame() {
        let original = input(1)
        var review = original.review
        review.attempts.append(ReviewPracticeAttempt(targetID: "target", evidenceRevision: "1", rootFEN: ChessPosition.initial.fen))
        let changed = InsightsReportInput(games: original.games, analyses: original.analyses, review: review, username: original.username)
        XCTAssertNotEqual(original, changed)
    }
}
