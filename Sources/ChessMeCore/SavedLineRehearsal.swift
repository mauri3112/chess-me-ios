import Foundation

/// Recalling a chosen saved variation does not establish that its moves are best.
public struct SavedLineRehearsal: Sendable {
    public enum Submission: Equatable, Sendable { case accepted, wrongMove, illegalMove, unavailable }
    public let playerSide: Side
    private let positions: [ChessPosition]
    private let moves: [ChessMove]
    public private(set) var index = 0
    public private(set) var mistakes = 0
    public private(set) var usedHelp = false
    public private(set) var hintSquare: Int?
    public var position: ChessPosition { positions[index] }
    public var isComplete: Bool { index == moves.count }
    public var isPlayerTurn: Bool { !isComplete && position.sideToMove == playerSide }
    public var awaitingReply: Bool { !isComplete && !isPlayerTurn }
    public var assisted: Bool { usedHelp || mistakes > 0 }
    public var cleanCompletion: Bool { isComplete && !assisted }
    public var totalPlayerMoves: Int { positions.dropLast().filter { $0.sideToMove == playerSide }.count }
    public var completedPlayerMoves: Int { positions.prefix(index).filter { $0.sideToMove == playerSide }.count }

    public init(line: SavedReviewLine) throws {
        guard line.initialFEN.utf8.count <= 256, line.positionFEN.utf8.count <= 256,
              line.prefix.count <= 2048, !line.moves.isEmpty, line.moves.count <= 512,
              (line.prefix + line.moves).allSatisfy({ $0.utf8.count == 4 || $0.utf8.count == 5 }) else {
            throw ChessError.invalidMove("Saved line is missing or too long.")
        }
        var board = try ChessPosition(fen: line.initialFEN)
        guard board.fullmoveNumber < 1_000_000, board.halfmoveClock < 1_000_000 else {
            throw ChessError.invalidMove("Saved position counters are out of range.")
        }
        var history: [String] = []
        for token in line.prefix {
            // The immutable source game may continue beyond an unclaimed draw.
            // Legal replay and the stored root establish the source prefix.
            history.append(board.repetitionKey)
            board = try board.applying(ChessMove(uci: token))
        }
        guard board.fen == line.positionFEN, history == line.repetitionHistory else {
            throw ChessError.invalidMove("Saved line does not match its source position.")
        }
        var positions = [board], moves: [ChessMove] = []
        for token in line.moves {
            guard board.outcome(repetitionCount: history.filter { $0 == board.repetitionKey }.count + 1) == .ongoing else {
                throw ChessError.invalidMove("Saved line continues after the position ended.")
            }
            let move = try ChessMove(uci: token)
            history.append(board.repetitionKey)
            board = try board.applying(move)
            moves.append(move); positions.append(board)
        }
        guard positions.dropLast().contains(where: { $0.sideToMove == line.playerSide }) else {
            throw ChessError.invalidMove("This line has no moves for your side to rehearse.")
        }
        self.positions = positions; self.moves = moves; self.playerSide = line.playerSide
    }

    @discardableResult public mutating func submit(_ move: ChessMove) -> Submission {
        guard isPlayerTurn else { return .unavailable }
        guard position.legalMoves().contains(move) else { mistakes += 1; return .illegalMove }
        guard move == moves[index] else { mistakes += 1; return .wrongMove }
        advance(); return .accepted
    }
    /// The UI calls this once after an intentional pause, never in a tight loop.
    @discardableResult public mutating func playReply() -> Bool {
        guard awaitingReply else { return false }
        advance(); return true
    }
    public mutating func hint() {
        guard isPlayerTurn else { return }
        usedHelp = true; hintSquare = moves[index].from
    }
    @discardableResult public mutating func reveal() -> ChessMove? {
        guard isPlayerTurn else { return nil }
        usedHelp = true
        let move = moves[index]; advance(); return move
    }
    public mutating func restart() { index = 0; mistakes = 0; usedHelp = false; hintSquare = nil }
    private mutating func advance() { index += 1; hintSquare = nil }
}
