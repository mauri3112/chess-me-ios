import Foundation

/// Read-only navigation never changes a lesson attempt or the imported game.
public struct MoveHistory: Equatable, Sendable {
    public private(set) var positions: [ChessPosition]
    public private(set) var moves: [ChessMove]
    private var notations: [String]

    public init(position: ChessPosition) { positions = [position]; moves = []; notations = ["Start"] }
    public init(game: ChessGame) throws {
        self = try GameReplay(game: game).moveHistory
    }
    init(positions: [ChessPosition], moves: [ChessMove], notations: [String]) {
        self.positions = positions; self.moves = moves; self.notations = notations
    }
    public init(game: ChessGame?, finding: MoveFinding) throws {
        let initial = try ChessPosition(fen: finding.positionFEN)
        self.init(position: initial)
        guard let game, game.id == finding.gameID, let replay = try? GameReplay(game: game),
              let index = replay.positions.indices.first(where: {
                  replay.moves.indices.contains($0) && replay.moves[$0].uci == finding.playedMove &&
                  replay.positions[$0].fullmoveNumber == initial.fullmoveNumber &&
                  replay.positions[$0].repetitionKey == initial.repetitionKey
              }) else { return }
        positions = Array(replay.positions.prefix(index + 1))
        moves = Array(replay.moves.prefix(index))
        notations = Array(replay.moveHistory.notations.prefix(index + 1))
    }
    public func appending(_ line: [ChessMove]) throws -> Self {
        var result = self
        for move in line {
            let board = result.positions.last!
            result.notations.append("\(board.fullmoveNumber)\(board.sideToMove == .white ? "." : "…") \(try board.san(move))")
            result.positions.append(try board.applying(move))
            result.moves.append(move)
        }
        return result
    }
    /// A lesson's lead-in ends at the decision, never at the player's mistake.
    public func leadIn(plies: Int = 3) -> Self {
        let start = max(0, moves.count - max(0, plies))
        var result = MoveHistory(position: positions[start])
        result.positions = Array(positions.suffix(from: start))
        result.moves = Array(moves.suffix(from: start))
        result.notations = ["Start"] + notations.suffix(from: start + 1)
        return result
    }
    public func notation(at index: Int) -> String {
        notations.indices.contains(index) ? notations[index] : "Start"
    }
}
