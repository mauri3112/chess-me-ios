import XCTest
import SwiftUI
import ChessMeCore
@testable import ChessMe

final class SavedLineRehearsalNativeTests: XCTestCase {
    private func savedLine() throws -> SavedReviewLine {
        let game = ChessGame(id: "removed-source", username: "Learner", white: "Learner", black: "Opponent",
                             playedAt: Date(), playerSide: .white, moves: "", status: "resign")
        var replay = try GameReplay(game: game)
        for uci in ["e2e4", "e7e5", "g1f3"] { try replay.play(ChessMove(uci: uci)) }
        return try SavedReviewLine(game: game, replay: replay)
    }

    @MainActor
    func testRetainedLineCanOpenWithoutItsSourceGame() throws {
        let line = try savedLine()
        let model = AppModel(previewLibrary: LibrarySnapshot())
        model.changeReview { $0.savedLines = [line] }
        let controller = UIHostingController(rootView: SavedLineRehearsalView(lineID: line.id).environmentObject(model))
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        XCTAssertNotNil(controller.view)
        XCTAssertTrue(model.library.games.isEmpty)
        var session = SavedLineRehearsalSession()
        session.synchronize(line: model.reviewState.savedLines.first, context: model.reviewGeneration)
        XCTAssertNotNil(session.run)
        session.submit(try ChessMove(uci: "e2e4"))
        XCTAssertTrue(session.run?.awaitingReply == true)
    }

    @MainActor
    func testDeletionDiscardsPrivateSourceAndRejectsItsPendingReply() throws {
        let line = try savedLine()
        let model = AppModel(previewLibrary: LibrarySnapshot())
        model.changeReview { $0.savedLines = [line] }
        var session = SavedLineRehearsalSession()
        session.synchronize(line: line, context: model.reviewGeneration)
        session.submit(try ChessMove(uci: "e2e4"))
        let token = try XCTUnwrap(session.replyToken)
        session.selected = 12
        session.promotions = [ChessMove(from: 48, to: 56, promotion: .queen)]
        model.deleteLocalData()
        let current = model.reviewState.savedLines.first { $0.id == line.id }
        XCTAssertFalse(session.matches(line: current, context: model.reviewGeneration), "Hide the board before lifecycle synchronization runs")
        XCTAssertFalse(session.playReply(token, line: current, context: model.reviewGeneration))
        session.synchronize(line: current, context: model.reviewGeneration)
        XCTAssertNil(session.source)
        XCTAssertNil(session.run)
        XCTAssertNil(session.selected)
        XCTAssertTrue(session.promotions.isEmpty)
        XCTAssertNil(session.replyToken)
        XCTAssertFalse(session.playReply(token, line: current, context: model.reviewGeneration))
    }

    func testSingleLineRemovalInvalidatesRunWithoutAContextChange() throws {
        let line = try savedLine(), context = UUID()
        var session = SavedLineRehearsalSession()
        session.synchronize(line: line, context: context)
        session.submit(try ChessMove(uci: "e2e4"))
        let oldReply = try XCTUnwrap(session.replyToken)
        XCTAssertFalse(session.matches(line: nil, context: context))
        XCTAssertFalse(session.playReply(oldReply, line: nil, context: context))
        session.synchronize(line: nil, context: context)
        XCTAssertNil(session.run)
        // Restoring the same ID starts a new run and cannot consume an old callback.
        session.synchronize(line: line, context: context)
        session.submit(try ChessMove(uci: "e2e4"))
        XCTAssertFalse(session.playReply(oldReply, line: line, context: context))
        XCTAssertTrue(session.run?.awaitingReply == true)
    }

    func testRestartDepartureAndContextChangeRejectOldReplyTokens() throws {
        let line = try savedLine(), context = UUID()
        var session = SavedLineRehearsalSession()
        session.synchronize(line: line, context: context)
        session.submit(try ChessMove(uci: "e2e4"))
        let beforeRestart = try XCTUnwrap(session.replyToken)
        session.restart()
        session.submit(try ChessMove(uci: "e2e4"))
        XCTAssertFalse(session.playReply(beforeRestart, line: line, context: context))
        let beforeLeave = try XCTUnwrap(session.replyToken)
        session.leave()
        XCTAssertFalse(session.playReply(beforeLeave, line: line, context: context))
        let currentReply = try XCTUnwrap(session.replyToken)
        XCTAssertTrue(session.playReply(currentReply, line: line, context: context))
        XCTAssertFalse(session.playReply(currentReply, line: line, context: context), "Consume a reply only once")
        let replacementContext = UUID()
        XCTAssertFalse(session.matches(line: line, context: replacementContext))
        session.synchronize(line: line, context: replacementContext)
        XCTAssertEqual(session.run?.index, 0)
        XCTAssertFalse(session.playReply(currentReply, line: line, context: replacementContext))
    }
}
