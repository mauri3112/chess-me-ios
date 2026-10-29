import Foundation

/// A prefix tree of saved games. Transposed positions deliberately retain their own move order.
public struct PersonalOpeningExplorer: Sendable {
    public struct Results: Equatable, Sendable {
        public var wins = 0, draws = 0, losses = 0, unknown = 0
        public var count: Int { wins + draws + losses + unknown }
        public var known: Int { wins + draws + losses }
        mutating func add(_ result: GameResult?, side: Side) {
            guard let result else { unknown += 1; return }
            switch result.outcome(for: side) { case .won: wins += 1; case .draw: draws += 1; case .lost: losses += 1 }
        }
    }
    public struct Branch: Identifiable, Sendable {
        public var id: String { move.uci }
        public let move: ChessMove
        public let san: String
        public let results: Results
    }
    private struct Node: Sendable {
        var results = Results()
        var gameIDs: [String] = []
        var branches: [String: Branch] = [:]
        var opening: OpeningVariation?
    }
    public let accounts: [String]
    public let selectedAccount: String
    public private(set) var excludedSetup = 0
    public private(set) var excludedInvalid = 0
    public private(set) var excludedDemo = 0
    public private(set) var deferred = 0
    public private(set) var duplicateCount = 0
    public private(set) var path: [String] = []
    public private(set) var position = ChessPosition.initial
    public let maximumPly: Int
    private var nodes: [String: Node] = [:]
    private var positions: [ChessPosition] = [.initial]
    private var key: String { path.joined(separator: " ") }
    public var results: Results { nodes[key]?.results ?? Results() }
    public var gameIDs: [String] { nodes[key]?.gameIDs ?? [] }
    public var opening: OpeningVariation? { nodes[key]?.opening }
    public var branches: [Branch] {
        (nodes[key]?.branches.values.map { $0 } ?? []).sorted {
            $0.results.count == $1.results.count ? $0.san < $1.san : $0.results.count > $1.results.count
        }
    }
    public static func accounts(in games: [ChessGame]) -> [String] {
        var names: [String: String] = [:]
        for game in games where !game.id.hasPrefix("demo-") {
            if !game.username.isEmpty { names[game.username.lowercased()] = game.username }
        }
        return names.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    public init(games: [ChessGame], account: String, side: Side? = nil, speed: GameSpeedFilter = .all,
                maximumGames: Int = 20_000, maximumPly: Int = 40) throws {
        self.accounts = Self.accounts(in: games)
        self.selectedAccount = account
        self.maximumPly = max(0, min(maximumPly, 80))
        var seen = Set<String>(), accepted = 0
        for game in games {
            try Task.checkCancellation()
            guard !game.id.hasPrefix("demo-") else { excludedDemo += 1; continue }
            guard game.username.caseInsensitiveCompare(account) == .orderedSame else { continue }
            let player: Side
            if game.white.caseInsensitiveCompare(account) == .orderedSame { player = .white }
            else if game.black.caseInsensitiveCompare(account) == .orderedSame { player = .black }
            else { continue }
            guard side == nil || side == player, speed.includes(game) else { continue }
            guard seen.insert(game.id).inserted else { duplicateCount += 1; continue }
            guard accepted < max(0, maximumGames) else { deferred += 1; continue }
            guard game.isFinished else { excludedInvalid += 1; continue }
            // Bound input before parsing a potentially malformed archive record.
            guard game.moves.utf8.count <= 100_000, (game.pgn?.utf8.count ?? 0) <= 250_000 else { excludedInvalid += 1; continue }
            let replay: GameReplay
            do {
                let document = try game.mainline()
                guard document.moves.count <= 1_000 else { excludedInvalid += 1; continue }
                let headerDocument = game.pgn.flatMap { try? PGNDocument($0) }
                let variant = (headerDocument?.headers["Variant"] ?? document.headers["Variant"] ?? "standard").lowercased()
                guard ["standard", "chess"].contains(variant) else { excludedInvalid += 1; continue }
                if game.initialFEN != nil || document.initialFEN != nil || headerDocument?.initialFEN != nil {
                    excludedSetup += 1; continue
                }
                replay = try GameReplay(game: game)
                guard replay.positions.first == .initial, !replay.moves.isEmpty else { excludedInvalid += 1; continue }
            } catch is CancellationError { throw CancellationError() }
            catch { excludedInvalid += 1; continue }
            accepted += 1
            let result = game.finishedResult
            let line = OpeningBook.shared.line(in: replay)
            var prefix: [String] = []
            for ply in 0...min(self.maximumPly, replay.moves.count) {
                let key = prefix.joined(separator: " ")
                var node = nodes[key] ?? Node()
                node.results.add(result, side: player)
                node.gameIDs.append(game.id)
                node.opening = line.opening(at: ply)
                if ply < min(self.maximumPly, replay.moves.count) {
                    let move = replay.moves[ply]
                    var totals = node.branches[move.uci]?.results ?? Results()
                    totals.add(result, side: player)
                    node.branches[move.uci] = Branch(move: move, san: try replay.positions[ply].san(move), results: totals)
                }
                nodes[key] = node
                if ply < min(self.maximumPly, replay.moves.count) { prefix.append(replay.moves[ply].uci) }
            }
        }
    }
    public mutating func advance(_ move: ChessMove) throws {
        guard branches.contains(where: { $0.move == move }) else { throw ChessError.invalidMove("no saved game follows this move") }
        position = try position.applying(move)
        positions.append(position)
        path.append(move.uci)
    }
    public mutating func back() {
        guard !path.isEmpty else { return }
        path.removeLast(); positions.removeLast(); position = positions.last ?? .initial
    }
    public mutating func reset() { path = []; positions = [.initial]; position = .initial }
}
