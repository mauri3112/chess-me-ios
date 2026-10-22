import ChessMeCore
import StoreKitTest
import XCTest
@testable import ChessMe

final class PracticePurchaseRegressionTests: XCTestCase {
    @MainActor func testStoredContinuationStaysVerifiedAfterItLeavesTheImportedGame() throws {
        let root = try ChessPosition(fen: "6k1/8/8/4p3/3P4/8/8/R5K1 w - - 0 13")
        let game = ChessGame(id: "off-record-lesson", username: "Learner", white: "Learner", black: "Partner",
                             playedAt: Date(), playerSide: .white, moves: "a1a2 g8f7 a2a3", initialFEN: root.fen, status: "resign")
        let finding = MoveFinding(id: "off-record-pv", gameID: game.id, gameLabel: "Learner vs Partner", positionFEN: root.fen,
                                 playedMove: "a1a2", bestMove: "d4e5", acceptedMoves: ["d4e5"],
                                 continuation: ["d4e5", "g8f7", "a1d1"], centipawnLoss: 900, theme: "Open the file",
                                 explanation: "Capture then activate the rook.", hint: "Use the file.", moveNumber: 13,
                                 source: "device", isPuzzle: true, quality: .blunder)
        let grade = MoveAssessment(ply: 0, positionFEN: root.fen, playedMove: "a1a2", bestMove: "d4e5", quality: .blunder,
                                   centipawnLoss: 900, whiteScore: -300, completedDepth: 18, isProvisional: true, bestWhiteScore: 600)
        let analysis = GameAnalysis(gameID: game.id, findings: [finding], analyzedPlies: 2, totalPlies: 2,
                                    moveAssessments: [grade])
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], analyses: [analysis], isDemo: true))
        var run = try model.prepareReviewRun(finding: finding)
        let first = try ChessMove(uci: "d4e5")
        XCTAssertTrue(run.submitStoredMove(first, verifiedDepth: model.storedDecisionDepth(for: run, move: first)))
        run.playReply()
        let followUp = try ChessMove(uci: "a1d1")
        XCTAssertEqual(model.storedDecisionDepth(for: run, move: followUp), 18,
                       "The saved engine line must not be compared with the game's actual next move.")
        XCTAssertTrue(run.submitStoredMove(followUp, verifiedDepth: model.storedDecisionDepth(for: run, move: followUp)))
        XCTAssertTrue(run.isFinished)
        XCTAssertNil(model.storedDecisionDepth(for: run, move: try ChessMove(uci: "a1a2")))
    }

    @MainActor func testLockedWindowRemembersIntentWithoutUnlockingHistoryOrForcingARootSheet() {
        let model = AppModel(previewLibrary: LibrarySnapshot())
        model.select(.week)
        XCTAssertTrue(model.showPaywall)
        XCTAssertEqual(model.selectedWindow, .day)
        XCTAssertEqual(model.requestedProWindow, .week)
        model.showPaywall = false
        model.select(.year, presentPaywall: false)
        XCTAssertFalse(model.showPaywall)
        XCTAssertEqual(model.requestedProWindow, .year)
        model.applyRequestedProWindow()
        XCTAssertEqual(model.selectedWindow, .day, "Presentation cannot grant a paid entitlement.")
    }

    @MainActor func testVerifiedLocalPurchaseUnlocksDeviceWindowAndCannotAuthorizeCloud() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ChessMe", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState(); session.clearTransactions(); session.disableDialogs = true
        defer { session.clearTransactions() }
        let model = AppModel(previewLibrary: LibrarySnapshot())
        model.select(.month, presentPaywall: false)
        await model.subscriptions.load()
        let product = try XCTUnwrap(model.subscriptions.products.first { $0.id.hasSuffix("monthly") })
        let result = try await model.subscriptions.purchase(product, appAccountToken: UUID())
        guard case .purchased = result else { return XCTFail("Expected the verified test purchase to complete.") }
        XCTAssertTrue(model.subscriptions.isPro)
        model.applyRequestedProWindow()
        XCTAssertEqual(model.selectedWindow, .month)
        do { _ = try await model.subscriptions.cloudCredential(); XCTFail("A fixture must never authorize cloud compute.") }
        catch SubscriptionError.developmentPurchase { }
    }
}
