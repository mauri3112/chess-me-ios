import Foundation

/// An offline study line, independent of the finished-game archive.
public struct AnalysisWorkspace: Sendable {
    public let root: ChessPosition
    public private(set) var positions: [ChessPosition]
    public private(set) var moves: [ChessMove] = []
    public private(set) var notations: [String] = []
    public static let maximumPlies = 1_000

    public init() {
        root = .initial
        positions = [.initial]
    }

    public init(fen: String) throws {
        let position = try Self.validatedPosition(fen: fen)
        root = position
        positions = [position]
    }

    public var position: ChessPosition { positions.last ?? root }
    public var repetitionHistory: [String] { positions.dropLast().map(\.repetitionKey) }
    public var outcome: PositionOutcome {
        position.outcome(repetitionCount: repetitionHistory.filter { $0 == position.repetitionKey }.count + 1)
    }

    public mutating func play(_ move: ChessMove) throws {
        guard moves.count < Self.maximumPlies else { throw ChessError.invalidMove("study line limit reached") }
        guard outcome == .ongoing else { throw ChessError.invalidMove("this position has ended") }
        let next = try position.applying(move)
        let notation = try position.san(move)
        moves.append(move)
        notations.append(notation)
        positions.append(next)
    }

    public mutating func undo() {
        guard !moves.isEmpty else { return }
        moves.removeLast()
        notations.removeLast()
        positions.removeLast()
    }

    public mutating func reset() {
        positions = [root]
        moves = []
        notations = []
    }

    public var pgn: String {
        let headers = "[Event \"ChessMe position study\"]\n[Result \"*\"]\n[SetUp \"1\"]\n[FEN \"\(root.fen)\"]"
        var tokens: [String] = []
        for index in moves.indices {
            let before = positions[index]
            if before.sideToMove == .white {
                tokens.append("\(before.fullmoveNumber).")
            } else if index == 0 {
                tokens.append("\(before.fullmoveNumber)...")
            }
            tokens.append(notations[index])
        }
        tokens.append("*")
        return headers + "\n\n" + tokens.joined(separator: " ")
    }

    /// Checks practical standard-chess constraints, without claiming retrograde reachability.
    public static func validatedPosition(fen: String) throws -> ChessPosition {
        guard fen.utf8.count <= 256, fen.unicodeScalars.allSatisfy({ $0.isASCII }) else {
            throw ChessError.invalidFEN("use a standard FEN of at most 256 characters")
        }
        let fields = fen.split(whereSeparator: \.isWhitespace)
        guard fields.count == 6,
              fields[4].allSatisfy({ $0.isNumber }), !fields[4].isEmpty,
              fields[5].allSatisfy({ $0.isNumber }), !fields[5].isEmpty,
              let halfmove = Int(fields[4]), halfmove <= 1_000_000,
              let fullmove = Int(fields[5]), fullmove <= 1_000_000 else {
            throw ChessError.invalidFEN("expected six fields with bounded move counters")
        }
        for rank in fields[0].split(separator: "/", omittingEmptySubsequences: false) {
            var previousWasDigit = false
            for character in rank {
                let isDigit = character >= "1" && character <= "8"
                guard !isDigit || !previousWasDigit else {
                    throw ChessError.invalidFEN("combine adjacent empty squares into one digit")
                }
                previousWasDigit = isDigit
            }
        }
        let position = try ChessPosition(fen: fen)
        for side in Side.allCases {
            let pieces = position.squares.compactMap { $0 }.filter { $0.side == side }
            let pawns = pieces.filter { $0.kind == .pawn }.count
            guard pieces.count <= 16, pawns <= 8 else { throw ChessError.invalidFEN("too many pieces or pawns") }
            // Every extra queen, rook, bishop or knight requires a missing pawn.
            let extras = [(PieceKind.queen, 1), (.rook, 2), (.bishop, 2), (.knight, 2)]
                .reduce(0) { total, item in total + max(0, pieces.filter { $0.kind == item.0 }.count - item.1) }
            guard extras <= 8 - pawns else { throw ChessError.invalidFEN("promoted pieces require missing pawns") }
        }
        if let ep = position.enPassantSquare {
            let origin = ep + (position.sideToMove == .white ? 8 : -8)
            guard position.squares[origin] == nil, position.halfmoveClock == 0 else {
                throw ChessError.invalidFEN("en passant requires a just-played double pawn move")
            }
        }
        return position
    }
}
