import XCTest
@testable import ChessMeCore

final class StockfishTests: XCTestCase {
    func testDeepSearchReportsElapsedTimeWithoutInventingCompletedDepth() throws {
        let started = ProcessInfo.processInfo.systemUptime
        var lastUpdate = started
        var longestGap = 0.0
        var elapsed = 0.0
        let result = try LocalAnalyzer(options: AnalysisOptions(maximumDepth: 64, memoryMegabytes: 16,
            timeLimitSeconds: 3, engine: .stockfish, searchNodeLimit: 100_000_000)).evaluate(position: .initial, update: { snapshot in
                let now = ProcessInfo.processInfo.systemUptime
                longestGap = max(longestGap, now - lastUpdate); lastUpdate = now
                let measured = snapshot.elapsedSeconds ?? -1
                XCTAssertGreaterThanOrEqual(measured, elapsed)
                elapsed = measured
                XCTAssertGreaterThan(snapshot.completedDepth, 0)
                XCTAssertEqual(Set(snapshot.moves.map(\.move)).count, snapshot.moves.count)
            })
        XCTAssertGreaterThan(elapsed, 1)
        XCTAssertLessThan(longestGap, 2, "A working deep search must keep reporting during long iterations")
        XCTAssertLessThan(result.completedDepth, 64)
        XCTAssertNotNil(result.limit)
    }
    func testMultiPVUpdatesContainDistinctLegalRootMoves() throws {
        let position = try ChessPosition(fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2")
        var updates = 0
        let result = try analyzer(depth: 24, seconds: 2).evaluate(position: position, update: { snapshot in
            updates += 1
            XCTAssertEqual(Set(snapshot.moves.map(\.move)).count, snapshot.moves.count,
                           "A completed MultiPV update must not mix roots from partial batches")
            XCTAssertTrue(snapshot.moves.allSatisfy { position.legalMoves().contains($0.move) })
        })
        XCTAssertGreaterThan(updates, 0)
        XCTAssertEqual(Set(result.moves.map(\.move)).count, result.moves.count)
    }

    private func analyzer(depth: Int = 8, seconds: Double = 2) -> LocalAnalyzer {
        LocalAnalyzer(options: AnalysisOptions(maximumDepth: depth, memoryMegabytes: 16,
            timeLimitSeconds: seconds, engine: .stockfish, searchNodeLimit: 1_000_000))
    }

    func testNativeStockfishFindsLegalMateAndGradesAForcedPlayedMove() throws {
        XCTAssertFalse(StockfishEngine.license.isEmpty)
        let position = try ChessPosition(fen: "7k/8/5KQ1/8/8/8/8/8 w - - 0 1")
        let played = try ChessMove(uci: "g6g5")
        let result = try analyzer().evaluate(position: position, requiredMove: played)
        XCTAssertGreaterThan(result.completedDepth, 0)
        XCTAssertTrue(try XCTUnwrap(result.best).isWinningMate)
        XCTAssertNotNil(result.assessment(position: position, played: played, ply: 0))
        for candidate in result.moves {
            var board = position
            for move in candidate.continuation { board = try board.applying(move) }
        }
    }

    func testHistoryReconstructionPreservesEnPassantAndRepetition() throws {
        var board = ChessPosition.initial
        var history: [String] = []
        for token in ["e2e4", "a7a6", "e4e5", "d7d5"] {
            history.append(board.repetitionKey)
            board = try board.applying(ChessMove(uci: token))
        }
        let native = try StockfishAnalyzer.nativePosition(board, history: history)
        XCTAssertEqual(native.moves, "e2e4 a7a6 e4e5 d7d5")
        let enPassant = try ChessMove(uci: "e5d6")
        let result = try analyzer(depth: 5).evaluate(position: board, repetitionHistory: history, requiredMove: enPassant)
        XCTAssertTrue(result.moves.contains { $0.move == enPassant })
        var repeated = ChessPosition.initial
        var repetitions: [String] = []
        for token in ["g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8"] {
            repetitions.append(repeated.repetitionKey)
            repeated = try repeated.applying(ChessMove(uci: token))
        }
        XCTAssertTrue(try analyzer().evaluate(position: repeated, repetitionHistory: repetitions).moves.isEmpty)
    }

    func testDeepSettingsAreBoundedAndShortSearchReportsAchievedDepth() throws {
        let options = AnalysisOptions(maximumDepth: 99, memoryMegabytes: 999, timeLimitSeconds: 999,
                                      engine: .stockfish, searchNodeLimit: 999_000_000, engineThreads: 99)
        XCTAssertEqual(options.maximumDepth, 64)
        XCTAssertEqual(options.memoryMegabytes, 256)
        XCTAssertEqual(options.timeLimitSeconds, 300)
        XCTAssertEqual(options.searchNodeLimit, 250_000_000)
        XCTAssertEqual(options.engineThreads, 2)
        let result = try analyzer(depth: 32, seconds: 0.2).evaluate(position: .initial)
        XCTAssertGreaterThan(result.completedDepth, 0)
        XCTAssertLessThan(result.completedDepth, 32)
        XCTAssertNotNil(result.limit)
    }

    func testRunningNativeSearchCanBeCancelled() async throws {
        let started = ProcessInfo.processInfo.systemUptime
        let task = Task.detached { try self.analyzer(depth: 32, seconds: 180).evaluate(position: .initial, cancellation: { Task.isCancelled }) }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        do { _ = try await task.value; XCTFail("An interrupted search must not return an apparently finished review") }
        catch { XCTAssertTrue(TaskCancelled(error)) }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 3)
    }

    private func TaskCancelled(_ error: Error) -> Bool {
        if case ChessError.cancelled = error { return true }
        return error is CancellationError
    }
}
