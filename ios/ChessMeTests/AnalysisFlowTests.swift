import XCTest
import Combine
import ChessMeCore
@testable import ChessMe

final class AnalysisFlowTests: XCTestCase {
    @MainActor
    func testBoardMotionCancellationCannotRestoreAnEarlierLessonAndRejectionReturnsQuickly() async throws {
        let motion = TrainingBoardMotion()
        let history = try MoveHistory(position: .initial).appending([ChessMove(uci: "e2e4"), ChessMove(uci: "e7e5")])
        let intro = Task { await motion.replay(history, reduceMotion: true) }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(motion.isAnimating)
        motion.stop()
        await intro.value
        XCTAssertNil(motion.position)
        XCTAssertFalse(motion.isAnimating)
        let started = ProcessInfo.processInfo.systemUptime
        await motion.returnAttempt(try ChessMove(uci: "e2e4"), in: .initial, rejected: true, reduceMotion: true)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 1)
        XCTAssertNil(motion.position)
        XCTAssertFalse(motion.isAnimating)
        XCTAssertEqual(motion.rejectionCount, 1)
    }

    @MainActor
    func testSessionMovesBetweenPositionsWithoutEndingPresentation() throws {
        let original = DemoContent.games()[0]
        let second = ChessGame(id: "second-genuine-blunder", username: original.username, white: original.white, black: original.black,
                               playedAt: original.playedAt, playerSide: original.playerSide, moves: original.moves, status: original.status)
        let games = [original, second]
        let analyses = try games.map { try LocalAnalyzer(options: AnalysisOptions(maximumDepth: 1, nodesPerMove: 800)).analyze(game: $0) }
        let model = AppModel(previewLibrary: LibrarySnapshot(games: games, analyses: analyses, isDemo: true))
        model.startSession()
        XCTAssertGreaterThan(model.session.count, 1)
        let first = try XCTUnwrap(model.activeLesson)
        model.advanceSession()
        XCTAssertNotNil(model.activeLesson)
        XCTAssertNotEqual(model.activeLesson?.id, first.id)
        model.previousSessionPosition()
        XCTAssertEqual(model.activeLesson?.id, first.id)
        while !model.sessionFinished { model.advanceSession() }
        XCTAssertNotNil(model.activeLesson, "The sheet stays open for the session summary.")
        model.endSession()
        XCTAssertTrue(model.session.isEmpty)
    }

    @MainActor
    func testGuidedPracticeDoesNotExtendAnUnaidedStreak() throws {
        let game = DemoContent.games()[0]
        let analysis = try LocalAnalyzer(options: AnalysisOptions(maximumDepth: 1)).analyze(game: game)
        let finding = try XCTUnwrap(analysis.findings.first)
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], analyses: [analysis], isDemo: true))
        model.recordPractice(finding, correct: true)
        XCTAssertEqual(model.library.practice.first?.streak, 1)
        model.recordPractice(finding, correct: true, assisted: true)
        let record = try XCTUnwrap(model.library.practice.first)
        XCTAssertEqual(record.streak, 0)
        XCTAssertEqual(record.correctCount, 1)
        XCTAssertEqual(record.assistedCount, 1)
        XCTAssertEqual(model.sessionOutcomes[finding.id], "Guided")
        XCTAssertLessThan(record.dueAt.timeIntervalSinceNow, 86_401)
    }

    @MainActor
    func testRapidPositionChangesCannotPublishStaleArrows() async throws {
        let controller = PositionAnalysisController()
        var configuration = DeviceEngineConfiguration()
        configuration.depth = 8
        configuration.secondsPerPosition = 1
        controller.start(position: .initial, configuration: configuration)
        let mate = try ChessPosition(fen: "7k/8/5KQ1/8/8/8/8/8 w - - 0 1")
        controller.start(position: mate, configuration: configuration)
        let finished = expectation(description: "The latest position finishes analysis")
        let observation = controller.$isCalculating.filter { !$0 }.prefix(1).sink { _ in finished.fulfill() }
        defer { observation.cancel(); controller.stop() }
        // A cold simulator also loads the bundled network before the bounded search starts.
        await fulfillment(of: [finished], timeout: 15)
        XCTAssertFalse(controller.isCalculating)
        let result = try XCTUnwrap(controller.evaluation)
        XCTAssertNotNil(controller.evaluation(for: mate))
        XCTAssertNil(controller.evaluation(for: .initial), "An earlier position must not reuse a score from the opposite side to move.")
        let legalMoves = Set(mate.legalMoves())
        // Disjoint move sets identify the position independently of how deeply
        // a slow runner searches within its one-second budget.
        XCTAssertTrue(legalMoves.isDisjoint(with: ChessPosition.initial.legalMoves()))
        XCTAssertGreaterThan(result.completedDepth, 0)
        XCTAssertFalse(result.moves.isEmpty)
        XCTAssertTrue(result.moves.allSatisfy { legalMoves.contains($0.move) })
        controller.stop()
        XCTAssertFalse(controller.isCalculating)
    }

    @MainActor
    func testRapidNavigationDefersSearchAndCompletedPositionsAreReused() async throws {
        let controller = PositionAnalysisController()
        defer { controller.stop() }
        let replay = try GameReplay(game: DemoContent.games()[0])
        var configuration = DeviceEngineConfiguration()
        configuration.engine = .material
        configuration.depth = 1
        let start = ProcessInfo.processInfo.systemUptime
        for index in 0..<100 {
            controller.start(position: replay.positions[index % replay.positions.count], configuration: configuration)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print("REVIEW_NAVIGATION 100 analysis requests main_thread_ms=\(elapsed * 1_000)")
        XCTAssertLessThan(elapsed, 0.5, "Navigation must not synchronously generate legal moves or search")
        let position = replay.positions[3]
        controller.start(position: position, configuration: configuration)
        let finished = expectation(description: "Settled position finishes")
        let observation = controller.$isCalculating.filter { !$0 }.prefix(1).sink { _ in finished.fulfill() }
        defer { observation.cancel() }
        await fulfillment(of: [finished], timeout: 15)
        let evaluation = try XCTUnwrap(controller.evaluation(for: position))
        XCTAssertNotNil(controller.lines[evaluation.moves.first!.move.uci])
        controller.start(position: .initial, configuration: configuration)
        controller.start(position: position, configuration: configuration)
        XCTAssertFalse(controller.isCalculating, "Returning to a cached position should not start another search")
        XCTAssertEqual(controller.evaluation(for: position)?.completedDepth, evaluation.completedDepth)
        XCTAssertNil(controller.evaluation(for: .initial))
    }
}
