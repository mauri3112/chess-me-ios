import Foundation

public enum FundamentalsProgress {
    public static let preferenceKey = "chessme.fundamentals.independent.v1"
}

/// Original teaching positions. Goals are checked by the legal-move rules, without engine scores.
public struct FundamentalsLesson: Identifiable, Sendable {
    public enum Goal: Sendable { case mateInOne, safePromotion }
    public let id: String
    public let title: String
    public let introduction: String
    public let hint: String
    public let fen: String
    public let exampleUCI: String
    public let goal: Goal

    public var position: ChessPosition { try! ChessPosition(fen: fen) }
    public var task: String {
        switch goal {
        case .mateInOne: return "Deliver checkmate in one move. Any legal mate counts."
        case .safePromotion: return "Promote without stalemate or allowing the promoted piece to be captured on the next move."
        }
    }

    public func accepts(_ move: ChessMove) -> Bool {
        let start = position
        guard let next = try? start.applying(move) else { return false }
        switch goal {
        case .mateInOne: return next.outcome() == .checkmate(winner: start.sideToMove)
        case .safePromotion:
            guard move.promotion != nil, next.outcome() != .stalemate,
                  !next.hasInsufficientMaterial else { return false }
            return !next.legalMoves().contains { $0.to == move.to }
        }
    }

    public static let all: [Self] = [
        .init(id: "back-rank", title: "A closed back rank", introduction: "The king's own pawns can block its escape. A rook can finish the game by checking along the back rank.", hint: "The rook can reach the eighth rank in one move.", fen: "7k/6pp/8/8/8/8/8/R3K3 w - - 0 1", exampleUCI: "a1a8", goal: .mateInOne),
        .init(id: "supported-queen", title: "Protect the checking queen", introduction: "A queen beside the king covers many escape squares. Your king must protect her if the enemy king could capture her.", hint: "Put the queen on a square protected by your king.", fen: "7k/8/5KQ1/8/8/8/8/8 w - - 0 1", exampleUCI: "g6g7", goal: .mateInOne),
        .init(id: "ladder", title: "Two rooks close the ladder", introduction: "One rook cuts off a rank. The other gives check on the next rank, leaving the king no room.", hint: "Keep the rook on the seventh rank in place. Use the other rook to check.", fen: "7k/R7/8/8/8/8/8/1R2K3 w - - 0 1", exampleUCI: "b1b8", goal: .mateInOne),
        .init(id: "black-back-rank", title: "See it from Black's side", introduction: "The same back-rank pattern works for either side. Read the coordinates with Black at the bottom.", hint: "Bring the rook to White's first rank.", fen: "r7/8/4k3/8/8/8/5PPP/6K1 b - - 0 1", exampleUCI: "a8a1", goal: .mateInOne),
        .init(id: "white-promotion", title: "Choose a useful promotion", introduction: "A pawn reaching the last rank becomes a queen, rook, bishop or knight. Here, choose a promotion that leaves useful material and keeps the new piece safe for one reply. This is a one-move exercise, not a claim about the whole ending.", hint: "Try a queen or rook. Check the enemy king's legal replies.", fen: "8/2P4k/2K5/8/8/8/8/8 w - - 0 1", exampleUCI: "c7c8q", goal: .safePromotion),
        .init(id: "black-promotion", title: "Black promotes on rank one", introduction: "Black's pawns move toward rank one. Choose a useful promotion, then check whether the enemy king can capture it or has no legal move.", hint: "The pawn on f2 can promote on f1. A queen or rook meets this exercise's goal.", fen: "8/8/8/8/8/5k2/K4p2/8 b - - 0 1", exampleUCI: "f2f1q", goal: .safePromotion)
    ]
}

/// A reveal makes the current attempt guided. Retry starts a fresh independent attempt.
public struct FundamentalsAttempt: Sendable {
    public let lesson: FundamentalsLesson
    public private(set) var position: ChessPosition
    public private(set) var completed = false
    public private(set) var guided = false
    public private(set) var feedback: String
    public init(lesson: FundamentalsLesson) {
        self.lesson = lesson; position = lesson.position; feedback = lesson.task
    }
    public mutating func hint() { guided = true; feedback = lesson.hint }
    public mutating func reveal() {
        guided = true
        let move = try! ChessMove(uci: lesson.exampleUCI)
        feedback = "One solution is \((try? position.san(move)) ?? move.uci). Play it on the board to rehearse."
    }
    public mutating func play(_ move: ChessMove) {
        guard !completed else { return }
        guard let next = try? position.applying(move) else {
            feedback = "That move is illegal. Choose a highlighted destination."; return
        }
        guard lesson.accepts(move) else {
            feedback = "\((try? position.san(move)) ?? move.uci) is legal, but does not meet this task. The position stays here so you can try again."; return
        }
        position = next; completed = true
        feedback = guided ? "Guided rehearsal complete. Retry to solve independently." : "Solved independently."
    }
}
