import XCTest
import ChessMeCore
@testable import ChessMe

@MainActor
private final class BackgroundTaskFixture: AnalysisBackgroundTask {
    let identifier: String
    let isContinued = true
    let progress = Progress(totalUnitCount: 0)
    var completions: [Bool] = []
    var subtitles: [String] = []
    private var expiration: (@Sendable () -> Void)?
    init(_ identifier: String) { self.identifier = identifier }
    func onExpiration(_ handler: @escaping @Sendable () -> Void) { expiration = handler }
    func updateTitle(_ title: String, subtitle: String) { subtitles.append(subtitle) }
    func complete(success: Bool) { completions.append(success) }
    func expire() { expiration?() }
}

final class BackgroundAnalysisTests: XCTestCase {
    @MainActor
    func testAWorkingSearchReportsProgressBeforeItsFirstSavedDecision() async throws {
        let game = ChessGame(id: "background-progress", username: "Learner", white: "Learner", black: "Partner",
                             playedAt: Date(), playerSide: .white, moves: "e4 e5", status: "resign")
        var configuration = DeviceEngineConfiguration()
        configuration.depth = 32; configuration.memoryMB = 16; configuration.secondsPerPosition = 3
        configuration.searchNodeLimit = 100_000_000
        let job = LocalAnalysisJob(gameID: game.id, configuration: configuration, level: .balanced)
        let duplicate = LocalAnalysisJob(gameID: game.id, configuration: configuration, level: .balanced)
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], isDemo: true, localAnalysisJobs: [job, duplicate]))
        let coordinator = DeviceAnalysisCoordinator(model: model, schedulerEnabled: false)
        defer { coordinator.pause() }
        coordinator.prepareContinuedRequest(identifier: "progress-request", jobIDs: [job.id, duplicate.id])
        let task = BackgroundTaskFixture("progress-request")
        await coordinator.accept(task)
        for _ in 0..<200 where task.progress.completedUnitCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(task.progress.completedUnitCount, 0)
        XCTAssertLessThan(task.progress.completedUnitCount, task.progress.totalUnitCount)
        XCTAssertGreaterThan(model.progress, 0)
        XCTAssertNil(model.library.localAnalysisJobs?.first?.checkpoint)
        for _ in 0..<600 where task.completions.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(task.completions, [true])
        XCTAssertTrue(task.progress.isFinished)
        XCTAssertTrue(model.library.localAnalysisJobs?.first?.checkpoint?.isComplete == true)
        XCTAssertEqual(model.progress, 1)
        XCTAssertEqual(task.subtitles, ["Reviewing game 1/1", "Reviewed 1/1 games"])
    }

    @MainActor
    func testLateGrantAndOldExpirationCannotInterruptTheNextBatch() async throws {
        let games = DemoContent.games()
        var fast = DeviceEngineConfiguration()
        fast.engine = .tactical; fast.depth = 1; fast.nodesPerCandidate = 800
        let firstJob = LocalAnalysisJob(gameID: games[0].id, configuration: fast)
        let model = AppModel(previewLibrary: LibrarySnapshot(games: games, isDemo: true, localAnalysisJobs: [firstJob]))
        let coordinator = DeviceAnalysisCoordinator(model: model, schedulerEnabled: false)
        defer { coordinator.pause() }
        coordinator.prepareContinuedRequest(identifier: "first-request", jobIDs: [firstJob.id])
        let firstTask = BackgroundTaskFixture("first-request")
        await coordinator.accept(firstTask)
        for _ in 0..<500 where firstTask.completions.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(firstTask.completions, [true])

        var slow = fast
        slow.depth = 8; slow.nodesPerCandidate = 1_000_000; slow.secondsPerPosition = 3
        let nextJob = LocalAnalysisJob(gameID: games[1].id, configuration: slow)
        model.updateLibrary { $0.localAnalysisJobs?.append(nextJob) }
        coordinator.prepareContinuedRequest(identifier: "next-request", jobIDs: [nextJob.id])
        let nextTask = BackgroundTaskFixture("next-request")
        await coordinator.accept(nextTask)
        let lateGrant = BackgroundTaskFixture("first-request")
        await coordinator.accept(lateGrant)
        XCTAssertEqual(lateGrant.completions, [true])
        XCTAssertTrue(lateGrant.progress.isFinished)
        firstTask.expire()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(nextTask.completions.isEmpty, "An old callback must not complete or cancel the current grant")
        XCTAssertTrue(model.library.localAnalysisJobs?.last?.isPending == true)
        nextTask.expire()
        for _ in 0..<200 where nextTask.completions.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(nextTask.completions, [false], "A real system expiration remains an interruption")
        XCTAssertEqual(model.library.localAnalysisJobs?.last?.state, .queued)
        XCTAssertTrue(model.library.localAnalysisJobs?.last?.message?.contains("iOS") == true)
    }
}
