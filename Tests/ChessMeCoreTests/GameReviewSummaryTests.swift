import Foundation
import Testing
@testable import ChessMeCore

struct GameReviewSummaryTests {
    private func game(side: Side = .white) -> ChessGame {
        ChessGame(id: "summary", username: "Learner", white: "Learner", black: "Partner", playedAt: Date(),
                  playerSide: side, moves: "e4 e5 Nf3 Nc6 Bb5 a6", status: "resign")
    }
    private func assessment(_ history: MoveHistory, ply: Int, quality: MoveQuality) -> MoveAssessment {
        MoveAssessment(ply: ply, positionFEN: history.positions[ply].fen, playedMove: history.moves[ply].uci,
                       bestMove: history.moves[ply].uci, quality: quality, centipawnLoss: 0,
                       whiteScore: 50, completedDepth: 12, isProvisional: true)
    }

    @Test func summaryCountsOnlyMatchingPlayerMovesAndDeduplicates() throws {
        let game = game(side: .black), history = try MoveHistory(game: game)
        let own = assessment(history, ply: 1, quality: .book)
        let other = assessment(history, ply: 0, quality: .blunder)
        let stale = MoveAssessment(ply: 3, positionFEN: history.positions[1].fen, playedMove: history.moves[3].uci,
                                   bestMove: "b8c6", quality: .mistake, centipawnLoss: 200, whiteScore: 200,
                                   completedDepth: 12, isProvisional: true)
        let analysis = GameAnalysis(gameID: game.id, findings: [], analyzedPlies: 1, totalPlies: 3,
                                    moveAssessments: [own, own, other, stale])
        let summary = GameReviewSummary(game: game, analysis: analysis, history: history)
        #expect(summary.assessments.map(\.ply) == [1])
        #expect(summary.count(.book) == 1 && summary.count(.blunder) == 0)
        #expect(summary.totalPlies == 6)
    }

    @Test func summaryDoesNotInventGradesForLegacyOrForeignAnalysis() throws {
        let game = game(), history = try MoveHistory(game: game)
        let legacy = GameAnalysis(gameID: game.id, findings: [], analyzedPlies: 3, totalPlies: 3)
        #expect(GameReviewSummary(game: game, analysis: legacy, history: history).assessments.isEmpty)
        let foreign = GameAnalysis(gameID: "other", findings: [], analyzedPlies: 3, totalPlies: 3,
                                   moveAssessments: [assessment(history, ply: 0, quality: .best)])
        #expect(GameReviewSummary(game: game, analysis: foreign, history: history).assessments.isEmpty)
    }

    @Test func unclassifiedMovesAreNotCountedAsSound() throws {
        let game = game(), history = try MoveHistory(game: game)
        let analysis = GameAnalysis(gameID: game.id, findings: [], analyzedPlies: 3, totalPlies: 3,
            moveAssessments: [assessment(history, ply: 0, quality: .excellent),
                              assessment(history, ply: 2, quality: .unclassified),
                              assessment(history, ply: 4, quality: .mistake)])
        let summary = GameReviewSummary(game: game, analysis: analysis, history: history)
        #expect(summary.classifiedCount == 2)
        #expect(summary.count(.sound) == 1 && summary.count(.mistake) == 1)
    }

    @Test func resumedBookmarkPrunesRemovedMomentsAndInvalidCursor() throws {
        let game = game(), journey = ReviewJourney(game: game, analysis: nil)
        let saved = ReviewBookmark(gameID: game.id, revision: "old", place: .moment, momentID: "removed",
                                   step: 4, visited: ["removed", "removed"], finished: false)
        let restored = saved.reconciled(with: journey)
        #expect(restored.visited.isEmpty && restored.momentID == nil)
        #expect(restored.place == .overview && restored.step == 0 && !restored.finished)
        #expect(restored.revision == journey.revision)
    }
}
