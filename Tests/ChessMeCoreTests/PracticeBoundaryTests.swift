import Foundation
import Testing
@testable import ChessMeCore

@Suite struct PracticeBoundaryTests {
    private let line = ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "d2d3", "f8c5", "b1c3", "d7d6", "c1e3", "c8e6"]
    private var finding: MoveFinding {
        MoveFinding(id: "long-line", gameID: "game", gameLabel: "Learner vs Partner", positionFEN: ChessPosition.initial.fen,
                    playedMove: "d2d4", bestMove: line[0], acceptedMoves: [line[0]], continuation: line,
                    centipawnLoss: 200, theme: "Develop your pieces", explanation: "Play the key decisions.",
                    hint: "Develop a piece.", moveNumber: 1, source: "device", isPuzzle: true)
    }

    @Test func gamePracticeStopsAfterThreeDecisionsAndKeepsTheLongPVOptional() throws {
        var run = try AdaptiveReviewRun(finding: finding, revision: "long")
        #expect(run.requiredDecisions == 3 && run.practiceContinuation == Array(line.prefix(6)))
        for index in 0..<6 {
            if index.isMultiple(of: 2) {
                #expect(run.submitStoredMove(try ChessMove(uci: line[index]), verifiedDepth: 18))
            } else { run.playReply() }
        }
        #expect(run.isFinished && run.attempt.outcome == .completed)
        #expect(run.acceptedDecisions == 3 && run.acceptedMoves == Array(line.prefix(6)))
        #expect(run.sourceFinding.continuation == line && run.practiceContinuation.isEmpty)
    }

    @Test func olderSavedRunsUseTheShortBoundaryWithoutReimportingOrInventingMoves() throws {
        var run = try AdaptiveReviewRun(finding: finding, revision: "legacy")
        for index in 0..<6 {
            if index.isMultiple(of: 2) { _ = run.submitStoredMove(try ChessMove(uci: line[index]), verifiedDepth: 18) }
            else { run.playReply() }
        }
        run.attempt.outcome = .inProgress; run.attempt.endedAt = nil
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as? [String: Any])
        json["requiredDecisions"] = 6
        var restored = try JSONDecoder().decode(AdaptiveReviewRun.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.decisionLimit == 3 && restored.isConsistent)
        restored.resumePractice()
        #expect(restored.isFinished && restored.acceptedMoves == run.acceptedMoves)
        #expect(restored.attempt.decisions == run.attempt.decisions)
    }

    @Test func revealIsShortForGamePracticeAndCuratedPuzzlesKeepTheirSolutionLength() throws {
        var game = try AdaptiveReviewRun(finding: finding, revision: "short")
        game.reviewAnswer()
        #expect(try GameReplay(game: game.explorationGame()).moves.count == 6)
        let puzzle = try AdaptiveReviewRun(finding: finding, revision: "catalogue", kind: .relatedPuzzle)
        #expect(puzzle.requiredDecisions == 6 && puzzle.practiceContinuation == line)
    }

    @Test func acceptedAlternativePinsItsOwnFollowUpsAcrossSaveAndRestore() throws {
        var run = try AdaptiveReviewRun(finding: finding, revision: "alternative")
        let branch = ["d2d4", "d7d5", "c2c4", "e7e6", "b1c3", "g8f6"]
        let move = try ChessMove(uci: branch[0])
        let evaluation = PositionEvaluation(moves: [MoveEvaluation(move: move, score: 20,
            continuation: try branch.map(ChessMove.init(uci:)))], completedDepth: 12, nodes: 1000)
        run.submit(move, evaluation: evaluation)
        run.playReply()
        run = try JSONDecoder().decode(AdaptiveReviewRun.self, from: JSONEncoder().encode(run))
        #expect(run.submitStoredMove(try ChessMove(uci: "c2c4")), "The line just accepted by the engine stays valid on its own branch.")
        run.playReply()
        #expect(run.submitStoredMove(try ChessMove(uci: "b1c3")))
        run.playReply()
        #expect(run.isFinished && run.acceptedMoves == branch)
    }

    @Test func unverifiedSavedAnswerConflictIsUngradedAndOtherMistakesStillCount() throws {
        var run = try AdaptiveReviewRun(finding: finding, revision: "legacy-conflict")
        let saved = try ChessMove(uci: "e2e4"), best = try ChessMove(uci: "d2d4"), wrong = try ChessMove(uci: "c2c4")
        let evaluation = PositionEvaluation(moves: [
            MoveEvaluation(move: best, score: 500, continuation: try ["d2d4", "d7d5"].map(ChessMove.init(uci:))),
            MoveEvaluation(move: saved, score: -200, continuation: try ["e2e4", "e7e5"].map(ChessMove.init(uci:))),
            MoveEvaluation(move: wrong, score: -200, continuation: try ["c2c4", "c7c5"].map(ChessMove.init(uci:)))
        ], completedDepth: 12, nodes: 1000)
        let reused = run.submitStoredMove(saved)
        #expect(!reused, "An old line without depth evidence must not gain a verified grade.")
        run.submit(saved, evaluation: evaluation)
        #expect(run.attempt.decisions.last?.grade == .ungraded && run.acceptedMoves.isEmpty)
        #expect(run.feedback?.contains("disagree") == true)
        run.submit(wrong, evaluation: evaluation)
        #expect(run.attempt.decisions.last?.grade == .mistake)
    }
}
