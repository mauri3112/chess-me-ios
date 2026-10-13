import XCTest
import Combine
import ChessMeCore
@testable import ChessMe

final class SyncTests: XCTestCase {
    func testPublicProfileFetchReadsCurrentRatingWithoutAccountCredentialsAndChecksIdentity() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyncProtocol.self]
        let service = LichessService(client: LichessHTTPClient(session: URLSession(configuration: configuration), gate: LichessRequestGate()))
        SyncProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/user/Learner")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, Data("{\"id\":\"learner\",\"username\":\"Learner\",\"perfs\":{\"puzzle\":{\"rating\":2100,\"games\":50}}}".utf8))
        }
        let profile = try await service.profile(username: "Learner")
        XCTAssertEqual(profile.suggestedPuzzleRating, 2100)
        SyncProtocol.handler = { _ in (200, Data("{\"id\":\"someone\",\"username\":\"Someone\"}".utf8)) }
        do { _ = try await service.profile(username: "Learner"); XCTFail("A different player's profile must not set the puzzle level") }
        catch { }
    }

    @MainActor
    func testPracticeSyncImportsNewGamesReportsPartialCoverageAndPreservesGamesOnFailure() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyncProtocol.self]
        let service = LichessService(client: LichessHTTPClient(session: URLSession(configuration: configuration), gate: LichessRequestGate()))
        let model = AppModel(previewLibrary: LibrarySnapshot(lastSyncedUsername: "Learner"), lichessService: service)
        let originalAutomatic = model.automaticPuzzleLevel
        let originalEngine = model.engineConfiguration
        defer { model.automaticPuzzleLevel = originalAutomatic; model.engineConfiguration = originalEngine }
        model.automaticPuzzleLevel = false
        model.engineConfiguration.engine = .material
        model.engineConfiguration.depth = 1
        var observedSync = false
        let observation = model.$isSyncing.sink { if $0 { observedSync = true } }
        defer { observation.cancel() }
        let createdAt = Int64(Date().addingTimeInterval(-100).timeIntervalSince1970 * 1000)
        SyncProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/games/user/Learner")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "clocks" }?.value, "true")
            let fixture = "{\"id\":\"syncfixture\",\"variant\":\"standard\",\"speed\":\"rapid\",\"createdAt\":\(createdAt),\"status\":\"resign\",\"players\":{\"white\":{\"user\":{\"id\":\"learner\",\"name\":\"Learner\"}},\"black\":{\"user\":{\"id\":\"partner\",\"name\":\"Partner\"}}},\"moves\":\"e4 e5 Nf3 Nc6\"}\ninvalid-export\n"
            return (200, Data(fixture.utf8))
        }
        await model.syncCompletedGames()
        XCTAssertTrue(observedSync)
        XCTAssertFalse(model.isSyncing)
        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.library.games.count, 1)
        XCTAssertEqual(model.syncMessage, "1 game synced · 1 new · partial import")
        XCTAssertTrue(model.library.coverageNote?.contains("partial") == true)
        let finished = expectation(description: "Imported games finish device review")
        let analysis = model.$isAnalyzing.filter { !$0 }.prefix(1).sink { _ in finished.fulfill() }
        defer { analysis.cancel() }
        await fulfillment(of: [finished], timeout: 10)
        await model.syncCompletedGames()
        XCTAssertEqual(model.library.games.count, 1)
        XCTAssertEqual(model.syncMessage, "1 game synced · 0 new · partial import")
        SyncProtocol.handler = { _ in (503, Data()) }
        await model.syncCompletedGames()
        XCTAssertFalse(model.isSyncing)
        XCTAssertNil(model.syncMessage)
        XCTAssertNotNil(model.notice)
        XCTAssertEqual(model.library.games.count, 1)
    }

    @MainActor
    func testExistingGameClockBackfillIsSharedSavedAndPreservesReviewAndPractice() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyncProtocol.self]
        let service = LichessService(client: LichessHTTPClient(session: URLSession(configuration: configuration), gate: LichessRequestGate()))
        let game = ChessGame(id: "clock123", username: "Learner", white: "Learner", black: "Partner", playedAt: Date(), playerSide: .white,
                             moves: "e4 e5 Nf3 Nc6", status: "resign")
        let analysis = GameAnalysis(gameID: game.id, findings: [], analyzedPlies: 2, totalPlies: 2, source: "cloud")
        let practice = PracticeRecord(findingID: "saved-finding", correctCount: 2, failedCount: 1, dueAt: Date(), lastPracticedAt: Date())
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], analyses: [analysis], practice: [practice]), lichessService: service)
        var requests = 0
        SyncProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.url?.path, "/game/export/clock123")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "clocks" }?.value, "true")
            return (200, Self.clockExport())
        }
        async let first: Void = model.loadGameClocks(gameID: game.id)
        async let second: Void = model.loadGameClocks(gameID: game.id)
        _ = try await (first, second)
        try await model.loadGameClocks(gameID: game.id)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(model.library.games.first?.clockData?.remainingCentiseconds, [30_000, 30_000, 29_100, 28_800])
        XCTAssertNotNil(model.library.games.first?.clockDataFetchedAt)
        XCTAssertEqual(model.library.analyses, [analysis])
        XCTAssertEqual(try GameReplay(game: model.library.games[0]).moves.count, 4)
        let restored = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(model.library))
        XCTAssertEqual(restored.games[0].clockData, model.library.games[0].clockData)
        XCTAssertEqual(restored.analyses, [analysis])
        XCTAssertEqual(restored.practice.first?.correctCount, 2)
        XCTAssertEqual(restored.practice.first?.failedCount, 1)
        // A later archive sync also must not invalidate cloud evidence solely because
        // its PGN now includes clock comments or its fetch timestamp changed.
        SyncProtocol.handler = { _ in (200, Self.clockExport() + Data([10])) }
        let imported = await model.importGames(username: "Learner")
        XCTAssertTrue(imported)
        XCTAssertEqual(model.syncMessage, "1 game synced · 0 new")
        XCTAssertEqual(model.library.analyses, [analysis])
        XCTAssertEqual(model.library.practice.first?.correctCount, 2)
    }

    @MainActor
    func testMissingClockExportIsRememberedAndChangedMovesCannotReplaceASavedGame() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyncProtocol.self]
        let service = LichessService(client: LichessHTTPClient(session: URLSession(configuration: configuration), gate: LichessRequestGate()))
        let game = ChessGame(id: "clock123", username: "Learner", white: "Learner", black: "Partner", playedAt: Date(), playerSide: .white,
                             moves: "e4 e5 Nf3 Nc6", status: "resign")
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game]), lichessService: service)
        var requests = 0
        SyncProtocol.handler = { _ in requests += 1; return (200, Self.clockExport(includeClocks: false)) }
        try await model.loadGameClocks(gameID: game.id)
        try await model.loadGameClocks(gameID: game.id)
        XCTAssertEqual(requests, 1)
        XCTAssertNil(model.library.games[0].clockData)
        XCTAssertNotNil(model.library.games[0].clockDataFetchedAt)
        let changed = AppModel(previewLibrary: LibrarySnapshot(games: [game]), lichessService: service)
        SyncProtocol.handler = { _ in (200, Self.clockExport(moves: "d4 d5")) }
        try await changed.loadGameClocks(gameID: game.id)
        XCTAssertEqual(changed.library.games[0], game)
    }

    private static func clockExport(includeClocks: Bool = true, moves: String = "e4 e5 Nf3 Nc6") -> Data {
        let clocks = includeClocks ? ",\"clock\":{\"initial\":300,\"increment\":3},\"clocks\":[30000,30000,29100,28800]" : ""
        let createdAt = Int64(Date().addingTimeInterval(-100).timeIntervalSince1970 * 1_000)
        return Data("{\"id\":\"clock123\",\"variant\":\"standard\",\"speed\":\"rapid\",\"createdAt\":\(createdAt),\"status\":\"resign\",\"players\":{\"white\":{\"user\":{\"id\":\"learner\",\"name\":\"Learner\"}},\"black\":{\"user\":{\"id\":\"partner\",\"name\":\"Partner\"}}},\"moves\":\"\(moves)\"\(clocks)}".utf8)
    }
}

private final class SyncProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (statusCode, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: ["Content-Type": "application/x-ndjson"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
