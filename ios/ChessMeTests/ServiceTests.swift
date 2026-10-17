import XCTest
import ChessMeCore
@testable import ChessMe

final class ServiceTests: XCTestCase {
    func testCloudFailurePausesAutomaticAndManualRequestsAcrossEndpoints() async throws {
        var requests = 0
        DeliveryProtocol.handler = { _ in
            requests += 1
            return (503, Data(#"{"error":{"code":"provider_unavailable","message":"Lichess is temporarily unavailable."}}"#.utf8))
        }
        defer { DeliveryProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeliveryProtocol.self]
        let cloud = CloudAnalysisService(baseURL: URL(string: "https://example.com/chessme")!, session: URLSession(configuration: configuration))
        do { _ = try await cloud.jobs(lichessToken: "fixture-token"); XCTFail("Initial request must fail") }
        catch CloudError.service(_, _, _, 503) { }
        let retryAt = await cloud.nextRetryAt
        XCTAssertGreaterThan(try XCTUnwrap(retryAt).timeIntervalSinceNow, 25)
        for _ in 0..<5 {
            do { _ = try await cloud.account(lichessToken: "fixture-token", consented: true); XCTFail("Retry must wait") }
            catch CloudError.paused { }
        }
        XCTAssertEqual(requests, 1, "Repeated polling and manual account actions must not send more upstream requests")
    }

    func testCloudPollingBacksOffHonorsServerDelayAndStopsForRevokedAccess() async throws {
        let now = Date(timeIntervalSince1970: 1000)
        let cooldown = CloudRequestCooldown()
        let error = CloudError.service(code: "provider_rate_limited", message: "Wait for Lichess.", requestID: nil, status: 503)
        await cooldown.failed(error, retryAfter: 180, now: now)
        do { try await cooldown.check(now: now.addingTimeInterval(179)); XCTFail("Retry-After must be honored") }
        catch CloudError.paused { }
        try await cooldown.check(now: now.addingTimeInterval(180))
        var schedule = CloudPollingSchedule()
        schedule.succeeded(pending: true, now: now)
        XCTAssertFalse(schedule.canRefresh(now: now.addingTimeInterval(4)))
        schedule.failed(error, retryAt: now.addingTimeInterval(180), now: now)
        XCTAssertFalse(schedule.canRefresh(now: now.addingTimeInterval(60)))
        XCTAssertTrue(schedule.canRefresh(now: now.addingTimeInterval(180)))
        schedule.succeeded(pending: false, now: now)
        XCTAssertEqual(schedule.nextAttemptAt, now.addingTimeInterval(60))
        schedule.failed(CloudError.service(code: "unauthorized", message: "Reconnect.", requestID: nil, status: 401), now: now)
        XCTAssertFalse(schedule.canRefresh(now: now.addingTimeInterval(3600)), "Expired credentials need reconnection, not automatic polling")
    }

    func testQueuedReviewAdaptsSavedSettingsToCurrentWorkerLimits() async throws {
        let game = try record().importGame(username: "Learner", start: start, end: end).get()
        let jobID = UUID()
        var requests: [String] = []
        DeliveryProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            requests.append(path)
            if path == "/chessme/v1/engines" {
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                return (200, Data(#"{"engines":[{"id":"stockfish","name":"Stockfish","available":true,"network":"Default"}],"max_depth":16,"max_hash_mb":64,"max_threads":1,"worker_memory_mb":512,"nodes_per_game":260000000,"timeout_seconds":240}"#.utf8))
            }
            XCTAssertEqual(path, "/chessme/v1/analysis/jobs")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONSerialization.jsonObject(with: self.bodyData(request)) as! [String: Any]
            let options = try XCTUnwrap(body["options"] as? [String: Any])
            XCTAssertEqual(options["engine_id"] as? String, "stockfish")
            XCTAssertEqual(options["depth"] as? Int, 16)
            XCTAssertEqual(options["hash_mb"] as? Int, 64)
            XCTAssertEqual(options["threads"] as? Int, 1)
            return (202, Data("""
            {"job_id":"\(jobID)","game_id":"\(game.id)","state":"queued",
             "submitted_at":"2026-10-04T12:00:00Z","deadline_at":"2026-10-05T12:00:00Z",
             "estimated_completion_at":null,"queue_position":0,"quota_remaining":29,
             "result":null,"error_code":null}
            """.utf8))
        }
        defer { DeliveryProtocol.handler = nil }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [DeliveryProtocol.self]
        let cloud = CloudAnalysisService(baseURL: URL(string: "https://example.com/chessme")!,
                                         session: URLSession(configuration: sessionConfiguration))
        let credential = CloudSubscriptionCredential(signedTransaction: "fixture-signed-transaction", appAccountToken: UUID())
        let defaults = CloudEngineConfiguration()
        let job = try await cloud.enqueue(game: game, credential: credential, lichessToken: "fixture-token",
                                          consented: true, configuration: defaults)
        XCTAssertEqual(job.job_id, jobID)
        XCTAssertEqual(requests, ["/chessme/v1/engines", "/chessme/v1/analysis/jobs"])
        XCTAssertEqual(defaults.hash_mb, 256, "Submission must not overwrite the saved preference")
    }

    @MainActor
    func testCloudAcknowledgementWaitsForDurableSaveAndCanRetryAfterRelaunch() async throws {
        let game = try record().importGame(username: "Learner", start: start, end: end).get()
        let result = try cloudResponse()
        let job = CloudAnalysisJob(job_id: UUID(), game_id: game.id, state: "completed", submitted_at: start,
                                   deadline_at: end, estimated_completion_at: nil, queue_position: nil,
                                   quota_remaining: 29, result: result, error_code: nil, result_token: String(repeating: "a", count: 64))
        let review = CloudReviewRecord(job: job, accountID: "Learner")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory); DeliveryProtocol.handler = nil }
        let storage = try LocalLibrary(url: directory.appendingPathComponent("library.json"))
        let snapshot = LibrarySnapshot(games: [game], analyses: [try result.analysis(for: game)], cloudReviews: [review])
        var attempts = 0
        DeliveryProtocol.handler = { request in
            attempts += 1
            let saved = try storage.load()
            XCTAssertEqual(saved.analyses.count, 1)
            XCTAssertEqual(saved.cloudReviews?.first?.resultToken, job.result_token)
            XCTAssertTrue(saved.cloudReviews?.first?.needsAcknowledgement == true)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/chessme/v1/analysis/jobs/\(job.job_id.uuidString)/acknowledge")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
            if attempts == 1 { return (503, Data()) }
            return (200, Data("{\"job_id\":\"\(job.job_id)\",\"acknowledged\":true}".utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeliveryProtocol.self]
        let cloud = CloudAnalysisService(baseURL: URL(string: "https://example.com/chessme")!, session: URLSession(configuration: configuration))
        do {
            try await cloud.acknowledgeSavedReview(review, lichessToken: "fixture-token") { try storage.save(snapshot) }
            XCTFail("The first confirmation must fail")
        } catch { }
        let relaunched = try LocalLibrary(url: directory.appendingPathComponent("library.json")).load()
        let pending = try XCTUnwrap(relaunched.cloudReviews?.first)
        XCTAssertTrue(pending.needsAcknowledgement)
        let relaunchedCloud = CloudAnalysisService(baseURL: URL(string: "https://example.com/chessme")!, session: URLSession(configuration: configuration))
        try await relaunchedCloud.acknowledgeSavedReview(pending, lichessToken: "fixture-token") { try storage.save(relaunched) }
        XCTAssertEqual(attempts, 2)
    }

    @MainActor
    func testCloudAcknowledgementNeverSendsWhenLocalSaveFails() async throws {
        let game = try record().importGame(username: "Learner", start: start, end: end).get()
        let job = CloudAnalysisJob(job_id: UUID(), game_id: game.id, state: "completed", submitted_at: start,
                                   deadline_at: end, estimated_completion_at: nil, queue_position: nil,
                                   quota_remaining: 29, result: try cloudResponse(), error_code: nil, result_token: String(repeating: "b", count: 64))
        DeliveryProtocol.handler = { _ in XCTFail("Failed save must not acknowledge server data"); return (200, Data()) }
        defer { DeliveryProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeliveryProtocol.self]
        let cloud = CloudAnalysisService(baseURL: URL(string: "https://example.com/chessme")!, session: URLSession(configuration: configuration))
        let storage = try LocalLibrary(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/missing/library.json"))
        do {
            try await cloud.acknowledgeSavedReview(CloudReviewRecord(job: job, accountID: "Learner"), lichessToken: "fixture-token") {
                try storage.save(LibrarySnapshot())
            }
            XCTFail("An unavailable directory must fail to save")
        } catch { XCTAssertTrue(error is CocoaError) }
    }

    @MainActor
    func testSavedReviewStopsRetryingWhenServerCopyIsAlreadyGone() async throws {
        let game = try record().importGame(username: "Learner", start: start, end: end).get()
        let job = CloudAnalysisJob(job_id: UUID(), game_id: game.id, state: "completed", submitted_at: start,
                                   deadline_at: end, estimated_completion_at: nil, queue_position: nil,
                                   quota_remaining: 29, result: try cloudResponse(), error_code: nil, result_token: String(repeating: "c", count: 64))
        var saved = false
        DeliveryProtocol.handler = { _ in
            XCTAssertTrue(saved)
            return (404, Data(#"{"error":{"code":"job_unavailable","message":"This review has expired."}}"#.utf8))
        }
        defer { DeliveryProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeliveryProtocol.self]
        let cloud = CloudAnalysisService(baseURL: URL(string: "https://example.com/chessme")!, session: URLSession(configuration: configuration))
        try await cloud.acknowledgeSavedReview(CloudReviewRecord(job: job, accountID: "Learner"), lichessToken: "fixture-token") { saved = true }
        XCTAssertTrue(saved)
    }

    func testQueuedCloudReferenceSurvivesRelaunchWithoutCredentials() throws {
        let id = UUID()
        let data = Data("""
        {"job_id":"\(id)","game_id":"abcdefgh","state":"queued",
         "submitted_at":"2026-10-04T12:00:00Z","deadline_at":"2026-10-05T12:00:00Z",
         "estimated_completion_at":"2026-10-04T13:00:00Z","queue_position":3,
         "quota_remaining":29,"result":null,"error_code":null}
        """.utf8)
        let job = try CloudAnalysisService.decoder().decode(CloudAnalysisJob.self, from: data)
        try job.validate()
        let snapshot = LibrarySnapshot(cloudReviews: [CloudReviewRecord(job: job, accountID: "Learner")])
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(LibrarySnapshot.self, from: encoded)
        let reference = try XCTUnwrap(decoded.cloudReviews?.first)
        XCTAssertEqual(reference.id, id)
        XCTAssertEqual(reference.accountID, "learner")
        XCTAssertTrue(reference.isPending)
        XCTAssertEqual(reference.statusText, "Cloud review queued")
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("signed_transaction"))
        let legacy = try JSONEncoder().encode(LibrarySnapshot())
        XCTAssertNil(try JSONDecoder().decode(LibrarySnapshot.self, from: legacy).cloudReviews)
    }

    func testQueueRejectsUnrecognisedStatesAndCompletedJobsWithoutResults() throws {
        func job(state: String) throws -> CloudAnalysisJob {
            let data = Data("""
            {"job_id":"\(UUID())","game_id":"abcdefgh","state":"\(state)",
             "submitted_at":"2026-10-04T12:00:00Z","deadline_at":"2026-10-05T12:00:00Z",
             "estimated_completion_at":null,"queue_position":null,"quota_remaining":29,
             "result":null,"error_code":null}
            """.utf8)
            return try CloudAnalysisService.decoder().decode(CloudAnalysisJob.self, from: data)
        }
        XCTAssertThrowsError(try job(state: "completed").validate())
        XCTAssertThrowsError(try job(state: "partial").validate())
        XCTAssertThrowsError(try job(state: "invented").validate())
        XCTAssertNoThrow(try job(state: "failed").validate())
    }

    func testPuzzleLevelUsesTheProfilePuzzleRatingAndIgnoresUnplayedPerformances() throws {
        func account(_ perfs: String) throws -> LichessAccount {
            try JSONDecoder().decode(LichessAccount.self, from: Data("{\"id\":\"learner\",\"username\":\"Learner\",\"perfs\":\(perfs)}".utf8))
        }
        XCTAssertEqual(try account("{\"puzzle\":{\"rating\":2100,\"games\":200},\"rapid\":{\"rating\":1600,\"games\":10},\"storm\":{\"score\":30,\"runs\":2}}").suggestedPuzzleRating, 2100)
        XCTAssertEqual(try account("{\"puzzle\":{\"rating\":1500,\"games\":0},\"rapid\":{\"rating\":1600,\"games\":10}}").suggestedPuzzleRating, 1600)
        XCTAssertEqual(try account("{\"rapid\":{\"rating\":1200,\"games\":2,\"prov\":true},\"blitz\":{\"rating\":1700,\"games\":100}}").suggestedPuzzleRating, 1700)
        XCTAssertNil(try account("{\"puzzle\":{\"rating\":1500,\"games\":0}}").suggestedPuzzleRating)
        let legacy = try JSONDecoder().decode(LichessAccount.self, from: Data("{\"id\":\"learner\",\"username\":\"Learner\"}".utf8))
        XCTAssertNil(legacy.suggestedPuzzleRating)
    }

    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private var end: Date { start.addingTimeInterval(86_400) }

    func testOnlyFinishedStandardGamesWithKnownPlayerAreImported() throws {
        let valid = try record()
        let game = try valid.importGame(username: "Learner", start: start, end: end).get()
        XCTAssertEqual(game.playerSide, .white)
        XCTAssertEqual(game.moves, "e4 e5 Nf3 Nc6")
        XCTAssertEqual(game.playedAt, start.addingTimeInterval(1))
        XCTAssertThrowsError(try record(status: "started").importGame(username: "Learner", start: start, end: end).get())
        XCTAssertThrowsError(try record(variant: "chess960").importGame(username: "Learner", start: start, end: end).get())
        XCTAssertThrowsError(try record(speed: "correspondence").importGame(username: "Learner", start: start, end: end).get())
        XCTAssertThrowsError(try valid.importGame(username: "SomebodyElse", start: start, end: end).get())
    }

    func testImportWindowUsesGameCreationTimeAndIncludesBoundaries() throws {
        let atStart = try record(createdAt: Int64(start.timeIntervalSince1970 * 1000))
        let atEnd = try record(createdAt: Int64(end.timeIntervalSince1970 * 1000))
        XCTAssertNoThrow(try atStart.importGame(username: "Learner", start: start, end: end).get())
        XCTAssertNoThrow(try atEnd.importGame(username: "Learner", start: start, end: end).get())
        let outside = try record(createdAt: Int64(start.timeIntervalSince1970 * 1000) - 1)
        XCTAssertThrowsError(try outside.importGame(username: "Learner", start: start, end: end).get())
    }

    func testPublicUsernameValidationCannotInjectURLPaths() {
        XCTAssertTrue(LichessService.isValidUsername("Learner_123"))
        XCTAssertFalse(LichessService.isValidUsername("Learner/../account"))
        XCTAssertFalse(LichessService.isValidUsername("Learner?max=1"))
        XCTAssertFalse(LichessService.isValidUsername(""))
    }

    @MainActor
    func testOAuthRedirectMatchesRegisteredReverseDomainScheme() throws {
        let redirect = LichessAuthentication.defaultRedirectURI
        XCTAssertEqual(redirect.absoluteString, "com.chessme.app://oauth/callback")
        XCTAssertEqual(redirect.scheme, Bundle.main.bundleIdentifier)
        let urlTypes = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.contains(try XCTUnwrap(redirect.scheme)))
    }

    @MainActor
    func testOAuthCallbackRejectsWrongStateLocationAndDuplicateParameters() throws {
        let redirect = LichessAuthentication.defaultRedirectURI
        let valid = URL(string: "com.chessme.app://oauth/callback?code=liu_ABC123&state=expected")!
        XCTAssertEqual(try LichessAuthentication.validateCallback(valid, redirectURI: redirect, state: "expected"), "liu_ABC123")
        for value in [
            "chessme://oauth/callback?code=liu_ABC123&state=expected",
            "com.chessme.app://oauth/callback?code=liu_ABC123&state=attacker",
            "com.chessme.app://elsewhere/callback?code=liu_ABC123&state=expected",
            "com.chessme.app://oauth/other?code=liu_ABC123&state=expected",
            "com.chessme.app://oauth/callback?code=liu_ABC123&state=expected&state=expected",
            "com.chessme.app://oauth/callback?code=liu_ABC123&code=second&state=expected",
            "com.chessme.app://oauth/callback?error=access_denied&state=expected"
        ] {
            XCTAssertThrowsError(try LichessAuthentication.validateCallback(URL(string: value)!, redirectURI: redirect, state: "expected"))
        }
    }

    func testCloudConfigurationRequiresHTTPSWithoutCredentials() {
        XCTAssertNotNil(CloudAnalysisService.validatedURL(URL(string: "https://analysis.example.com")!))
        for url in ["http://analysis.example.com", "https://token@analysis.example.com", "https://analysis.example.com?token=secret"] {
            XCTAssertNil(CloudAnalysisService.validatedURL(URL(string: url)!))
        }
        XCTAssertFalse(CloudAnalysisService(baseURL: nil).isConfigured)
    }

    func testCloudLessonMappingValidatesImportedPositionAndContinuation() throws {
        let game = try record().importGame(username: "Learner", start: start, end: end).get()
        let response = try cloudResponse()
        let analysis = try response.analysis(for: game)
        XCTAssertTrue(analysis.findings.isEmpty, "An opening finding without blunder evidence is not a lesson")
        XCTAssertEqual(analysis.source, "cloud")
        XCTAssertTrue(analysis.isComplete)
        XCTAssertThrowsError(try cloudResponse(continuation: ["d2d4", "a8a1"]).analysis(for: game))
        XCTAssertThrowsError(try cloudResponse(playedMove: "a2a3").analysis(for: game))
        XCTAssertThrowsError(try cloudResponse(totalPlies: 3).analysis(for: game))
    }

    func testStockfishBlackMateFixtureMatchesNativeReplayAndEnPassant() throws {
        // Generated by the Python worker from a synthetic completed game, not a private game archive.
        // Kept inline so this test also works on devices without access to the source checkout.
        let fixture = #"""
        {
          "game_id":"abcdefgh","engine":"Stockfish 19","engine_version":"Stockfish 19",
          "analyzed_at":"2026-10-02T20:00:00Z","source":"cloud",
          "findings":[{
            "id":"83947625-0c02-5197-b200-b312ce7c64ae","gameID":"abcdefgh",
            "positionFEN":"rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq g3 0 2",
            "playedMove":"b8c6","bestMove":"d8h4","acceptedMoves":["d8h4"],"continuation":["d8h4"],
            "centipawnLoss":9753.0,"theme":"Missed mate",
            "explanation":"Qh4# ends the game with checkmate. Nc6 missed that chance.",
            "hint":"Look for a move that gives checkmate.","moveNumber":2,"isPuzzle":true
          }],
          "nodes_used":32013,"analyzed_plies":2,"total_plies":2,"quota_remaining":119
        }
        """#
        let game = ChessGame(id: "abcdefgh", username: "Learner", white: "Opponent", black: "Learner",
                             playedAt: start, playerSide: .black, moves: "f3 e5 g4 Nc6", status: "resign")
        let response = try CloudAnalysisService.decoder().decode(AnalysisResponse.self, from: Data(fixture.utf8))
        let analysis = try response.analysis(for: game)
        XCTAssertEqual(analysis.totalPlies, 2)
        XCTAssertTrue(analysis.isComplete)
        XCTAssertTrue(analysis.findings.isEmpty, "Missing mate in an otherwise winning opening is not a practice blunder")
        let finding = try XCTUnwrap(response.findings.first)
        let position = try ChessPosition(fen: finding.positionFEN)
        XCTAssertEqual(position.sideToMove, .black)
        XCTAssertEqual(position.enPassantSquare, ChessMove.square("g3"))
        let mate = try position.applying(ChessMove(uci: finding.bestMove))
        XCTAssertTrue(mate.isInCheck)
        XCTAssertTrue(mate.legalMoves().isEmpty)
    }

    func testRateLimitBackoffHonorsLichessMinimumAndRetryAfter() {
        let url = URL(string: "https://lichess.org/api/account")!
        let short = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "2"])!
        let long = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "180"])!
        XCTAssertEqual(LichessHTTPClient.retryDelay(short, attempt: 0), 60)
        XCTAssertEqual(LichessHTTPClient.retryDelay(long, attempt: 0), 180)
        XCTAssertEqual(LichessHTTPClient.retryDelay(short, attempt: 1), 120)
    }

    func testLichessRequestsRemainSerialAcrossConcurrentCallers() async throws {
        let gate = LichessRequestGate()
        let probe = ConcurrencyProbe()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await gate.perform {
                        await probe.start()
                        try await Task.sleep(for: .milliseconds(5))
                        await probe.stop()
                    }
                }
            }
            try await group.waitForAll()
        }
        let maximum = await probe.maximum
        XCTAssertEqual(maximum, 1)
    }

    func testQueuedLichessRequestCanCancelWithoutWaitingForActiveStream() async throws {
        let gate = LichessRequestGate()
        let started = expectation(description: "first request started")
        let cancelled = expectation(description: "queued request cancelled")
        let first = Task {
            try await gate.perform {
                started.fulfill()
                try await Task.sleep(for: .seconds(10))
            }
        }
        await fulfillment(of: [started], timeout: 1)
        let queued = Task {
            do { try await gate.perform { XCTFail("Cancelled request must not start") } }
            catch is CancellationError { cancelled.fulfill() }
            catch { XCTFail("Unexpected cancellation error: \(error)") }
        }
        queued.cancel()
        await fulfillment(of: [cancelled], timeout: 1)
        first.cancel()
        _ = try? await first.value
        await queued.value
    }

    private func bodyData(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? CloudError.invalidResponse }
            if count == 0 { return body }
            body.append(contentsOf: buffer.prefix(count))
        }
    }

    @MainActor
    func testCloudBatchEligibilityRejectsDuplicatesForeignPlayersAndUnsupportedGames() {
        func game(_ id: String, _ player: String = "Learner", _ status: String = "mate", _ date: Date = Date()) -> ChessGame {
            ChessGame(id: id, username: player, white: player, black: "Opponent", playedAt: date,
                      playerSide: .white, moves: "e4 e5", status: status)
        }
        let old = game("old", "Learner", "mate", Date().addingTimeInterval(-100))
        let fresh = game("fresh")
        let results = AppModel.cloudCandidates([old, fresh, fresh, game("foreign", "Other"), game("playing", "Learner", "started"),
                                               game("demo-1"), game("pgn-1"), game("pending")],
                                              username: "learner", excluding: ["pending"])
        XCTAssertEqual(results.map(\.id), ["fresh", "old"])
    }

    func testCloudConsentSubmissionKeysAndUnfinishedBatchSurviveLocalRelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let local = try LocalLibrary(url: url)
        let requestID = UUID()
        var snapshot = LibrarySnapshot()
        snapshot.cloudReviewAccounts = ["learner"]
        snapshot.cloudEnabledAccounts = ["learner"]
        snapshot.cloudSubmissionKeys = ["learner:abcdefgh:settings": requestID]
        snapshot.cloudBatch = CloudBatchRecord(accountID: "learner", gameIDs: ["abcdefgh", "ijklmnop"], submittedGameIDs: ["abcdefgh"], startedAt: Date())
        try local.save(snapshot)
        let reopened = try local.load()
        XCTAssertEqual(reopened.cloudReviewAccounts, ["learner"])
        XCTAssertEqual(reopened.cloudEnabledAccounts, ["learner"])
        XCTAssertEqual(reopened.cloudSubmissionKeys?["learner:abcdefgh:settings"], requestID)
        XCTAssertEqual(reopened.cloudBatch?.gameIDs, ["abcdefgh", "ijklmnop"])
        XCTAssertEqual(reopened.cloudBatch?.submittedGameIDs, ["abcdefgh"])
    }

    func testSubscriptionConnectionNeverSendsBeforeConsentAndRejectsExpiredServerAccess() async throws {
        var requests = 0
        DeliveryProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.url?.path, "/chessme/v1/cloud/subscription")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
            return (200, Data(#"{"active":true,"expires_at":"2000-01-01T00:00:00Z"}"#.utf8))
        }
        defer { DeliveryProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeliveryProtocol.self]
        let cloud = CloudAnalysisService(baseURL: URL(string: "https://example.com/chessme"), session: URLSession(configuration: configuration))
        let body = CloudSubscriptionConnection(signed_transaction: "fixture-signed-transaction")
        do {
            try await cloud.connectSubscription(body, lichessToken: "fixture", consented: false)
            XCTFail("Consent must precede any token transmission")
        } catch CloudError.consentRequired { }
        XCTAssertEqual(requests, 0)
        do {
            try await cloud.connectSubscription(body, lichessToken: "fixture", consented: true)
            XCTFail("Expired access cannot enable cloud")
        } catch SubscriptionError.subscriptionRequired { }
        XCTAssertEqual(requests, 1)
    }

    func testCloudMoveEvidenceValidatesEveryPlayerDecisionBeforeOpeningCoaching() throws {
        let game = try record().importGame(username: "Learner", start: start, end: end).get()
        let afterOpening = try ChessPosition.initial.applying(ChessMove(uci: "e2e4")).applying(ChessMove(uci: "e7e5"))
        var response = try cloudResponse()
        let first = AnalysisResponse.Assessment(ply: 0, positionFEN: ChessPosition.initial.fen, playedMove: "e2e4", bestMove: "d2d4", centipawnLoss: 200, whiteScore: 200, completedDepth: 19)
        let second = AnalysisResponse.Assessment(ply: 2, positionFEN: afterOpening.fen, playedMove: "g1f3", bestMove: "b1c3", centipawnLoss: 300, whiteScore: -300, completedDepth: 21)
        response.move_assessments = [first, second]
        let analysis = try response.analysis(for: game)
        XCTAssertEqual(analysis.moveAssessments?.map(\.quality), [.mistake, .blunder])
        XCTAssertEqual(analysis.moveAssessments?.map(\.completedDepth), [19, 21])
        let report = OpeningCoach.report(games: [game], analyses: [analysis])
        XCTAssertEqual(report.reviewedGames, 1, "Verified cloud evidence must count toward opening coaching")
        response.move_assessments = [first, first]
        XCTAssertThrowsError(try response.analysis(for: game))
        response.move_assessments = [first, AnalysisResponse.Assessment(ply: 1, positionFEN: afterOpening.fen, playedMove: "g1f3", bestMove: "b1c3", centipawnLoss: 300, whiteScore: -300, completedDepth: 21)]
        XCTAssertThrowsError(try response.analysis(for: game), "Opponent positions are not player evidence")
        response.move_assessments = [first, AnalysisResponse.Assessment(ply: 2, positionFEN: ChessPosition.initial.fen, playedMove: "g1f3", bestMove: "b1c3", centipawnLoss: 300, whiteScore: -300, completedDepth: 21)]
        XCTAssertThrowsError(try response.analysis(for: game), "FEN must match the exact mainline ply")
    }

    private func record(status: String = "mate", variant: String = "standard", speed: String = "blitz",
                        createdAt: Int64? = nil) throws -> LichessGameRecord {
        let object: [String: Any] = [
            "id": "abc12345", "variant": variant, "speed": speed,
            "createdAt": createdAt ?? Int64(start.timeIntervalSince1970 * 1000) + 1000,
            "status": status, "moves": "e4 e5 Nf3 Nc6",
            "players": ["white": ["user": ["id": "learner", "name": "Learner"]],
                        "black": ["user": ["id": "opponent", "name": "Opponent"]]]
        ]
        return try JSONDecoder().decode(LichessGameRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func cloudResponse(continuation: [String] = ["d2d4", "d7d5"], playedMove: String = "e2e4",
                               totalPlies: Int = 2) throws -> AnalysisResponse {
        let finding: [String: Any] = [
            "id": UUID().uuidString, "gameID": "abc12345", "positionFEN": ChessPosition.initial.fen,
            "playedMove": playedMove, "bestMove": "d2d4", "acceptedMoves": ["d2d4"],
            "continuation": continuation, "centipawnLoss": 200.0, "theme": "Tactics",
            "explanation": "Find the better move.", "hint": "Look in the center.", "moveNumber": 1, "isPuzzle": true
        ]
        let object: [String: Any] = [
            "game_id": "abc12345", "engine": "Stockfish", "engine_version": "test",
            "analyzed_at": "2026-10-02T18:00:00.123Z", "source": "cloud", "findings": [finding],
            "analyzed_plies": 2, "total_plies": totalPlies, "nodes_used": 16_000, "quota_remaining": 19
        ]
        return try CloudAnalysisService.decoder().decode(AnalysisResponse.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

private actor ConcurrencyProbe {
    private var running = 0
    private(set) var maximum = 0
    func start() { running += 1; maximum = max(maximum, running) }
    func stop() { running -= 1 }
}

private final class DeliveryProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
