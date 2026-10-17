import XCTest
import ChessMeCore
@testable import ChessMe

final class RefinementTests: XCTestCase {
    @MainActor func testReviewFiltersIncludeAllAndBothSourcesFromHistory() {
        let game = ChessGame(id: "filter", username: "Learner", white: "Learner", black: "Opponent", playedAt: Date(), playerSide: .white, moves: "e4 e5")
        let partial = GameAnalysis(gameID: game.id, findings: [], analyzedPlies: 1, totalPlies: 2)
        let local = GameAnalysis(gameID: game.id, findings: [], analyzedPlies: 2, totalPlies: 2)
        let cloud = GameAnalysis(gameID: game.id, findings: [], analyzedPlies: 2, totalPlies: 2, source: "cloud")
        XCTAssertTrue(ReviewedGameFilter.all.includes(game: game, reviews: []))
        XCTAssertTrue(ReviewedGameFilter.all.includes(game: game, reviews: [partial]))
        XCTAssertFalse(ReviewedGameFilter.reviewed.includes(game: game, reviews: [partial]))
        XCTAssertTrue(ReviewedGameFilter.reviewed.includes(game: game, reviews: [local, cloud]))
        XCTAssertTrue(ReviewedGameFilter.local.includes(game: game, reviews: [cloud, local]))
        XCTAssertTrue(ReviewedGameFilter.cloud.includes(game: game, reviews: [local, cloud]))
    }
    @MainActor func testCompletedSavedReviewRemovesStaleQueueButDeeperWorkRemains() {
        let game = ChessGame(id: "queue", username: "Learner", white: "Learner", black: "Opponent", playedAt: Date(), playerSide: .white, moves: "e4 e5", speed: .rapid)
        let configuration = DeviceEngineConfiguration()
        let review = GameAnalysis(gameID: game.id, findings: [], analyzedPlies: 1, totalPlies: 1,
                                  engineVersion: StockfishEngine.version, configurationID: configuration.options.configurationID)
        let stale = LocalAnalysisJob(gameID: game.id, configuration: configuration)
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], analyses: [review], isDemo: true, localAnalysisJobs: [stale]))
        model.reconcileLocalAnalysisResults()
        XCTAssertTrue(model.queuedAnalysisGames.isEmpty)
        XCTAssertEqual(model.library.localAnalysisJobs?.first?.state, .completed)
        var deeper = configuration; deeper.depth = 28
        model.updateLibrary { $0.localAnalysisJobs?.append(LocalAnalysisJob(gameID: game.id, configuration: deeper, level: .deep)) }
        XCTAssertEqual(model.queuedAnalysisGames.map(\.id), [game.id])
        let complete = GameAnalysis(gameID: game.id, findings: [], analyzedPlies: 1, totalPlies: 1,
                                   engineVersion: StockfishEngine.version, configurationID: deeper.options.configurationID)
        model.updateLibrary { $0.localAnalysisJobs?[1].checkpoint = complete; $0.localAnalysisJobs?[1].state = .completed }
        model.acceptDeviceCheckpoint(complete)
        XCTAssertTrue(model.queuedAnalysisGames.isEmpty)
    }
    @MainActor func testOldAutomaticJobsAdoptSpeedSettingsAndManualJobsKeepTheirBudget() {
        let game = ChessGame(id: "old-bullet", username: "Learner", white: "Learner", black: "Opponent", playedAt: Date().addingTimeInterval(-60), playerSide: .white, moves: "e4 e5", speed: .bullet)
        let configuration = DeviceEngineConfiguration()
        let automatic = LocalAnalysisJob(gameID: game.id, configuration: configuration, requiresPro: true)
        var manual = LocalAnalysisJob(gameID: game.id, configuration: configuration, level: .deep)
        manual.scheduledByUser = true; manual.nightOnly = true
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], isDemo: true, localAnalysisJobs: [automatic, manual]))
        let originalSpeeds = model.automaticReviewSpeeds
        defer { model.pauseAnalysis(); model.automaticReviewSpeeds = originalSpeeds }
        model.automaticReviewSpeeds = [.rapid, .classical]
        let jobs = model.library.localAnalysisJobs ?? []
        XCTAssertEqual(jobs.first { $0.id == automatic.id }?.state, .paused)
        XCTAssertEqual(jobs.first { $0.id == manual.id }?.configuration.depth, configuration.depth)
        XCTAssertTrue(jobs.contains { $0.gameID == game.id && $0.level == nil && $0.configuration.depth == 8 && $0.requiresPro })
    }

    @MainActor func testFastGamesHaveQuickAutomaticReviewAndExplicitDeepOverride() async throws {
        let now = Date()
        let games = [GameSpeed.bullet, .blitz, .rapid].map { speed in
            ChessGame(id: speed.rawValue, username: "Learner", white: "Learner", black: "Opponent", playedAt: now.addingTimeInterval(-10), playerSide: .white, moves: "e4 e5", speed: speed)
        }
        let model = AppModel(previewLibrary: LibrarySnapshot(games: games, isDemo: true))
        let savedSpeeds = model.automaticReviewSpeeds
        defer { model.automaticReviewSpeeds = savedSpeeds; model.pauseAnalysis() }
        model.automaticReviewSpeeds = [.rapid, .classical]
        model.analyzePending()
        let jobs = model.library.localAnalysisJobs ?? []
        XCTAssertEqual(jobs.first { $0.gameID == "bullet" }?.configuration.depth, 8)
        XCTAssertEqual(jobs.first { $0.gameID == "blitz" }?.configuration.secondsPerPosition, 1)
        XCTAssertEqual(jobs.first { $0.gameID == "rapid" }?.configuration.depth, model.effectiveEngineConfiguration.depth)
        model.pauseAnalysis()
        model.analyzeOnDevice(gameID: "bullet")
        XCTAssertTrue(model.library.localAnalysisJobs?.contains { $0.gameID == "bullet" && $0.level != nil && $0.scheduledByUser == true } == true)
    }
}
