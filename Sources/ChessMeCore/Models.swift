import Foundation

public enum ReviewWindow: String, Codable, CaseIterable, Identifiable, Sendable {
    case day, week, month, year
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .day: return "Last 24 hours"
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .year: return "Last 365 days"
        }
    }
    public var shortTitle: String {
        switch self {
        case .day: return "24 hours"
        case .week: return "7 days"
        case .month: return "30 days"
        case .year: return "365 days"
        }
    }
    public var duration: TimeInterval {
        switch self {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .year: return 365 * 86_400
        }
    }
    public var isFree: Bool { self == .day }
    public func since(now: Date = Date()) -> Date { now.addingTimeInterval(-duration) }
    public func contains(_ date: Date, now: Date = Date()) -> Bool { date >= since(now: now) && date <= now }
}

public enum GameResult: String, Codable, Sendable {
    case whiteWin = "1-0", blackWin = "0-1", draw = "1/2-1/2"
    public func outcome(for side: Side) -> PlayerGameOutcome {
        switch self {
        case .draw: return .draw
        case .whiteWin: return side == .white ? .won : .lost
        case .blackWin: return side == .black ? .won : .lost
        }
    }
}

public enum PlayerGameOutcome: String, Sendable { case won, lost, draw }

public struct ChessGame: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let username: String
    public let white: String
    public let black: String
    public let playedAt: Date
    public let playerSide: Side
    /// Mainline SAN from the provider. UCI mainlines are also accepted by the replay engine.
    public let moves: String
    public let pgn: String?
    public let initialFEN: String?
    public let status: String
    public let clockData: GameClockData?
    /// A successful export can legitimately have no clocks. Do not keep fetching it.
    public let clockDataFetchedAt: Date?
    public let result: GameResult?

    public init(id: String, username: String, white: String, black: String, playedAt: Date,
                playerSide: Side, moves: String, pgn: String? = nil, initialFEN: String? = nil,
                status: String = "mate", clockData: GameClockData? = nil, clockDataFetchedAt: Date? = nil, result: GameResult? = nil) {
        self.id = id; self.username = username; self.white = white; self.black = black
        self.playedAt = playedAt; self.playerSide = playerSide; self.moves = moves
        self.pgn = pgn; self.initialFEN = initialFEN; self.status = status
        self.clockData = clockData; self.clockDataFetchedAt = clockDataFetchedAt
        self.result = result
    }

    public var label: String { "\(white) vs \(black)" }
    public var opponent: String { playerSide == .white ? black : white }
    public var reviewLabel: String { "You vs \(opponent)" }
    public var finishedResult: GameResult? {
        guard isFinished else { return nil }
        if let result { return result }
        if let pgn, let document = try? PGNDocument(pgn), let value = document.result,
           let result = GameResult(rawValue: value) { return result }
        if ["draw", "stalemate"].contains(status) { return .draw }
        if status == "mate", let replay = try? GameReplay(game: self), let outcome = replay.positions.last?.outcome(),
           case .checkmate(let winner) = outcome {
            return winner == .white ? .whiteWin : .blackWin
        }
        return nil
    }
    public var url: URL? { id.hasPrefix("demo-") || id.hasPrefix("pgn-") ? nil : URL(string: "https://lichess.org/\(id)") }
    public var isFinished: Bool { !["created", "started", "aborted"].contains(status) }
    public func mainline() throws -> PGNDocument { try PGNDocument(moves.isEmpty ? (pgn ?? "") : moves) }
    public func hasSameMainline(as other: ChessGame) -> Bool {
        moves == other.moves && initialFEN == other.initialFEN && (moves.isEmpty ? pgn == other.pgn : true)
    }
    public func withClockData(_ data: GameClockData?, fetchedAt: Date) -> ChessGame {
        ChessGame(id: id, username: username, white: white, black: black, playedAt: playedAt, playerSide: playerSide,
                  moves: moves, pgn: pgn, initialFEN: initialFEN, status: status, clockData: data, clockDataFetchedAt: fetchedAt, result: result)
    }
    public func withResult(_ value: GameResult?) -> ChessGame {
        ChessGame(id: id, username: username, white: white, black: black, playedAt: playedAt, playerSide: playerSide,
                  moves: moves, pgn: pgn, initialFEN: initialFEN, status: status, clockData: clockData,
                  clockDataFetchedAt: clockDataFetchedAt, result: value)
    }
}

public struct MoveFinding: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let gameID: String
    public let gameLabel: String
    public let positionFEN: String
    public let playedMove: String
    public let bestMove: String
    public let acceptedMoves: [String]
    /// UCI line including bestMove as its first ply.
    public let continuation: [String]
    public let centipawnLoss: Double
    public let theme: String
    public let explanation: String
    public let hint: String
    public let moveNumber: Int
    public let source: String
    /// Ambiguous strategic findings are review cards instead of graded puzzles.
    public let isPuzzle: Bool

    public init(id: String, gameID: String, gameLabel: String, positionFEN: String,
                playedMove: String, bestMove: String, acceptedMoves: [String], continuation: [String],
                centipawnLoss: Double, theme: String, explanation: String, hint: String,
                moveNumber: Int, source: String = "device", isPuzzle: Bool = true) {
        self.id = id; self.gameID = gameID; self.gameLabel = gameLabel; self.positionFEN = positionFEN
        self.playedMove = playedMove; self.bestMove = bestMove; self.acceptedMoves = acceptedMoves
        self.continuation = continuation; self.centipawnLoss = centipawnLoss; self.theme = theme
        self.explanation = explanation; self.hint = hint; self.moveNumber = moveNumber
        self.source = source; self.isPuzzle = isPuzzle
    }
}

public struct GameAnalysis: Codable, Identifiable, Equatable, Sendable {
    public var id: String { gameID }
    public let gameID: String
    public let findings: [MoveFinding]
    /// Count of player's positions examined. Other-side moves do not count as analyzed positions.
    public let analyzedPlies: Int
    public let totalPlies: Int
    public let source: String
    public let completedAt: Date
    public let engineVersion: String
    public let configurationID: String?
    public let moveAssessments: [MoveAssessment]?

    public init(gameID: String, findings: [MoveFinding], analyzedPlies: Int, totalPlies: Int,
                source: String = "device", completedAt: Date = Date(), engineVersion: String = LocalAnalyzer.engineVersion,
                configurationID: String? = nil, moveAssessments: [MoveAssessment]? = nil) {
        self.gameID = gameID; self.findings = findings; self.analyzedPlies = analyzedPlies
        self.totalPlies = totalPlies; self.source = source; self.completedAt = completedAt
        self.engineVersion = engineVersion
        self.configurationID = configurationID; self.moveAssessments = moveAssessments
    }
    public var isComplete: Bool { analyzedPlies >= totalPlies }
}

public enum AttemptResult: String, Codable, Sendable {
    case correct, incorrect, revealed
}

public struct LessonAttempt: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let findingID: String
    public let attemptedAt: Date
    public let result: AttemptResult
    public let streak: Int
    public let nextReviewAt: Date

    public init(id: String = UUID().uuidString, findingID: String, result: AttemptResult,
                attemptedAt: Date = Date(), previousStreak: Int = 0) {
        self.id = id; self.findingID = findingID; self.attemptedAt = attemptedAt; self.result = result
        let prior = max(0, previousStreak)
        self.streak = result == .correct ? prior + 1 : 0
        let days: Double
        if result != .correct { days = 1 }
        else { days = [1.0, 3, 7, 14, 30, 60][min(prior, 5)] }
        self.nextReviewAt = attemptedAt.addingTimeInterval(days * 86_400)
    }
    public func isDue(now: Date = Date()) -> Bool { nextReviewAt <= now }
}

public enum LearningSession {
    /// One theme per session, with earlier mistakes and due retries ahead of new exercises.
    public static func findings(_ findings: [MoveFinding], attempts: [LessonAttempt],
                                limit: Int = 6, now: Date = Date()) -> [MoveFinding] {
        guard limit > 0 else { return [] }
        let latest = Dictionary(grouping: attempts, by: \.findingID).compactMapValues { $0.max { $0.attemptedAt < $1.attemptedAt } }
        let available = findings.filter { latest[$0.id]?.isDue(now: now) ?? true }
        let groups = Dictionary(grouping: available, by: \.theme)
        let theme = groups.keys.sorted {
            let lhs = groups[$0]!, rhs = groups[$1]!
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return $0 < $1
        }.first
        guard let theme else { return [] }
        return Array(groups[theme]!.sorted {
            let lhsDue = latest[$0.id] != nil, rhsDue = latest[$1.id] != nil
            if lhsDue != rhsDue { return lhsDue }
            if $0.centipawnLoss != $1.centipawnLoss { return $0.centipawnLoss > $1.centipawnLoss }
            return $0.id < $1.id
        }.prefix(limit))
    }
}

public enum DemoContent {
    /// Curated complete miniatures, replayed and evaluated by the same engine as imported games.
    public static func games(now: Date = Date()) -> [ChessGame] {
        [
            ChessGame(id: "demo-missed-mate", username: "You", white: "You", black: "Practice partner",
                      playedAt: now.addingTimeInterval(-3_600), playerSide: .white,
                      moves: "1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qe2 Nd4 5. Qd1 d6 6. d3 Be7",
                      status: "resign", clockData: GameClockData(initialSeconds: 300, incrementSeconds: 3,
                          remainingCentiseconds: [30_000, 30_000, 29_900, 29_750, 29_100, 29_500, 28_700, 28_900, 27_800, 27_500, 27_000, 26_800])),
            ChessGame(id: "demo-queen-loss", username: "You", white: "Practice partner", black: "You",
                      playedAt: now.addingTimeInterval(-7_200), playerSide: .black,
                      moves: "1. e4 e5 2. Nf3 Nc6 3. Bc4 Nd4 4. Nxe5 Qg5 5. Nxf7 Qxg2 6. Rf1 Qxe4+ 7. Be2 Nf3#",
                      status: "mate"),
            ChessGame(id: "demo-back-rank", username: "You", white: "You", black: "Practice partner",
                      playedAt: now.addingTimeInterval(-10_800), playerSide: .white,
                      moves: "1. Re7 Rb1+ 2. Re1 Rxe1#",
                      initialFEN: "6k1/5ppp/8/8/8/8/1r3PPP/4R1K1 w - - 0 1", status: "mate")
        ]
    }
}
