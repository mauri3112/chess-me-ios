import Foundation
import Testing
@testable import ChessMeCore

@Suite(.serialized)
struct ArasanTests {
    private func analyzer(depth: Int = 5, seconds: Double = 1) -> LocalAnalyzer {
        LocalAnalyzer(options: AnalysisOptions(maximumDepth: depth, nodesPerMove: 100_000,
            memoryMegabytes: 8, timeLimitSeconds: seconds, engine: .arasan))
    }

    @Test func bundledNetworkFindsLegalMateForBothSides() throws {
        for fen in ["7k/8/5KQ1/8/8/8/8/8 w - - 0 1", "8/8/8/8/8/5kq1/8/7K b - - 0 1"] {
            let board = try ChessPosition(fen: fen)
            let result = try analyzer().evaluate(position: board)
            let best = try #require(result.best)
            #expect(best.isWinningMate)
            #expect(result.completedDepth >= 1)
            #expect(try board.applying(best.move).outcome() == .checkmate(winner: board.sideToMove))
            for candidate in result.moves {
                var position = board
                for move in candidate.continuation { position = try position.applying(move) }
            }
        }
        #expect(ArasanEngine.license.contains("Copyright 1994-2026 by Jon Dart"))
        #expect(ArasanEngine.license.contains("network directories"))
    }

    @Test func reviewComparesPlayedMovesAndUsesArasanCheckpointIdentity() throws {
        let engine = analyzer()
        let game = DemoContent.games()[0]
        let result = try engine.analyze(game: game)
        #expect(result.isComplete)
        #expect(result.engineVersion == ArasanEngine.version)
        let mate = try #require(result.findings.first { $0.bestMove == "h5f7" })
        #expect(!mate.acceptedMoves.contains(mate.playedMove))
        #expect(result.moveAssessments?.contains { $0.ply == 6 && $0.centipawnLoss >= 250 } == true)
        let original = try LocalAnalyzer().analyze(game: game)
        #expect(throws: ChessError.self) { try engine.analyze(game: game, previousAnalysis: original) }
    }

    @Test func boundsTimeAndCancellationAndRecognizesDraws() throws {
        let engine = analyzer(depth: 32, seconds: 0.1)
        let began = ProcessInfo.processInfo.systemUptime
        let result = try engine.evaluate(position: .initial)
        #expect(ProcessInfo.processInfo.systemUptime - began < 2)
        #expect(!result.moves.isEmpty)
        #expect(result.completedDepth < 32)
        #expect(throws: ChessError.cancelled) { try engine.evaluate(position: .initial, cancellation: { true }) }
        let fifty = try ChessPosition(fen: "7k/8/8/8/8/8/3R4/7K w - - 100 1")
        #expect(try engine.evaluate(position: fifty).moves.isEmpty)
        #expect(try engine.evaluate(position: .initial, repetitionHistory: [ChessPosition.initial.repetitionKey, ChessPosition.initial.repetitionKey]).moves.isEmpty)
    }

    @Test func runningNativeSearchRespondsToTaskCancellation() async throws {
        let engine = analyzer(depth: 32, seconds: 10)
        let work = Task.detached {
            try engine.evaluate(position: .initial, cancellation: { Task.isCancelled })
        }
        try await Task.sleep(for: .milliseconds(50))
        let began = ProcessInfo.processInfo.systemUptime
        work.cancel()
        do { _ = try await work.value; Issue.record("Cancelled native search returned a result") }
        catch { #expect(error as? ChessError == .cancelled) }
        #expect(ProcessInfo.processInfo.systemUptime - began < 2)
    }
}
