import Foundation
import Testing
@testable import ChessMeCore

struct LearningTests {
    static let puzzle = TrainingPuzzle(id: "00sHx", setupFEN: "q3k1nr/1pp1nQpp/3p4/1P2p3/4P3/B1PP1b2/B5PP/5K2 b k - 0 17",
                                      setupMove: "e8d7", positionFEN: "q5nr/1ppknQpp/3p4/1P2p3/4P3/B1PP1b2/B5PP/5K2 w - - 1 18",
                                      solution: ["a2e6", "d7d8", "f7f8"], rating: 1760, themes: ["mate", "mateIn2"],
                                      url: URL(string: "https://lichess.org/training/00sHx")!)

    @Test func puzzleAppliesSetupAndRequiresEverySolverMove() throws {
        var attempt = try PuzzlePlaythrough(puzzle: Self.puzzle)
        #expect(attempt.position.sideToMove == .white)
        #expect(attempt.history.moves.map(\.uci) == ["e8d7"])
        let before = attempt.position
        #expect(try !attempt.play(ChessMove(uci: "f7f6")))
        #expect(attempt.position == before)
        #expect(try attempt.play(ChessMove(uci: "a2e6")))
        #expect(!attempt.isComplete)
        #expect(attempt.cursor == 2)
        #expect(attempt.position.sideToMove == .white)
        #expect(attempt.moves.map(\.uci) == ["a2e6", "d7d8"])
        #expect(try attempt.play(ChessMove(uci: "f7f8")))
        #expect(attempt.isComplete)
        #expect(attempt.position.outcome() == .checkmate(winner: .white))
        #expect(attempt.history.positions.count == 5)
    }

    @Test func puzzleRejectsMalformedSetupIllegalRepliesAndTruncatedLines() throws {
        let p = Self.puzzle
        func changed(fen: String = p.positionFEN, line: [String]) -> TrainingPuzzle {
            TrainingPuzzle(id: p.id, setupFEN: p.setupFEN, setupMove: p.setupMove, positionFEN: fen,
                           solution: line, rating: p.rating, themes: p.themes, url: p.url)
        }
        #expect(throws: ChessError.self) { try PuzzlePlaythrough(puzzle: changed(fen: ChessPosition.initial.fen, line: p.solution)) }
        #expect(throws: ChessError.self) { try PuzzlePlaythrough(puzzle: changed(line: ["a2e6", "d7d8"])) }
        #expect(throws: ChessError.self) { try PuzzlePlaythrough(puzzle: changed(line: ["a2e6", "d7h1", "f7f8"])) }
        var attempt = try PuzzlePlaythrough(puzzle: p)
        try attempt.reveal()
        #expect(attempt.isComplete)
        #expect(attempt.moves.count == 3)
    }

    @Test func animatedPuzzleReplyCannotBePlayedAsASolverMove() throws {
        var attempt = try PuzzlePlaythrough(puzzle: Self.puzzle)
        #expect(try attempt.play(ChessMove(uci: "a2e6"), automaticallyReply: false))
        #expect(attempt.isAwaitingReply)
        #expect(attempt.position.sideToMove == .black)
        let waiting = attempt.position
        #expect(try !attempt.play(ChessMove(uci: "d7d8")))
        #expect(attempt.position == waiting)
        #expect(try attempt.playReply())
        #expect(!attempt.isAwaitingReply)
        #expect(attempt.position.sideToMove == .white)
        #expect(try !attempt.playReply())
        #expect(try attempt.play(ChessMove(uci: "f7f8"), automaticallyReply: false))
        #expect(attempt.isComplete)
    }

    @Test func mateInOneAcceptsEveryLegalMatingMove() throws {
        let setup = try ChessPosition(fen: "8/5K1k/8/6Q1/8/8/8/8 b - - 0 1")
        let board = try setup.applying(ChessMove(uci: "h7h8"))
        let mates = try board.legalMoves().filter { try board.applying($0).outcome() == .checkmate(winner: .white) }
        try #require(mates.count > 1)
        let puzzle = TrainingPuzzle(id: "mate1", setupFEN: setup.fen, setupMove: "h7h8", positionFEN: board.fen,
                                    solution: [mates[0].uci], rating: 1000, themes: ["mateIn1"], url: URL(string: "https://lichess.org/training/mate1")!)
        var attempt = try PuzzlePlaythrough(puzzle: puzzle)
        #expect(try attempt.play(mates[1]))
        #expect(attempt.isComplete)
    }

    @Test func lessonHistoryStopsAtDecisionAndCanAppendAnImprovement() throws {
        let game = DemoContent.games()[0]
        let replay = try GameReplay(game: game)
        let ply = 6
        let finding = MoveFinding(id: "sample", gameID: game.id, gameLabel: game.label, positionFEN: replay.positions[ply].fen,
                                  playedMove: replay.moves[ply].uci, bestMove: "h5f7", acceptedMoves: ["h5f7"], continuation: ["h5f7"],
                                  centipawnLoss: 1000, theme: "Missed checkmate", explanation: "Mate", hint: "Check", moveNumber: 4)
        let history = try MoveHistory(game: game, finding: finding)
        #expect(history.moves.count == ply)
        #expect(history.positions.last == replay.positions[ply])
        let intro = history.leadIn()
        #expect(intro.positions.first == replay.positions[ply - 3])
        #expect(intro.moves.map(\.uci) == Array(replay.moves[(ply - 3)..<ply]).map(\.uci))
        #expect(intro.positions.last == replay.positions[ply])
        #expect(!intro.moves.contains(replay.moves[ply]))
        #expect(MoveHistory(position: .initial).leadIn().moves.isEmpty)
        #expect(history.notation(at: 1) == "1. e4")
        let solved = try history.appending([ChessMove(uci: "h5f7")])
        #expect(solved.positions.last?.outcome() == .checkmate(winner: .white))
        #expect(history.positions.last == replay.positions[ply])
        #expect(PuzzleTheme.related(to: finding).contains("mateIn1"))
    }

    private func openingSample(count: Int, depth: Int = 4) throws -> ([ChessGame], [GameAnalysis]) {
        var games: [ChessGame] = [], analyses: [GameAnalysis] = []
        for index in 0..<count {
            let game = ChessGame(id: "sample-\(index)", username: "Learner", white: "Learner", black: "Partner",
                                 playedAt: Date(), playerSide: .white, moves: "e4 e5 h4 Nc6", status: "resign")
            let replay = try GameReplay(game: game)
            let assessments = [0, 2].map { ply in
                MoveAssessment(ply: ply, positionFEN: replay.positions[ply].fen, playedMove: replay.moves[ply].uci,
                               bestMove: ply == 0 ? "e2e4" : "g1f3", quality: ply == 2 ? .mistake : .best,
                               centipawnLoss: ply == 2 ? 150 : 0, whiteScore: -150, completedDepth: depth, isProvisional: true)
            }
            games.append(game)
            analyses.append(GameAnalysis(gameID: game.id, findings: [], analyzedPlies: 2, totalPlies: 2, moveAssessments: assessments))
        }
        return (games, analyses)
    }

    @Test func openingAdviceNeedsThirtyReviewedGamesAndRanksRepeatedLoss() throws {
        let (games, analyses) = try openingSample(count: 30)
        let short = OpeningCoach.report(games: Array(games.prefix(29)), analyses: analyses)
        #expect(!short.isReady && short.opportunities.isEmpty)
        let report = OpeningCoach.report(games: games + [games[0]], analyses: analyses)
        #expect(report.reviewedGames == 30)
        #expect(report.eligibleGames == 30)
        let opportunity = try #require(report.opportunities.first)
        #expect(opportunity.visits == 30)
        #expect(opportunity.mistakes == 30)
        #expect(opportunity.suggestedSAN == "Nf3")
        #expect(opportunity.averageLoss == 150)
        #expect(opportunity.totalLoss == 4500)
    }

    @Test func shallowOrIncompleteOpeningReviewsCannotUnlockAdvice() throws {
        let (games, shallow) = try openingSample(count: 30, depth: 1)
        #expect(OpeningCoach.report(games: games, analyses: shallow).reviewedGames == 0)
        let (_, complete) = try openingSample(count: 30)
        let partial = complete.map { analysis in
            GameAnalysis(gameID: analysis.gameID, findings: [], analyzedPlies: 1, totalPlies: 2, moveAssessments: Array(analysis.moveAssessments!.prefix(1)))
        }
        #expect(OpeningCoach.report(games: games, analyses: partial).reviewedGames == 0)
        #expect(OpeningCoach.report(games: DemoContent.games(), analyses: []).eligibleGames == 0)
    }

    @Test func openingSampleDoesNotCombineDifferentImportedPlayers() throws {
        let (games, analyses) = try openingSample(count: 30)
        let mixed = games.enumerated().map { index, game in
            ChessGame(id: game.id, username: index < 15 ? "Alice" : "Bob", white: game.white, black: game.black,
                      playedAt: game.playedAt, playerSide: game.playerSide, moves: game.moves, status: game.status)
        }
        let report = OpeningCoach.report(games: mixed, analyses: analyses, username: "alice")
        #expect(report.reviewedGames == 15)
        #expect(!report.isReady)
        #expect(report.opportunities.isEmpty)
    }
}
