import Foundation
import Testing
@testable import ChessMeCore

struct LearningInsightsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func game(_ id: String, username: String = "Learner", result: GameResult? = .whiteWin,
                      side: Side = .white, speed: GameSpeed = .blitz) -> ChessGame {
        ChessGame(id: id, username: username, white: side == .white ? username : "Partner",
                  black: side == .black ? username : "Partner", playedAt: now, playerSide: side,
                  moves: "e4 e5 Nf3 Nc6", status: "resign", result: result, speed: speed)
    }

    @Test func resultsExcludeDemonstrationsAndOtherPlayersAndKeepUnknownDenominator() {
        let games = [game("a"), game("a"), game("b", result: .draw),
                     game("c", result: .whiteWin, side: .black, speed: .rapid),
                     game("unknown", result: nil), game("demo-a"), game("other", username: "Other")]
        let report = LearningInsights(games: games, analyses: [], review: ReviewLibrary(), username: "learner")
        #expect(report.results.games == 4)
        #expect(report.results.wins == 1 && report.results.draws == 1 && report.results.losses == 1)
        #expect(report.results.known == 3 && report.results.unknown == 1)
        #expect(report.excludedGames == 1)
        #expect(report.speeds.first { $0.title == "Blitz" }?.results.games == 3)
        #expect(report.colors.first { $0.title == "Black" }?.results.losses == 1)
        #expect(report.openings.reduce(0) { $0 + $1.results.games } == 4)
    }

    @Test func estimatesDeduplicateHistoriesButSeparateSourcesAndValidateMoves() throws {
        let game = game("a"), history = try MoveHistory(game: game)
        func assessment(_ ply: Int, quality: MoveQuality) -> MoveAssessment {
            MoveAssessment(ply: ply, positionFEN: history.positions[ply].fen,
                           playedMove: history.moves[ply].uci, bestMove: history.moves[ply].uci,
                           quality: quality, centipawnLoss: 200, whiteScore: 0,
                           completedDepth: 8, isProvisional: true)
        }
        let old = GameAnalysis(gameID: game.id, findings: [], analyzedPlies: 2, totalPlies: 2,
                               completedAt: now.addingTimeInterval(-1), moveAssessments: [assessment(0, quality: .blunder)])
        let current = GameAnalysis(gameID: game.id, findings: [], analyzedPlies: 1, totalPlies: 2,
                                   completedAt: now, moveAssessments: [assessment(0, quality: .mistake), assessment(0, quality: .mistake), assessment(1, quality: .blunder)])
        let cloud = GameAnalysis(gameID: game.id, findings: [], analyzedPlies: 2, totalPlies: 2,
                                 source: "cloud", completedAt: now, moveAssessments: [assessment(0, quality: .good), assessment(2, quality: .blunder)])
        let report = LearningInsights(games: [game], analyses: [old, current, current, cloud], review: ReviewLibrary())
        let device = try #require(report.estimates.first { $0.source == "device" })
        #expect(device.games == 1 && device.decisions == 1 && device.completeGames == 0)
        #expect(device.mistakes == 1 && device.blunders == 0)
        let remote = try #require(report.estimates.first { $0.source == "cloud" })
        #expect(remote.decisions == 2 && remote.completeGames == 1 && remote.blunders == 1)
    }

    @Test func practiceUsesLinkedEvidenceAndSeparatesAssistanceAndDueControls() throws {
        let game = game("a")
        let finding = MoveFinding(id: "target", gameID: game.id, gameLabel: game.label,
                                  positionFEN: ChessPosition.initial.fen, playedMove: "d2d4", bestMove: "e2e4",
                                  acceptedMoves: ["e2e4"], continuation: ["e2e4"], centipawnLoss: 100,
                                  theme: "Development", explanation: "Develop", hint: "Center", moveNumber: 1)
        var target = ReviewLearningTarget(username: "Learner", finding: finding, revision: "1", history: [], ideaKey: nil, now: now.addingTimeInterval(-200_000))
        var clean = ReviewPracticeAttempt(targetID: target.id, evidenceRevision: "1", rootFEN: finding.positionFEN, id: "clean")
        clean.decisions = [ReviewDecision(positionFEN: finding.positionFEN, move: "e2e4", grade: .accepted)]
        clean.outcome = .completed
        var assisted = clean
        assisted = ReviewPracticeAttempt(targetID: target.id, evidenceRevision: "1", rootFEN: finding.positionFEN, id: "assisted")
        assisted.outcome = .completed; assisted.help = [.idea]
        var revealed = ReviewPracticeAttempt(targetID: target.id, evidenceRevision: "1", rootFEN: finding.positionFEN, id: "revealed")
        revealed.outcome = .revealed
        var unrelated = clean
        unrelated.sourceUsername = "Other"
        var review = ReviewLibrary()
        review.targets = [target, target]
        review.attempts = [clean, clean, assisted, revealed]
        let report = LearningInsights(games: [game], analyses: [], review: review, now: now)
        #expect(report.practiceAttempts == 3 && report.unaidedCompletions == 1)
        #expect(report.assistedCompletions == 1 && report.revealedAttempts == 1 && report.dueLessons == 1)
        target.deferredUntil = now.addingTimeInterval(100)
        review.targets = [target]; review.attempts = [unrelated]
        let deferred = LearningInsights(games: [game], analyses: [], review: review, now: now)
        #expect(deferred.dueLessons == 0 && deferred.practiceAttempts == 0)
    }
}
