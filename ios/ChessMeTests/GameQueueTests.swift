import XCTest
import ChessMeCore
@testable import ChessMe

final class GameQueueTests: XCTestCase {
    private var preferences: Data?
    override func setUpWithError() throws {
        preferences = UserDefaults.standard.data(forKey: "analysis.overnight.settings")
        UserDefaults.standard.removeObject(forKey: "analysis.overnight.settings")
    }
    override func tearDownWithError() throws {
        if let preferences { UserDefaults.standard.set(preferences, forKey: "analysis.overnight.settings") }
        else { UserDefaults.standard.removeObject(forKey: "analysis.overnight.settings") }
    }
    @MainActor
    func testSelectedNightGamesAreSavedWithoutEnablingAutomaticQueueing() throws {
        let games = DemoContent.games()
        let model = AppModel(previewLibrary: LibrarySnapshot(games: games, isDemo: true))
        defer { model.pauseAnalysis() }
        let selected = try XCTUnwrap(games.first)
        XCTAssertTrue(model.queueForAnalysis(gameIDs: [selected.id], schedule: .night))
        XCTAssertFalse(model.overnightSettings.enabled)
        XCTAssertEqual(model.library.localAnalysisJobs?.count, 1)
        let job = try XCTUnwrap(model.library.localAnalysisJobs?.first)
        XCTAssertEqual(job.gameID, selected.id)
        XCTAssertTrue(job.nightOnly)
        XCTAssertEqual(job.scheduledByUser, true)
        let encoded = try JSONEncoder().encode(model.library)
        let restored = try JSONDecoder().decode(LibrarySnapshot.self, from: encoded)
        XCTAssertEqual(restored.localAnalysisJobs?.first?.scheduledByUser, true)
        XCTAssertEqual(restored.localAnalysisJobs?.first?.id, job.id)
    }
    @MainActor
    func testTurningAutomaticNightQueueOffPreservesExplicitSelections() throws {
        let games = DemoContent.games()
        let model = AppModel(previewLibrary: LibrarySnapshot(games: games, isDemo: true))
        defer { model.pauseAnalysis() }
        let selected = try XCTUnwrap(games.first)
        XCTAssertTrue(model.queueForAnalysis(gameIDs: [selected.id], schedule: .night))
        model.overnightSettings.enabled = true
        XCTAssertGreaterThan(model.library.localAnalysisJobs?.count ?? 0, 1)
        model.overnightSettings.enabled = false
        XCTAssertEqual(model.library.localAnalysisJobs?.count, 1)
        XCTAssertEqual(model.library.localAnalysisJobs?.first?.gameID, selected.id)
        XCTAssertEqual(model.library.localAnalysisJobs?.first?.scheduledByUser, true)
    }
    @MainActor
    func testChangingSelectedGameFromNightToNowReusesItsCheckpointAndJob() throws {
        let game = try XCTUnwrap(DemoContent.games().first)
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], isDemo: true))
        defer { model.pauseAnalysis() }
        XCTAssertTrue(model.queueForAnalysis(gameIDs: [game.id], schedule: .night))
        let id = try XCTUnwrap(model.library.localAnalysisJobs?.first?.id)
        XCTAssertTrue(model.queueForAnalysis(gameIDs: [game.id], schedule: .now))
        XCTAssertEqual(model.library.localAnalysisJobs?.count, 1)
        XCTAssertEqual(model.library.localAnalysisJobs?.first?.id, id)
        XCTAssertFalse(model.library.localAnalysisJobs?.first?.nightOnly ?? true)
    }
    @MainActor
    func testInvalidAndEmptySelectionsDoNotChangeTheQueue() {
        let model = AppModel(previewLibrary: LibrarySnapshot(games: DemoContent.games(), isDemo: true))
        XCTAssertFalse(model.queueForAnalysis(gameIDs: [], schedule: .night))
        XCTAssertFalse(model.queueForAnalysis(gameIDs: ["not-in-period"], schedule: .night))
        XCTAssertTrue(model.library.localAnalysisJobs?.isEmpty ?? true)
    }
    @MainActor
    func testGameOutcomeChangesWhenMetadataArrivesWithoutReplacingAnalysis() throws {
        let old = ChessGame(id: "result-update", username: "Learner", white: "Learner", black: "Partner", playedAt: Date(),
                            playerSide: .white, moves: "e4 e5", status: "resign")
        let review = GameAnalysis(gameID: old.id, findings: [], analyzedPlies: 1, totalPlies: 1)
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [old], analyses: [review], isDemo: true))
        XCTAssertNil(model.outcome(for: old))
        let updated = old.withResult(.blackWin)
        model.updateLibrary { $0.games = [updated] }
        XCTAssertEqual(model.outcome(for: updated), .lost)
        XCTAssertEqual(model.library.analyses.first?.completedAt, review.completedAt)
    }
    func testProviderWinnerIsImportedForTheCorrectPlayerSide() throws {
        let object: [String: Any] = ["id": "result01", "variant": "standard", "speed": "blitz", "createdAt": Int64(Date().timeIntervalSince1970 * 1000),
            "status": "resign", "winner": "black", "moves": "e4 e5 Nf3 Nc6",
            "players": ["white": ["user": ["id": "partner", "name": "Partner"]], "black": ["user": ["id": "learner", "name": "Learner"]]]]
        let record = try JSONDecoder().decode(LichessGameRecord.self, from: JSONSerialization.data(withJSONObject: object))
        let imported = try record.importGame(username: "Learner", start: .distantPast, end: Date()).get()
        XCTAssertEqual(imported.playerSide, .black)
        XCTAssertEqual(imported.result, .blackWin)
        XCTAssertEqual(imported.finishedResult?.outcome(for: imported.playerSide), .won)
        XCTAssertEqual(imported.reviewLabel, "You vs Partner")
    }
}
