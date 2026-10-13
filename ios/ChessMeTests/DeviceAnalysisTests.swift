import XCTest
import Combine
import ChessMeCore
@testable import ChessMe

final class DeviceAnalysisTests: XCTestCase {
    @MainActor
    func testManualReviewOverridesAnOvernightWaitWithoutDuplicatingTheJob() async throws {
        let game = try XCTUnwrap(DemoContent.games().first)
        var configuration = DeviceEngineConfiguration()
        configuration.engine = .tactical; configuration.depth = 1; configuration.nodesPerCandidate = 800
        let nightJob = LocalAnalysisJob(gameID: game.id, configuration: configuration, level: .balanced,
                                       nightOnly: true, requiresPro: true)
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], isDemo: true, localAnalysisJobs: [nightJob]))
        let completed = expectation(description: "An eligible free-window manual request overrides the overnight wait")
        let observation = model.$library.filter { $0.localAnalysisJobs?.first?.state == .completed }.prefix(1).sink { _ in completed.fulfill() }
        defer { observation.cancel(); model.pauseAnalysis() }
        model.deviceAnalysis.enqueue(games: [game], configuration: configuration, level: .balanced, requiresPro: false)
        await fulfillment(of: [completed], timeout: 15)
        let job = try XCTUnwrap(model.library.localAnalysisJobs?.first)
        XCTAssertEqual(model.library.localAnalysisJobs?.count, 1)
        XCTAssertEqual(job.id, nightJob.id)
        XCTAssertFalse(job.nightOnly)
        XCTAssertFalse(job.requiresPro)
    }

    @MainActor
    func testPlayerSelectedDeepReviewRunsBeforeTheImportedBacklog() async throws {
        let games = DemoContent.games()
        let selected = try XCTUnwrap(games.last)
        let queued = try XCTUnwrap(games.first)
        XCTAssertNotEqual(selected.id, queued.id)
        var configuration = DeviceEngineConfiguration()
        configuration.engine = .tactical; configuration.depth = 1; configuration.nodesPerCandidate = 800
        let backlog = LocalAnalysisJob(gameID: queued.id, configuration: configuration)
        let model = AppModel(previewLibrary: LibrarySnapshot(games: games, isDemo: true, localAnalysisJobs: [backlog]))
        let firstDecision = expectation(description: "The selected game is reviewed before the backlog")
        var firstGameID: String?
        let observation = model.$library.compactMap { snapshot in
            snapshot.localAnalysisJobs?.first { ($0.checkpoint?.analyzedPlies ?? 0) > 0 }?.gameID
        }.prefix(1).sink { id in firstGameID = id; firstDecision.fulfill() }
        defer { observation.cancel(); model.pauseAnalysis() }
        model.deviceAnalysis.enqueue(games: [selected], configuration: configuration, level: .balanced)
        await fulfillment(of: [firstDecision], timeout: 15)
        XCTAssertEqual(firstGameID, selected.id)
    }

    @MainActor
    func testDurableQueueResumesAPartialReviewWithoutDuplicatingDecisions() async throws {
        let game = try XCTUnwrap(DemoContent.games().first)
        var configuration = DeviceEngineConfiguration()
        configuration.engine = .tactical; configuration.depth = 1; configuration.nodesPerCandidate = 800
        var options = configuration.options
        options.maximumPositions = 1
        let checkpoint = try LocalAnalyzer(options: options).analyze(game: game)
        var job = LocalAnalysisJob(gameID: game.id, configuration: configuration)
        job.checkpoint = checkpoint; job.state = .paused
        let library = LibrarySnapshot(games: [game], analyses: [checkpoint], isDemo: true, localAnalysisJobs: [job])
        let model = AppModel(previewLibrary: library)
        let completed = expectation(description: "The persisted review resumes and completes")
        let observation = model.$library.filter { $0.localAnalysisJobs?.first?.state == .completed }.prefix(1).sink { _ in completed.fulfill() }
        defer { observation.cancel(); model.pauseAnalysis() }
        model.deviceAnalysis.enqueue(games: [game], configuration: configuration)
        await fulfillment(of: [completed], timeout: 15)
        let final = try XCTUnwrap(model.library.localAnalysisJobs?.first?.checkpoint)
        XCTAssertTrue(final.isComplete)
        XCTAssertEqual(model.library.localAnalysisJobs?.count, 1)
        XCTAssertEqual(Set(final.moveAssessments?.map(\.ply) ?? []).count, final.moveAssessments?.count)
        XCTAssertTrue(checkpoint.findings.allSatisfy { previous in final.findings.contains { $0.id == previous.id } })
    }

    @MainActor
    func testPartialReplacementRetainsExistingCompleteReview() throws {
        let game = try XCTUnwrap(DemoContent.games().first)
        let complete = try LocalAnalyzer(options: AnalysisOptions(maximumDepth: 1)).analyze(game: game)
        let partial = try LocalAnalyzer(options: AnalysisOptions(maximumDepth: 2, maximumPositions: 1)).analyze(game: game)
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], analyses: [complete], isDemo: true))
        model.acceptDeviceCheckpoint(partial)
        XCTAssertTrue(try XCTUnwrap(model.library.analyses.first).isComplete)
        XCTAssertEqual(model.library.analyses.first?.configurationID, complete.configurationID)
    }

    func testLibraryFromOlderBuildLoadsWithoutAQueue() throws {
        let legacy = Data("{\"games\":[],\"analyses\":[],\"practice\":[],\"isDemo\":false,\"skippedGames\":0}".utf8)
        XCTAssertNil(try JSONDecoder().decode(LibrarySnapshot.self, from: legacy).localAnalysisJobs)
    }
}
