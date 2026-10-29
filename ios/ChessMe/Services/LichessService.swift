import Foundation
import ChessMeCore

struct LichessAccount: Codable, Equatable, Sendable {
    let id: String
    let username: String
    var perfs: [String: Performance]? = nil

    struct Performance: Codable, Equatable, Sendable {
        let rating: Int?
        let games: Int?
        var prov: Bool? = nil
    }

    var suggestedPuzzleRating: Int? {
        func rating(_ perf: Performance?) -> Int? {
            guard let perf, (perf.games ?? 0) > 0, let rating = perf.rating, (400...4000).contains(rating) else { return nil }
            return min(3000, max(400, rating))
        }
        if let puzzle = rating(perfs?["puzzle"]) { return puzzle }
        // Prefer established slower time controls over a provisional or bullet estimate.
        let controls = ["rapid", "classical", "blitz", "bullet"]
        for provisional in [false, true] {
            for control in controls where (perfs?[control]?.prov ?? false) == provisional {
                if let value = rating(perfs?[control]) { return value }
            }
        }
        return nil
    }
}

struct LichessImportResult: Sendable {
    let games: [ChessGame]
    let skippedGames: Int
    let skippedReasons: [String: Int]
    let windowStart: Date
    let windowEnd: Date
    let isComplete: Bool
    let reachedLimit: Bool
}

enum LichessError: LocalizedError {
    case invalidUsername, consentRequired, invalidResponse, invalidCallback, denied, notConnected
    case busy, malformedExport, http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidUsername: return "Enter a valid Lichess username."
        case .consentRequired: return "Allow chess-me to import your completed public games first."
        case .invalidResponse: return "Lichess returned an unexpected response. Try again later."
        case .invalidCallback: return "The Lichess connection could not be verified. Start the connection again."
        case .denied: return "Lichess access was not granted."
        case .notConnected: return "Connect your Lichess account again."
        case .busy: return "Another Lichess connection is already in progress."
        case .malformedExport: return "A game export was too large to import safely."
        case .http(401), .http(403): return "Lichess access has expired or was revoked. Connect again."
        case .http(404): return "This Lichess account could not be found. Check the username."
        case .http(429): return "Lichess is limiting requests. Wait a few minutes before importing again."
        case .http(let code): return "Lichess could not complete the request (HTTP \(code)). Try again later."
        }
    }

    var isRetryable: Bool {
        switch self { case .http(429), .http(500...599), .invalidResponse: return true; default: return false }
    }
}

/// A single gate is shared by authentication and export requests, including the lifetime of a stream.
actor LichessRequestGate {
    static let shared = LichessRequestGate()
    private var isBusy = false
    private var waiting: [(UUID, CheckedContinuation<Void, Error>)] = []

    func perform<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if !isBusy { isBusy = true; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiting.append((id, continuation)) }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.0 == id }) else { return }
        let (_, continuation) = waiting.remove(at: index)
        continuation.resume(throwing: CancellationError())
    }

    private func release() {
        if waiting.isEmpty { isBusy = false }
        else { waiting.removeFirst().1.resume() }
    }
}

struct LichessHTTPClient: Sendable {
    static let shared = LichessHTTPClient(session: URLSession(configuration: .ephemeral))
    let session: URLSession
    let gate: LichessRequestGate
    let delay: @Sendable (TimeInterval) async throws -> Void

    init(session: URLSession = .shared, gate: LichessRequestGate = .shared,
         delay: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
             try await Task.sleep(for: .seconds(seconds))
         }) {
        self.session = session
        self.gate = gate
        self.delay = delay
    }

    func data(for request: URLRequest) async throws -> Data {
        try await gate.perform {
            for attempt in 0..<3 {
                try Task.checkCancellation()
                let (bytes, response) = try await session.bytes(for: request)
                defer { bytes.task.cancel() }
                guard let http = response as? HTTPURLResponse else { throw LichessError.invalidResponse }
                if http.statusCode == 429, attempt < 2 {
                    bytes.task.cancel()
                    try await delay(Self.retryDelay(http, attempt: attempt))
                    continue
                }
                guard (200..<300).contains(http.statusCode) else { throw LichessError.http(http.statusCode) }
                var data = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    guard data.count < 128_000 else { throw LichessError.invalidResponse }
                    data.append(byte)
                }
                return data
            }
            throw LichessError.http(429)
        }
    }

    func stream<T: Sendable>(for request: URLRequest,
                           consume: @escaping @Sendable (URLSession.AsyncBytes) async throws -> T) async throws -> T {
        try await gate.perform {
            for attempt in 0..<3 {
                try Task.checkCancellation()
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    bytes.task.cancel()
                    throw LichessError.invalidResponse
                }
                if http.statusCode == 429, attempt < 2 {
                    bytes.task.cancel()
                    try await delay(Self.retryDelay(http, attempt: attempt))
                    continue
                }
                guard (200..<300).contains(http.statusCode) else {
                    bytes.task.cancel()
                    throw LichessError.http(http.statusCode)
                }
                defer { bytes.task.cancel() }
                return try await consume(bytes)
            }
            throw LichessError.http(429)
        }
    }

    static func retryDelay(_ response: HTTPURLResponse, attempt: Int) -> TimeInterval {
        let fallback = 60.0 * Double(attempt + 1)
        guard let header = response.value(forHTTPHeaderField: "Retry-After") else { return fallback }
        if let seconds = TimeInterval(header), seconds.isFinite { return max(fallback, min(seconds, 3600)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        guard let date = formatter.date(from: header) else { return fallback }
        return max(fallback, min(date.timeIntervalSinceNow, 3600))
    }

    static func request(_ url: URL, token: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("chess-me/0.1 (iOS; completed-game learning)", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }
}

struct LichessService: Sendable {
    let client: LichessHTTPClient
    init(client: LichessHTTPClient = .shared) { self.client = client }

    /// Recover just the game belonging to an already-charged downloadable review.
    /// This does not mark any archive window complete or require a new purchase.
    func reviewedGame(gameID: String, username: String, accessToken: String? = nil) async throws -> ChessGame {
        guard gameID.count == 8, gameID.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }),
              Self.isValidUsername(username) else { throw LichessError.invalidResponse }
        var components = URLComponents(string: "https://lichess.org/game/export/\(gameID)")!
        components.queryItems = [.init(name: "moves", value: "true"), .init(name: "pgnInJson", value: "true"),
                                 .init(name: "clocks", value: "true"), .init(name: "evals", value: "false")]
        // Lichess requires authentication for exports of older, lower-rated
        // games. A retained paid review must still download after that cutoff.
        var request = LichessHTTPClient.request(components.url!, token: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await client.data(for: request)
        let record = try JSONDecoder().decode(LichessGameRecord.self, from: data)
        guard record.id == gameID else { throw LichessError.invalidResponse }
        return try record.importGame(username: username, start: .distantPast, end: Date()).get()
    }

    func profile(username: String) async throws -> LichessAccount {
        guard Self.isValidUsername(username) else { throw LichessError.invalidUsername }
        var request = LichessHTTPClient.request(URL(string: "https://lichess.org/api/user/\(username)")!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let account = try JSONDecoder().decode(LichessAccount.self, from: await client.data(for: request))
        guard !account.id.isEmpty, account.username.caseInsensitiveCompare(username) == .orderedSame else { throw LichessError.invalidResponse }
        return account
    }

    /// Lichess filters on creation time. Every window therefore means games started in this period.
    func importGames(username: String, window: ReviewWindow, accessToken: String? = nil,
                     consented: Bool, now: Date = Date(), maxGames: Int = 20_000, speedFilter: GameSpeedFilter = .all,
                     onGame: (@MainActor @Sendable (ChessGame) -> Void)? = nil,
                     onProgress: @escaping @MainActor @Sendable (Int) -> Void = { _ in }) async throws -> LichessImportResult {
        guard consented else { throw LichessError.consentRequired }
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidUsername(username) else { throw LichessError.invalidUsername }
        let start = now.addingTimeInterval(-Double(Self.days(for: window)) * 86_400)
        let limit = max(1, min(maxGames, 100_000))
        var components = URLComponents(string: "https://lichess.org/api/games/user/\(username)")!
        components.queryItems = [
            .init(name: "since", value: String(Int64((start.timeIntervalSince1970 * 1000).rounded(.down)))),
            .init(name: "until", value: String(Int64((now.timeIntervalSince1970 * 1000).rounded(.down)))),
            .init(name: "max", value: String(limit + 1)),
            .init(name: "perfType", value: speedFilter.lichessPerfTypes),
            .init(name: "ongoing", value: "false"), .init(name: "finished", value: "true"),
            .init(name: "moves", value: "true"), .init(name: "pgnInJson", value: "true"),
            .init(name: "clocks", value: "true"), .init(name: "evals", value: "false"),
            .init(name: "sort", value: "dateDesc")
        ]
        var request = LichessHTTPClient.request(components.url!, token: accessToken)
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        return try await client.stream(for: request) { bytes in
            var games: [ChessGame] = []
            var seen = Set<String>()
            var skipped: [String: Int] = [:]
            var records = 0
            var reachedLimit = false
            func processLine(_ data: Data) async throws -> Bool {
                try Task.checkCancellation()
                guard !data.allSatisfy({ [UInt8(9), 13, 32].contains($0) }) else { return true }
                records += 1
                if records > limit { reachedLimit = true; return false }
                do {
                    let record = try JSONDecoder().decode(LichessGameRecord.self, from: data)
                    switch record.importGame(username: username, start: start, end: now) {
                    case .success(let game):
                        if !speedFilter.includes(game) { skipped["outside selected time control", default: 0] += 1 }
                        else if seen.insert(game.id).inserted {
                            games.append(game)
                            await onGame?(game)
                        }
                        else { skipped["duplicate", default: 0] += 1 }
                    case .failure(let reason): skipped[reason.rawValue, default: 0] += 1
                    }
                } catch { skipped["invalid export", default: 0] += 1 }
                await onProgress(games.count)
                return true
            }
            // Enforce the byte bound while receiving each line, before allocating a whole export record.
            var line = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                if byte == 10 {
                    let completeLine = line
                    line = Data()
                    if try await !processLine(completeLine) { break }
                } else {
                    guard line.count < 512_000 else { throw LichessError.malformedExport }
                    line.append(byte)
                }
            }
            if !reachedLimit, !line.isEmpty {
                _ = try await processLine(line)
            }
            return LichessImportResult(games: games, skippedGames: skipped.values.reduce(0, +),
                                       skippedReasons: skipped, windowStart: start, windowEnd: now,
                                       isComplete: !reachedLimit && skipped["invalid export"] == nil,
                                       reachedLimit: reachedLimit)
        }
    }

    static func isValidUsername(_ username: String) -> Bool {
        username.range(of: "^[A-Za-z0-9_-]{2,30}$", options: .regularExpression) != nil
    }

    static func days(for window: ReviewWindow) -> Int {
        switch window { case .day: return 1; case .week: return 7; case .month: return 30; case .year: return 365 }
    }
}

enum ImportSkipReason: String, Error {
    case unfinished = "unfinished game"
    case unsupported = "unsupported variant or correspondence"
    case outsideWindow = "outside selected period"
    case unknownPlayer = "player identity missing"
    case noMoves = "no moves"
}

struct LichessGameRecord: Decodable {
    struct Player: Decodable {
        struct User: Decodable { let id: String; let name: String }
        let user: User?
        let name: String?
        var displayName: String { user?.name ?? name ?? "Anonymous" }
    }
    struct Players: Decodable { let white: Player; let black: Player }
    struct Clock: Decodable { let initial: Int; let increment: Int }
    let id: String
    let variant: String
    let speed: String
    let createdAt: Int64
    let status: String
    let winner: Side?
    let players: Players
    let moves: String?
    let pgn: String?
    let initialFen: String?
    let clock: Clock?
    let clocks: [Int?]?

    func importGame(username: String, start: Date, end: Date) -> Result<ChessGame, ImportSkipReason> {
        guard Self.finishedStatuses.contains(status) else { return .failure(.unfinished) }
        guard variant == "standard", speed != "correspondence" else { return .failure(.unsupported) }
        let date = Date(timeIntervalSince1970: Double(createdAt) / 1000)
        guard date >= start, date <= end else { return .failure(.outsideWindow) }
        let identity = username.lowercased()
        let side: Side
        if players.white.user?.id.lowercased() == identity { side = .white }
        else if players.black.user?.id.lowercased() == identity { side = .black }
        else { return .failure(.unknownPlayer) }
        let san = (moves ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        guard !san.isEmpty else { return .failure(.noMoves) }
        let clockData = clocks.flatMap { readings in
            readings.contains(where: { $0 != nil }) ? GameClockData(initialSeconds: clock?.initial, incrementSeconds: clock?.increment,
                remainingCentiseconds: readings) : nil
        }
        return .success(ChessGame(id: id, username: username, white: players.white.displayName,
                                  black: players.black.displayName, playedAt: date, playerSide: side,
                                  moves: san.joined(separator: " "), pgn: pgn, initialFEN: initialFen, status: status,
                                  clockData: clockData, clockDataFetchedAt: Date(),
                                  result: winner.map { $0 == .white ? .whiteWin : .blackWin } ?? (["draw", "stalemate"].contains(status) ? .draw : nil),
                                  speed: speed == "ultraBullet" ? .bullet : GameSpeed(rawValue: speed), timestampIsExact: true))
    }

    static let finishedStatuses: Set<String> = ["mate", "resign", "stalemate", "timeout", "draw", "outoftime", "cheat", "noStart", "variantEnd"]
}
