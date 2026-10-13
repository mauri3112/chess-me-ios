import Foundation

/// Keeps experimental moves separate from the imported, immutable mainline.
public struct GameReplay: Sendable {
    public let positions: [ChessPosition]
    public let moves: [ChessMove]
    public let moveHistory: MoveHistory
    public private(set) var index = 0
    public private(set) var variationPositions: [ChessPosition] = []
    public private(set) var variationMoves: [ChessMove] = []
    private var variationNotations: [String] = []

    public init(game: ChessGame) throws {
        guard game.isFinished else { throw ChessError.invalidPGN("only finished games can be reviewed") }
        let document = try game.mainline()
        guard document.result != "*" else { throw ChessError.invalidPGN("the game is unfinished") }
        var board = try (game.initialFEN ?? document.initialFEN).map(ChessPosition.init(fen:)) ?? .initial
        var positions = [board], moves: [ChessMove] = []
        var notations = ["Start"]
        for token in document.moves {
            try Task.checkCancellation()
            let move = try board.move(san: token)
            notations.append("\(board.fullmoveNumber)\(board.sideToMove == .white ? "." : "…") \(try board.san(move))")
            board = try board.applying(move)
            moves.append(move)
            positions.append(board)
        }
        self.positions = positions
        self.moves = moves
        self.moveHistory = MoveHistory(positions: positions, moves: moves, notations: notations)
    }
    public var position: ChessPosition { variationPositions.last ?? positions[index] }
    public var isVariation: Bool { !variationMoves.isEmpty }
    public var previousMove: ChessMove? { variationMoves.last ?? (index > 0 ? moves[index - 1] : nil) }
    public var repetitionHistory: [String] {
        Array(positions.prefix(index + (isVariation ? 1 : 0))).map(\.repetitionKey) + variationPositions.dropLast().map(\.repetitionKey)
    }
    public mutating func navigate(to index: Int) {
        self.index = min(moves.count, max(0, index))
        variationPositions = []; variationMoves = []; variationNotations = []
    }
    public mutating func previous() {
        if isVariation { variationPositions.removeLast(); variationMoves.removeLast(); variationNotations.removeLast() }
        else { navigate(to: index - 1) }
    }
    public mutating func play(_ move: ChessMove) throws {
        guard position.outcome(repetitionCount: repetitionHistory.filter { $0 == position.repetitionKey }.count + 1) == .ongoing else {
            throw ChessError.invalidMove("this position has ended")
        }
        let next = try position.applying(move)
        variationNotations.append(try position.san(move))
        variationPositions.append(next)
        variationMoves.append(move)
    }
    public var variationSAN: String {
        variationNotations.joined(separator: " ")
    }
}
