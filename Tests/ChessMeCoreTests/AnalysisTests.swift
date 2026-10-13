import Testing
import Foundation
@testable import ChessMeCore

struct AnalysisTests {
    @Test func goodMoveHighlightsExcludeWeakIllegalAndUnsearchedCandidates() throws {
        let board = ChessPosition.initial
        let candidates = try zip(["e2e4", "d2d4", "g1f3", "a2a3", "a1a8"], [100, 90, 65, -100, 80]).map {
            MoveEvaluation(move: try ChessMove(uci: $0.0), score: $0.1, continuation: [])
        }
        let evaluation = PositionEvaluation(moves: candidates, completedDepth: 3, nodes: 100)
        let highlights = evaluation.goodMoves(in: board)
        #expect(highlights.map(\.move.uci) == ["e2e4", "d2d4", "g1f3"])
        #expect(highlights.map(\.quality) == [.best, .excellent, .good])
        #expect(PositionEvaluation(moves: candidates, completedDepth: 0, nodes: 0).goodMoves(in: board).isEmpty)
        #expect(evaluation.goodMoves(in: board, limit: 1).count == 1)
        let mate = PositionEvaluation(moves: Array(candidates.prefix(2)).enumerated().map {
            MoveEvaluation(move: $0.element.move, score: $0.offset == 0 ? 99_995 : 500, continuation: [])
        }, completedDepth: 3, nodes: 100)
        #expect(mate.goodMoves(in: board).count == 1, "A material gain cannot be highlighted as comparable to forced mate")
    }

    @Test
    func testBlackAndWhiteMateScoresArePlayerRelative() throws {
        let analyzer = LocalAnalyzer(options: AnalysisOptions(maximumDepth: 1, nodesPerMove: 500))
        let white = try ChessPosition(fen: "7k/8/5KQ1/8/8/8/8/8 w - - 0 1")
        let whiteResult = try analyzer.evaluate(position: white)
        #expect(try #require(whiteResult.best).isWinningMate)
        let whiteAfter = try white.applying(#require(whiteResult.best).move)
        #expect(whiteAfter.outcome() == .checkmate(winner: .white))
        let black = try ChessPosition(fen: "8/8/8/8/8/5kq1/8/7K b - - 0 1")
        let blackResult = try analyzer.evaluate(position: black)
        #expect(try #require(blackResult.best).isWinningMate)
        #expect(try black.applying(#require(blackResult.best).move).outcome() == .checkmate(winner: .black))
    }

    @Test
    func testBlackChoosesMaterialGainAndForcedMoveCreatesNoPuzzle() throws {
        let analyzer = LocalAnalyzer(options: AnalysisOptions(maximumDepth: 2, nodesPerMove: 800))
        let position = try ChessPosition(fen: "7k/8/8/8/8/8/1r1Q4/7K b - - 0 1")
        let evaluation = try analyzer.evaluate(position: position)
        #expect(evaluation.best?.move.uci == "b2d2")
        let forced = ChessGame(id: "forced", username: "You", white: "You", black: "Them", playedAt: Date(),
                               playerSide: .white, moves: "1. Kg1", initialFEN: "8/8/8/8/8/6k1/4r3/7K w - - 0 1")
        #expect(try analyzer.analyze(game: forced).findings.count == 0)
    }

    @Test
    func testDemoProducesReplayableRealMateLesson() throws {
        let analyzer = LocalAnalyzer()
        let game = try #require(DemoContent.games().first)
        let analysis = try analyzer.analyze(game: game)
        #expect(analysis.isComplete)
        let mate = try #require(analysis.findings.first { $0.theme == "Missed checkmate" })
        #expect(mate.moveNumber == 4)
        #expect(mate.bestMove == "h5f7")
        #expect(mate.isPuzzle)
        let position = try ChessPosition(fen: mate.positionFEN)
        var replay = position
        #expect(!(mate.acceptedMoves.contains(mate.playedMove)))
        for token in mate.continuation { replay = try replay.applying(ChessMove(uci: token)) }
        #expect(replay.outcome() == .checkmate(winner: .white))
        #expect(analysis.source == "device")
        #expect(analysis.engineVersion == LocalAnalyzer.engineVersion)
        for demo in DemoContent.games() { _ = try PGNDocument(demo.moves).replayFrom(fen: demo.initialFEN) }
    }

    @Test
    func testLimitsCancellationAndInvalidReplayDoNotClaimCompletion() throws {
        let analyzer = LocalAnalyzer(options: AnalysisOptions(maximumDepth: 2, nodesPerMove: 100, maximumPositions: 1))
        let game = DemoContent.games()[0]
        let partial = try analyzer.analyze(game: game)
        #expect(partial.analyzedPlies == 1)
        #expect(!(partial.isComplete))
        #expect(throws: ChessError.cancelled) { try analyzer.analyze(game: game, cancellation: { true }) }
        let malformed = ChessGame(id: "bad", username: "you", white: "you", black: "them", playedAt: Date(), playerSide: .white, moves: "e4 e5 Qz9")
        #expect(throws: ChessError.self) { try analyzer.analyze(game: malformed) }
        let started = ChessGame(id: "started", username: "you", white: "you", black: "them", playedAt: Date(), playerSide: .white, moves: "e4", status: "started")
        #expect(throws: ChessError.self) { try analyzer.analyze(game: started) }
        let empty = ChessGame(id: "empty", username: "you", white: "you", black: "them", playedAt: Date(), playerSide: .white, moves: "")
        #expect(throws: ChessError.self) { try analyzer.analyze(game: empty) }
        let bounded = try analyzer.evaluate(position: .initial)
        #expect(bounded.nodes <= 20 * 100 * 2)
    }

    @Test
    func testTimeWindowsCodableRoundTripAndSpacedReview() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ReviewWindow.day.contains(now.addingTimeInterval(-86_400), now: now))
        #expect(!(ReviewWindow.day.contains(now.addingTimeInterval(-86_401), now: now)))
        #expect(!(ReviewWindow.year.contains(now.addingTimeInterval(1), now: now)))
        #expect(ReviewWindow.month.duration == 30 * 86_400)
        #expect(ReviewWindow.allCases.filter(\.isFree) == [.day])
        let first = LessonAttempt(findingID: "exercise", result: .correct, attemptedAt: now)
        #expect(first.streak == 1)
        #expect(first.nextReviewAt.timeIntervalSince(now) == 86_400)
        let third = LessonAttempt(findingID: "exercise", result: .correct, attemptedAt: now, previousStreak: 2)
        #expect(third.nextReviewAt.timeIntervalSince(now) == 7 * 86_400)
        let reveal = LessonAttempt(findingID: "exercise", result: .revealed, attemptedAt: now, previousStreak: 4)
        #expect(reveal.streak == 0)
        let game = DemoContent.games(now: now)[0]
        #expect(try JSONDecoder().decode(ChessGame.self, from: JSONEncoder().encode(game)) == game)
        #expect(game.url == nil)
    }

    @Test
    func testChunkedAnalysisResumesUntilCompleteWithoutRepeatingFindings() throws {
        let analyzer = LocalAnalyzer(options: AnalysisOptions(maximumDepth: 1, nodesPerMove: 500, maximumPositions: 1))
        let game = DemoContent.games()[0]
        var checkpoint = try analyzer.analyze(game: game)
        #expect(checkpoint.analyzedPlies == 1)
        #expect(!checkpoint.isComplete)
        var completedChunks = 1
        while !checkpoint.isComplete {
            let oldCount = checkpoint.analyzedPlies
            let oldFindings = checkpoint.findings
            var progressCounts: [Int] = []
            checkpoint = try analyzer.analyze(game: game, previousAnalysis: checkpoint,
                                              progress: { progressCounts.append($0); #expect($1 == 6) })
            #expect(checkpoint.analyzedPlies == oldCount + 1)
            #expect(Array(checkpoint.findings.prefix(oldFindings.count)) == oldFindings)
            #expect(progressCounts.first == oldCount)
            #expect(progressCounts.last == checkpoint.analyzedPlies)
            #expect(Set(checkpoint.findings.map(\.id)).count == checkpoint.findings.count)
            completedChunks += 1
        }
        #expect(completedChunks == 6)
        #expect(checkpoint.analyzedPlies == checkpoint.totalPlies)
        #expect(checkpoint.findings.contains { $0.bestMove == "h5f7" && $0.theme == "Missed checkmate" })
        let repeated = try analyzer.analyze(game: game, previousAnalysis: checkpoint)
        #expect(repeated.findings == checkpoint.findings)
        #expect(repeated.analyzedPlies == checkpoint.analyzedPlies)
    }

    @Test
    func testResumeRejectsDifferentGameOrEngineCheckpoints() throws {
        let analyzer = LocalAnalyzer(options: AnalysisOptions(maximumDepth: 1, maximumPositions: 1))
        let games = DemoContent.games()
        let checkpoint = try analyzer.analyze(game: games[0])
        #expect(throws: ChessError.self) { try analyzer.analyze(game: games[1], previousAnalysis: checkpoint) }
        let cloud = GameAnalysis(gameID: games[0].id, findings: [], analyzedPlies: 1, totalPlies: checkpoint.totalPlies,
                                 source: "cloud", engineVersion: "stockfish")
        #expect(throws: ChessError.self) { try analyzer.analyze(game: games[0], previousAnalysis: cloud) }
        let invalidCount = GameAnalysis(gameID: games[0].id, findings: [], analyzedPlies: -1, totalPlies: checkpoint.totalPlies)
        #expect(throws: ChessError.self) { try analyzer.analyze(game: games[0], previousAnalysis: invalidCount) }
    }
}

private extension PGNDocument {
    func replayFrom(fen: String?) throws -> [ChessPosition] {
        var position = try fen.map(ChessPosition.init(fen:)) ?? .initial
        var positions = [position]
        for token in moves { position = try position.applying(position.move(san: token)); positions.append(position) }
        return positions
    }
}
