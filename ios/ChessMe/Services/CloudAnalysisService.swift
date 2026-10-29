import Foundation
import ChessMeCore

struct CloudEngineConfiguration: Codable, Equatable, Sendable {
    var engine_id = "stockfish"
    var depth = 20
    var hash_mb = 256
    var threads = 2
    static func saved() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "analysis.cloud.configuration"),
              let result = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return result
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "analysis.cloud.configuration") }
    }
}

struct CloudEngineCatalog: Decodable, Sendable {
    struct Engine: Decodable, Identifiable, Sendable {
        let id: String
        let name: String
        let available: Bool
        let network: String
    }
    let engines: [Engine]
    let max_depth: Int
    let max_hash_mb: Int
    let max_threads: Int
    let worker_memory_mb: Int
    let nodes_per_game: Int
    let timeout_seconds: Int
    var review_nodes_per_search: Int? = nil
    var review_uses_node_budget: Bool? = nil
}

struct CloudAccount: Sendable, Decodable {
    let accountToken: UUID
    let monthlyGameLimit: Int
    let quotaUsed: Int
    let quotaRemaining: Int
    let quotaResetsAt: Date
    let cachedResultsRetainedHours: Int
    enum CodingKeys: String, CodingKey {
        case accountToken = "account_token", monthlyGameLimit = "monthly_game_limit"
        case quotaUsed = "quota_used", quotaRemaining = "quota_remaining"
        case quotaResetsAt = "quota_resets_at", cachedResultsRetainedHours = "cached_results_retained_hours"
    }
}

struct CloudMonitoringStatus: Decodable, Sendable {
    let available: Bool
    let enabled: Bool
    let state: String
    let issue: String?
    let recovery_limited: Bool
    let device_count: Int
    let expires_at: Date?

    var message: String {
        switch issue {
        case "quota_exhausted", "quota_exceeded": return "Your monthly allowance is used. New games can be reviewed after it resets."
        case "subscription_required", "account_mismatch": return "Automatic reviews paused. Check your Pro access to resume."
        case "unauthorized", "monitor_reconnect_required": return "Reconnect Lichess to resume automatic reviews."
        case "notification_device_unavailable": return "Reconnect notifications on this iPhone to receive alerts."
        case .some: return "Automatic reviews are waiting to reconnect. You can still check the queue."
        case nil:
            if !available { return "Automatic reviews are not available on this server yet." }
            return enabled ? "New finished games are reviewed while ChessMe is closed." : "Automatic reviews are off."
        }
    }
}

struct CloudMonitoringRegistration: Encodable, Sendable {
    let signed_transaction: String
    let installation_id: UUID
    let device_token: String
    let apns_environment: String
}

struct CloudSubscriptionConnection: Encodable, Sendable {
    let signed_transaction: String
    var signed_app_transaction: String? = nil
    var legacy_token: UUID? = nil
}

struct CloudAnalysisResult: Sendable {
    let analysis: GameAnalysis
    let quotaRemaining: Int
    let nodesUsed: Int
    let engine: String
}

struct CloudAnalysisJob: Decodable, Sendable {
    let job_id: UUID
    let game_id: String
    let state: String
    let submitted_at: Date
    let deadline_at: Date
    let estimated_completion_at: Date?
    let queue_position: Int?
    let quota_remaining: Int
    let result: AnalysisResponse?
    let error_code: String?
    var result_token: String? = nil
    var downloaded_at: Date? = nil

    func validate() throws {
        guard ["queued", "running", "completed", "partial", "failed", "cancelled"].contains(state),
              quota_remaining >= 0, deadline_at >= submitted_at,
              queue_position == nil || queue_position! >= 0,
              result == nil || result!.game_id == game_id,
              result_token == nil || (result != nil && Self.isValidReceipt(result_token!)),
              !["completed", "partial"].contains(state) || result != nil else {
            throw CloudError.invalidResponse
        }
    }

    static func isValidReceipt(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { ("0"..."9").contains(String($0)) || ("a"..."f").contains(String($0)) }
    }
}

struct CloudReviewRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let gameID: String
    let accountID: String
    var state: String
    var estimatedCompletionAt: Date?
    let deadlineAt: Date
    var errorCode: String?
    var resultToken: String?
    var deliveryAcknowledged: Bool?
    var queuePosition: Int?
    var isPending: Bool { state == "queued" || state == "running" }
    var needsAcknowledgement: Bool { ["completed", "partial"].contains(state) && resultToken != nil && deliveryAcknowledged != true }
    var statusText: String {
        switch state {
        case "queued": "Cloud review queued"
        case "running": "Cloud review is analyzing"
        case "completed": "Cloud review saved"
        case "partial": "Partial cloud review saved"
        case "cancelled": "Cloud review cancelled"
        default: "Cloud review failed. You can try again."
        }
    }
    init(job: CloudAnalysisJob, accountID: String) {
        id = job.job_id; gameID = job.game_id; self.accountID = accountID.lowercased()
        queuePosition = job.queue_position
        state = job.state; estimatedCompletionAt = job.estimated_completion_at
        deadlineAt = job.deadline_at; errorCode = job.error_code
        resultToken = job.result_token; deliveryAcknowledged = job.downloaded_at != nil
    }
}

enum CloudError: LocalizedError {
    case unconfigured, consentRequired, invalidResponse, unfinishedGame, demonstrationGame
    case service(code: String, message: String, requestID: String?, status: Int)
    case paused(until: Date, message: String)
    var errorDescription: String? {
        switch self {
        case .unconfigured: return "Cloud analysis is not configured for this build. You can still create lessons on this iPhone."
        case .consentRequired: return "Allow cloud analysis first. The service receives your Lichess read token and fetches each selected completed game."
        case .invalidResponse: return "The cloud result could not be matched to this game. Keep the device review and try again later."
        case .unfinishedGame: return "Cloud analysis only supports completed games."
        case .demonstrationGame: return "Demonstration games are analyzed on this iPhone."
        case .service(_, let message, _, _): return message
        case .paused(_, let message): return message
        }
    }
    var isRetryable: Bool {
        if case .paused = self { return true }
        if case .service(let code, _, _, let status) = self {
            return ["worker_busy", "provider_unavailable", "verification_unavailable", "engine_unavailable", "analysis_in_progress", "analysis_timeout"].contains(code) || status == 429 || status >= 500
        }
        return false
    }
}

actor CloudRequestCooldown {
    private(set) var retryAt: Date?
    private var failures = 0
    private var message = "Cloud reviews will retry after a pause."

    func check(now: Date = Date()) throws {
        if let retryAt, retryAt > now { throw CloudError.paused(until: retryAt, message: message) }
    }
    func succeeded() { retryAt = nil; failures = 0 }
    func failed(_ error: Error, retryAfter: TimeInterval? = nil, now: Date = Date()) {
        guard (error as? CloudError)?.isRetryable == true ||
                ((error as? URLError).map { $0.code != .cancelled } == true) else { return }
        failures += 1
        let backoff = min(300, 30 * pow(2, Double(min(failures - 1, 4))))
        let retryAfter = retryAfter.flatMap { $0.isFinite ? $0 : nil } ?? 0
        let delay = max(backoff, min(3600, max(0, retryAfter)))
        retryAt = now.addingTimeInterval(delay)
        message = error.localizedDescription
    }
}

struct CloudPollingSchedule {
    var nextAttemptAt = Date.distantPast
    private var failures = 0
    private(set) var requiresReconnect = false

    func canRefresh(now: Date = Date()) -> Bool { !requiresReconnect && nextAttemptAt <= now }
    mutating func succeeded(pending: Bool, now: Date = Date()) {
        failures = 0
        requiresReconnect = false
        nextAttemptAt = now.addingTimeInterval(pending ? 5 : 60)
    }
    mutating func failed(_ error: Error, retryAt: Date? = nil, now: Date = Date()) {
        failures += 1
        if case CloudError.service(_, _, _, 401) = error { requiresReconnect = true }
        if case LichessError.notConnected = error { requiresReconnect = true }
        nextAttemptAt = max(retryAt ?? .distantPast, now.addingTimeInterval(min(300, 60 * pow(2, Double(min(failures - 1, 3))))))
    }
}

struct CloudAnalysisService: Sendable {
    private let baseURL: URL?
    private let session: URLSession
    private let cooldown: CloudRequestCooldown
    var nextRetryAt: Date? { get async { await cooldown.retryAt } }
    var isConfigured: Bool { baseURL != nil }
    var usesSandbox: Bool {
        isConfigured && Bundle.main.object(forInfoDictionaryKey: "ChessMeCloudEnvironment") as? String == "Sandbox"
    }

    init(baseURL: URL? = Self.configuredURL(), session: URLSession? = nil, cooldown: CloudRequestCooldown = CloudRequestCooldown()) {
        self.baseURL = baseURL.flatMap(Self.validatedURL)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        self.session = session ?? URLSession(configuration: configuration)
        self.cooldown = cooldown
    }

    func engines() async throws -> CloudEngineCatalog {
        let data = try await request(path: "v1/engines", method: "GET", token: nil)
        let catalog = try JSONDecoder().decode(CloudEngineCatalog.self, from: data)
        guard (1...32).contains(catalog.max_depth), (8...256).contains(catalog.max_hash_mb),
              (1...4).contains(catalog.max_threads), !catalog.engines.isEmpty,
              Set(catalog.engines.map(\.id)).count == catalog.engines.count else { throw CloudError.invalidResponse }
        return catalog
    }

    /// This request sends the Lichess credential to the configured worker, so consent precedes it too.
    func account(lichessToken: String, consented: Bool) async throws -> CloudAccount {
        guard consented else { throw CloudError.consentRequired }
        let data = try await request(path: "v1/cloud/account", method: "GET", token: lichessToken)
        let account = try Self.decoder().decode(CloudAccount.self, from: data)
        guard account.monthlyGameLimit >= 0, account.quotaUsed >= 0, account.quotaRemaining >= 0,
              account.quotaRemaining <= account.monthlyGameLimit else { throw CloudError.invalidResponse }
        return account
    }

    func connectSubscription(_ body: CloudSubscriptionConnection, lichessToken: String, consented: Bool) async throws {
        guard consented else { throw CloudError.consentRequired }
        let data = try await request(path: "v1/cloud/subscription", method: "POST", token: lichessToken,
                                     body: JSONEncoder().encode(body))
        struct Access: Decodable { let active: Bool; let expires_at: Date }
        let access = try Self.decoder().decode(Access.self, from: data)
        guard access.active, access.expires_at > Date() else { throw SubscriptionError.subscriptionRequired }
    }

    func analyze(game: ChessGame, credential: CloudSubscriptionCredential, lichessToken: String,
                 consented: Bool, idempotencyKey: UUID = UUID(), configuration: CloudEngineConfiguration? = nil) async throws -> CloudAnalysisResult {
        guard consented else { throw CloudError.consentRequired }
        guard !game.id.hasPrefix("demo-") else { throw CloudError.demonstrationGame }
        guard game.isFinished else { throw CloudError.unfinishedGame }
        let options = try await supportedConfiguration(configuration)
        let body = try JSONEncoder().encode(AnalysisRequest(game_id: game.id,
                                                         signed_transaction: credential.signedTransaction,
                                                         app_account_token: credential.appAccountToken,
                                                         idempotency_key: idempotencyKey, options: options))
        let data = try await request(path: "v1/analysis", method: "POST", token: lichessToken, body: body)
        do {
            let response = try Self.decoder().decode(AnalysisResponse.self, from: data)
            let analysis = try response.analysis(for: game)
            return CloudAnalysisResult(analysis: analysis, quotaRemaining: response.quota_remaining,
                                       nodesUsed: response.nodes_used, engine: response.engine)
        } catch is CancellationError { throw CancellationError() }
        catch { throw CloudError.invalidResponse }
    }

    func deleteAccount(lichessToken: String) async throws {
        _ = try await request(path: "v1/cloud/account", method: "DELETE", token: lichessToken)
    }

    func monitoring(lichessToken: String) async throws -> CloudMonitoringStatus {
        try Self.decoder().decode(CloudMonitoringStatus.self, from: await request(path: "v1/cloud/monitoring", method: "GET", token: lichessToken))
    }

    func enableMonitoring(_ body: CloudMonitoringRegistration, lichessToken: String) async throws -> CloudMonitoringStatus {
        try Self.decoder().decode(CloudMonitoringStatus.self, from: await request(path: "v1/cloud/monitoring", method: "POST", token: lichessToken, body: JSONEncoder().encode(body)))
    }

    func disableMonitoring(lichessToken: String) async throws -> CloudMonitoringStatus {
        try Self.decoder().decode(CloudMonitoringStatus.self, from: await request(path: "v1/cloud/monitoring", method: "DELETE", token: lichessToken))
    }

    func registerPushDevice(token: String, installation: UUID, environment: String, lichessToken: String) async throws -> CloudMonitoringStatus {
        struct Body: Encodable { let installation_id: UUID; let device_token: String; let apns_environment: String }
        let body = Body(installation_id: installation, device_token: token, apns_environment: environment)
        return try Self.decoder().decode(CloudMonitoringStatus.self, from: await request(path: "v1/cloud/monitoring/device", method: "POST", token: lichessToken, body: JSONEncoder().encode(body)))
    }

    func enqueue(game: ChessGame, credential: CloudSubscriptionCredential, lichessToken: String,
                 consented: Bool, idempotencyKey: UUID = UUID(), configuration: CloudEngineConfiguration? = nil) async throws -> CloudAnalysisJob {
        guard consented else { throw CloudError.consentRequired }
        guard !game.id.hasPrefix("demo-") else { throw CloudError.demonstrationGame }
        guard game.isFinished else { throw CloudError.unfinishedGame }
        let options = try await supportedConfiguration(configuration)
        let body = try JSONEncoder().encode(AnalysisRequest(game_id: game.id,
            signed_transaction: credential.signedTransaction, app_account_token: credential.appAccountToken,
            idempotency_key: idempotencyKey, options: options))
        let data = try await request(path: "v1/analysis/jobs", method: "POST", token: lichessToken, body: body)
        let job = try Self.decoder().decode(CloudAnalysisJob.self, from: data)
        try job.validate()
        guard job.game_id == game.id else { throw CloudError.invalidResponse }
        return job
    }

    func jobs(lichessToken: String) async throws -> [CloudAnalysisJob] {
        let data = try await request(path: "v1/analysis/jobs", method: "GET", token: lichessToken)
        let jobs = try Self.decoder().decode([CloudAnalysisJob].self, from: data)
        guard jobs.count <= 100, Set(jobs.map(\.job_id)).count == jobs.count else { throw CloudError.invalidResponse }
        try jobs.forEach { try $0.validate() }
        return jobs
    }

    func cancel(jobID: UUID, lichessToken: String) async throws -> CloudAnalysisJob {
        let data = try await request(path: "v1/analysis/jobs/\(jobID.uuidString)", method: "DELETE", token: lichessToken)
        let job = try Self.decoder().decode(CloudAnalysisJob.self, from: data)
        try job.validate()
        guard job.job_id == jobID else { throw CloudError.invalidResponse }
        return job
    }

    @MainActor
    func acknowledgeSavedReview(_ review: CloudReviewRecord, lichessToken: String, save: () throws -> Void) async throws {
        guard review.needsAcknowledgement, let receipt = review.resultToken,
              CloudAnalysisJob.isValidReceipt(receipt) else { throw CloudError.invalidResponse }
        try Task.checkCancellation()
        // Do not release server retention before the atomic local write succeeds.
        try save()
        try Task.checkCancellation()
        struct Body: Encodable { let result_token: String }
        struct Reply: Decodable { let job_id: UUID; let acknowledged: Bool }
        let data: Data
        do {
            data = try await request(path: "v1/analysis/jobs/\(review.id.uuidString)/acknowledge", method: "POST", token: lichessToken,
                                     body: JSONEncoder().encode(Body(result_token: receipt)))
        } catch CloudError.service(let code, _, _, let status) where status == 404 && code == "job_unavailable" {
            // An earlier successful receipt may have lost its response, then
            // expired. The locally saved review remains valid; nothing is left
            // on the server to acknowledge. Explicit account deletion also ends it.
            return
        }
        let reply = try Self.decoder().decode(Reply.self, from: data)
        guard reply.job_id == review.id, reply.acknowledged else { throw CloudError.invalidResponse }
    }

    private func supportedConfiguration(_ requested: CloudEngineConfiguration?) async throws -> CloudEngineConfiguration? {
        guard var configuration = requested else { return nil }
        // Limits can change after settings were saved or before Settings is opened.
        let catalog = try await engines()
        configuration.depth = min(catalog.max_depth, max(1, configuration.depth))
        configuration.hash_mb = min(catalog.max_hash_mb, max(8, configuration.hash_mb))
        configuration.threads = min(catalog.max_threads, max(1, configuration.threads))
        return configuration
    }

    private func request(path: String, method: String, token: String?, body: Data? = nil) async throws -> Data {
        guard let baseURL else { throw CloudError.unconfigured }
        try Task.checkCancellation()
        try await cooldown.check()
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 180
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("chess-me/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do { (bytes, response) = try await session.bytes(for: request) }
        catch { await cooldown.failed(error); throw error }
        defer { bytes.task.cancel() }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 2_000_000 else { throw CloudError.invalidResponse }
            data.append(byte)
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw CloudError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error: CloudError
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                error = .service(code: envelope.error.code, message: envelope.error.message,
                                 requestID: envelope.error.request_id, status: http.statusCode)
            } else {
                error = .service(code: "http_error", message: "Cloud analysis could not complete the request. Try again later.",
                                 requestID: http.value(forHTTPHeaderField: "X-Request-ID"), status: http.statusCode)
            }
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            await cooldown.failed(error, retryAfter: retry)
            throw error
        }
        await cooldown.succeeded()
        return data
    }

    static func configuredURL() -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "ChessMeCloudBaseURL") as? String,
              !value.isEmpty, let url = URL(string: value) else { return nil }
        return validatedURL(url)
    }

    static func validatedURL(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid cloud date")
            }
            return date
        }
        return decoder
    }

    private struct AnalysisRequest: Encodable {
        let game_id: String
        let signed_transaction: String
        let app_account_token: UUID
        let idempotency_key: UUID
        let options: CloudEngineConfiguration?
    }
    private struct ErrorEnvelope: Decodable {
        struct Detail: Decodable { let code: String; let message: String; let request_id: String? }
        let error: Detail
    }
}

struct AnalysisResponse: Decodable, Sendable {
    struct Finding: Decodable, Sendable {
        let id: String
        let gameID: String
        let positionFEN: String
        let playedMove: String
        let bestMove: String
        let acceptedMoves: [String]
        let continuation: [String]
        let centipawnLoss: Double
        let theme: String
        let explanation: String
        let hint: String
        let moveNumber: Int
        let isPuzzle: Bool
    }
    struct Assessment: Decodable, Sendable {
        let ply: Int
        let positionFEN: String
        let playedMove: String
        let bestMove: String
        let centipawnLoss: Int
        let whiteScore: Int
        var bestWhiteScore: Int? = nil
        let completedDepth: Int
    }
    var move_assessments: [Assessment]? = nil
    let game_id: String
    let engine: String
    let engine_version: String
    var configuration_id: String? = nil
    let analyzed_at: Date
    let source: String
    let findings: [Finding]
    let analyzed_plies: Int
    let total_plies: Int
    let nodes_used: Int
    let quota_remaining: Int

    func analysis(for game: ChessGame) throws -> GameAnalysis {
        guard game_id == game.id, source == "cloud", analyzed_plies >= 0, total_plies > 0,
              analyzed_plies <= total_plies, nodes_used >= 0, quota_remaining >= 0 else {
            throw CloudError.invalidResponse
        }
        // Confirm that remote lesson positions belong to the exact imported game before storing them.
        let mainline = try game.mainline()
        var position = try game.initialFEN.map(ChessPosition.init(fen:)) ?? .initial
        var ownPositions: [String: String] = [:]
        var playerPositions = 0
        var positionsByPly: [Int: (ChessPosition, String)] = [:]
        for (ply, token) in mainline.moves.enumerated() {
            let move = try position.move(san: token)
            if position.sideToMove == game.playerSide {
                ownPositions[position.fen] = move.uci
                positionsByPly[ply] = (position, move.uci)
                playerPositions += 1
            }
            position = try position.applying(move)
        }
        guard total_plies == playerPositions else { throw CloudError.invalidResponse }
        let mapped = try findings.map { finding -> MoveFinding in
            guard finding.gameID == game.id, ownPositions[finding.positionFEN] == finding.playedMove,
                  finding.centipawnLoss.isFinite, finding.centipawnLoss >= 0,
                  !finding.acceptedMoves.isEmpty, finding.acceptedMoves.contains(finding.bestMove),
                  finding.continuation.first == finding.bestMove else { throw CloudError.invalidResponse }
            let board = try ChessPosition(fen: finding.positionFEN)
            guard board.fullmoveNumber == finding.moveNumber else { throw CloudError.invalidResponse }
            let legal = Set(board.legalMoves().map(\.uci))
            guard finding.acceptedMoves.allSatisfy(legal.contains), legal.contains(finding.bestMove) else {
                throw CloudError.invalidResponse
            }
            var continuation = board
            for uci in finding.continuation { continuation = try continuation.applying(ChessMove(uci: uci)) }
            return MoveFinding(id: finding.id, gameID: finding.gameID, gameLabel: game.label,
                               positionFEN: finding.positionFEN, playedMove: finding.playedMove,
                               bestMove: finding.bestMove, acceptedMoves: finding.acceptedMoves,
                               continuation: finding.continuation, centipawnLoss: finding.centipawnLoss,
                               theme: finding.theme, explanation: finding.explanation, hint: finding.hint,
                               moveNumber: finding.moveNumber, source: "cloud", isPuzzle: finding.isPuzzle)
        }
        var assessments: [MoveAssessment]? = nil
        if let values = move_assessments {
            guard values.count == analyzed_plies, Set(values.map(\.ply)).count == values.count else { throw CloudError.invalidResponse }
            // Coverage is a prefix of player decisions, never arbitrary positions.
            guard values.map(\.ply) == Array(positionsByPly.keys.sorted().prefix(analyzed_plies)) else { throw CloudError.invalidResponse }
            assessments = try values.map { value in
                guard let (board, played) = positionsByPly[value.ply], board.fen == value.positionFEN,
                      played == value.playedMove, (0...20000).contains(value.centipawnLoss),
                      (-10000...10000).contains(value.whiteScore), value.bestWhiteScore.map({ (-10000...10000).contains($0) }) ?? true, (0...256).contains(value.completedDepth),
                      board.legalMoves().contains(where: { $0.uci == value.bestMove }) else { throw CloudError.invalidResponse }
                return MoveAssessment(ply: value.ply, positionFEN: value.positionFEN, playedMove: played,
                    bestMove: value.bestMove, quality: value.completedDepth < 2 ? .unclassified : .estimated(loss: value.centipawnLoss, isBest: played == value.bestMove),
                    centipawnLoss: value.centipawnLoss, whiteScore: value.whiteScore,
                    completedDepth: value.completedDepth, isProvisional: value.completedDepth < 2, bestWhiteScore: value.bestWhiteScore)
            }
        }
        return ReviewMovePolicy.normalizing(GameAnalysis(gameID: game_id, findings: mapped, analyzedPlies: analyzed_plies,
                            totalPlies: total_plies, source: "cloud", completedAt: analyzed_at,
                            engineVersion: engine_version, configurationID: configuration_id, moveAssessments: assessments))
    }
}
