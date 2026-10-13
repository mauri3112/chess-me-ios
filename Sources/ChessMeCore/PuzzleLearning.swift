import Foundation

public struct TrainingPuzzle: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let setupFEN: String
    public let setupMove: String
    public let positionFEN: String
    public let solution: [String]
    public let rating: Int
    public let themes: [String]
    public let openingTags: [String]
    public let url: URL
    public let source: String
    public let license: String

    public init(id: String, setupFEN: String, setupMove: String, positionFEN: String, solution: [String],
                rating: Int, themes: [String], openingTags: [String] = [], url: URL, source: String = "lichess", license: String = "CC0") {
        self.id = id; self.setupFEN = setupFEN; self.setupMove = setupMove; self.positionFEN = positionFEN
        self.solution = solution; self.rating = rating; self.themes = themes; self.openingTags = openingTags
        self.url = url; self.source = source; self.license = license
    }
}

/// Applies the opponent's setup, validates every ply, and grades all solver turns.
public struct PuzzlePlaythrough: Sendable {
    public let puzzle: TrainingPuzzle
    public let solution: [ChessMove]
    public private(set) var positions: [ChessPosition]
    public private(set) var moves: [ChessMove] = []
    public private(set) var cursor = 0
    public private(set) var isComplete = false
    public var position: ChessPosition { positions.last! }
    public var isAwaitingReply: Bool { !isComplete && cursor % 2 == 1 && cursor < solution.count }

    public init(puzzle: TrainingPuzzle) throws {
        let setup = try ChessPosition(fen: puzzle.setupFEN)
        let start = try setup.applying(ChessMove(uci: puzzle.setupMove))
        guard start == (try ChessPosition(fen: puzzle.positionFEN)),
              !puzzle.solution.isEmpty, puzzle.solution.count <= 31, puzzle.solution.count % 2 == 1 else {
            throw ChessError.invalidPGN("invalid puzzle setup or solution")
        }
        let line = try puzzle.solution.map(ChessMove.init(uci:))
        var board = start
        for move in line { board = try board.applying(move) }
        self.puzzle = puzzle; solution = line; positions = [start]
    }
    @discardableResult
    public mutating func play(_ move: ChessMove, automaticallyReply: Bool = true) throws -> Bool {
        guard !isComplete, !isAwaitingReply, solution.indices.contains(cursor) else { return false }
        let next = try position.applying(move)
        let alternateMate = puzzle.themes.contains("mateIn1") && next.outcome() == .checkmate(winner: position.sideToMove)
        guard move == solution[cursor] || alternateMate else { return false }
        positions.append(next); moves.append(move); cursor += 1
        if alternateMate { isComplete = true; return true }
        if automaticallyReply { try playReply() }
        isComplete = cursor == solution.count
        return true
    }
    @discardableResult
    public mutating func playReply() throws -> Bool {
        guard isAwaitingReply else { return false }
        let reply = solution[cursor]
        positions.append(try position.applying(reply)); moves.append(reply); cursor += 1
        return true
    }
    public mutating func reveal() throws {
        while cursor < solution.count {
            let move = solution[cursor]
            positions.append(try position.applying(move)); moves.append(move); cursor += 1
        }
        isComplete = true
    }
    public var history: MoveHistory {
        let setup = try! ChessPosition(fen: puzzle.setupFEN)
        return try! MoveHistory(position: setup).appending([ChessMove(uci: puzzle.setupMove)] + moves)
    }
}

public enum PuzzleTheme {
    public static func title(_ theme: String) -> String {
        switch theme {
        case "mate": return "Checkmate"
        case "mateIn1": return "Mate in one"
        case "mateIn2": return "Mate in two"
        case "mateIn3": return "Mate in three"
        case "fork": return "Forks"
        case "pin": return "Pins"
        case "skewer": return "Skewers"
        case "hangingPiece": return "Unprotected pieces"
        case "defensiveMove": return "Defending threats"
        case "advantage": return "Building an advantage"
        case "promotion": return "Promotion"
        case "endgame": return "Endgames"
        case "discoveredAttack": return "Discovered attacks"
        case "backRankMate": return "Back rank mate"
        case "exposedKing": return "Exposed king"
        default: return theme.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Conservative geometric tags plus broad teaching themes. These are estimated similarities.
    public static func related(to finding: MoveFinding) -> Set<String> {
        guard let board = try? ChessPosition(fen: finding.positionFEN), let move = try? ChessMove(uci: finding.bestMove),
              let next = try? board.applying(move), let piece = next.squares[move.to] else { return [] }
        var themes = Set<String>()
        if next.outcome() == .checkmate(winner: board.sideToMove) { themes.formUnion(["mate", "mateIn1"]) }
        else if finding.theme == "Missed checkmate" { themes.insert("mate") }
        if finding.theme == "King safety" || finding.theme == "Preventing material loss" || finding.theme == "Avoiding checkmate" {
            themes.insert("defensiveMove")
        }
        if move.promotion != nil { themes.insert("promotion") }
        if let captured = board.squares[move.to], captured.side != board.sideToMove,
           !board.isAttacked(move.to, by: captured.side) { themes.insert("hangingPiece") }
        let targets = next.squares.indices.filter { square in
            guard let target = next.squares[square], target.side != piece.side,
                  target.kind == .king || target.kind.value >= 300 else { return false }
            return attacks(piece: piece, from: move.to, to: square, board: next)
        }
        if piece.kind != .king && targets.count >= 2 { themes.insert("fork") }
        if [.bishop, .rook, .queen].contains(piece.kind) {
            for (df, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)] {
                if piece.kind == .bishop && (df == 0 || dr == 0) { continue }
                if piece.kind == .rook && df != 0 && dr != 0 { continue }
                var file = move.to % 8 + df, rank = move.to / 8 + dr
                var first: Piece?
                while (0..<8).contains(file) && (0..<8).contains(rank) {
                    if let target = next.squares[rank * 8 + file] {
                        if target.side == piece.side { break }
                        if let first {
                            if target.kind == .king && first.kind != .king { themes.insert("pin") }
                            if (first.kind == .king || first.kind.value > target.kind.value) && target.kind.value >= 300 { themes.insert("skewer") }
                            break
                        }
                        first = target
                    }
                    file += df; rank += dr
                }
            }
        }
        if board.squares.compactMap({ $0 }).filter({ $0.kind != .pawn && $0.kind != .king }).count <= 4 { themes.insert("endgame") }
        if themes.isEmpty { themes.insert("advantage") }
        return themes
    }

    private static func attacks(piece: Piece, from: Int, to: Int, board: ChessPosition) -> Bool {
        let df = to % 8 - from % 8, dr = to / 8 - from / 8
        switch piece.kind {
        case .pawn: return abs(df) == 1 && dr == (piece.side == .white ? 1 : -1)
        case .knight: return abs(df) * abs(dr) == 2
        case .king: return max(abs(df), abs(dr)) == 1
        case .bishop: guard abs(df) == abs(dr) else { return false }
        case .rook: guard df == 0 || dr == 0 else { return false }
        case .queen: guard df == 0 || dr == 0 || abs(df) == abs(dr) else { return false }
        }
        let stepFile = df == 0 ? 0 : (df > 0 ? 1 : -1), stepRank = dr == 0 ? 0 : (dr > 0 ? 1 : -1)
        var file = from % 8 + stepFile, rank = from / 8 + stepRank
        while rank * 8 + file != to {
            if board.squares[rank * 8 + file] != nil { return false }
            file += stepFile; rank += stepRank
        }
        return true
    }
}

public extension DemoContent {
    /// One public CC0 example for offline demonstration. It is not a personal match.
    static var puzzleExamples: [TrainingPuzzle] {
        [TrainingPuzzle(id: "00sHx", setupFEN: "q3k1nr/1pp1nQpp/3p4/1P2p3/4P3/B1PP1b2/B5PP/5K2 b k - 0 17",
                        setupMove: "e8d7", positionFEN: "q5nr/1ppknQpp/3p4/1P2p3/4P3/B1PP1b2/B5PP/5K2 w - - 1 18",
                        solution: ["a2e6", "d7d8", "f7f8"], rating: 1760, themes: ["mate", "mateIn2"],
                        url: URL(string: "https://lichess.org/training/00sHx")!)]
    }
}
