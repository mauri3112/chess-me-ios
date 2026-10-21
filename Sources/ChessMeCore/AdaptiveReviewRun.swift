import Foundation

public enum ReviewPracticeGoal: Codable, Equatable, Sendable {
    case mate
    case materialGain(Int)
    case openFile(Int)
    case decisions
    public var prompt: String {
        switch self {
        case .mate: return "Find a mating continuation"
        case .openFile(let file): return "Open the \(String(UnicodeScalar(97 + file)!))-file and activate a rook on it"
        case .materialGain(let value):
            return "Find a continuation that gains at least \(value == 100 ? "a pawn" : String(format: "%g", Double(value) / 100) + " pawns") of material"
        case .decisions: return "Find a strong continuation"
        }
    }
}

/// Persisted after each transition. A pending opponent reply is consumed exactly
/// once, and the accepted prefix is independent of a requested demonstration.
public struct AdaptiveReviewRun: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let targetID: String
    public let revision: String
    public let rootFEN: String
    public let rootHistory: [String]
    public let solver: Side
    public let requiredDecisions: Int
    public let requiresMate: Bool
    public let goal: ReviewPracticeGoal
    public let sourceFinding: MoveFinding
    public let puzzleSnapshot: TrainingPuzzle?
    public var puzzleConnection: ReviewPuzzleConnection?
    public var relatedOffer: ReviewPuzzleConnection?
    public var currentFEN: String
    public var acceptedMoves: [String] = []
    public var pendingReply: String?
    public var remainingLine: [String] = []
    public var acceptedDecisions = 0
    public var attempt: ReviewPracticeAttempt
    public var feedback: String?
    public var counterline: [String] = []
    public var hintLevel = 0

    public init(finding: MoveFinding, revision: String, history: [String] = [], now: Date = Date(),
                kind: ReviewPracticeAttempt.Kind = .game, puzzleID: String? = nil, seenBefore: Bool = false,
                learningTargetID: String? = nil, puzzle: TrainingPuzzle? = nil) throws {
        let root = try ChessPosition(fen: finding.positionFEN)
        guard finding.isPuzzle, let proof = ReviewLineProof(position: root, moves: finding.continuation),
              proof.moves.first == finding.bestMove else {
            throw ChessError.invalidMove("This lesson has no verified playable exercise line. Use review or Explore.")
        }
        let id = UUID().uuidString
        let target = learningTargetID ?? finding.id
        self.id = id; self.targetID = target; self.revision = revision; self.rootFEN = root.fen
        self.sourceFinding = finding; self.puzzleSnapshot = puzzle
        self.currentFEN = root.fen; self.rootHistory = history; self.solver = root.sideToMove
        self.requiresMate = proof.endsInMate
        let solverMoves = (proof.moves.count + 1) / 2
        self.requiredDecisions = max(1, solverMoves)
        if proof.endsInMate { self.goal = .mate }
        else if let first = try? ChessMove(uci: proof.moves[0]), root.squares[first.from]?.kind == .pawn,
                first.from % 8 != first.to % 8,
                let last = try? ChessMove(uci: proof.moves.last!),
                proof.positions.dropLast().last?.squares[last.from]?.kind == .rook,
                last.to % 8 == first.from % 8,
                !proof.positions.last!.squares.indices.contains(where: { $0 % 8 == first.from % 8 && proof.positions.last!.squares[$0]?.kind == .pawn }) {
            self.goal = .openFile(first.from % 8)
        } else if proof.materialGain >= 100 { self.goal = .materialGain(proof.materialGain) }
        else { self.goal = .decisions }
        self.attempt = ReviewPracticeAttempt(targetID: target, kind: kind, puzzleID: puzzleID,
                                            evidenceRevision: revision, rootFEN: root.fen, knownSeenBefore: seenBefore,
                                            topicCued: kind == .relatedPuzzle || goal != .decisions, now: now, id: id)
    }
    public var position: ChessPosition { (try? ChessPosition(fen: currentFEN)) ?? .initial }
    public var isFinished: Bool { attempt.outcome != .inProgress && attempt.outcome != .interrupted }
    public var isConsistent: Bool {
        guard id == attempt.id, targetID == attempt.targetID, revision == attempt.evidenceRevision,
              requiredDecisions > 0, let root = try? ChessPosition(fen: rootFEN), root.sideToMove == solver else { return false }
        var board = root, decisions = 0
        for token in acceptedMoves {
            if board.sideToMove == solver { decisions += 1 }
            guard let move = try? ChessMove(uci: token), let next = try? board.applying(move) else { return false }
            board = next
        }
        guard board.fen == currentFEN, decisions == acceptedDecisions, attempt.line == acceptedMoves else { return false }
        if let pendingReply {
            return !isFinished && board.sideToMove != solver && remainingLine.first == pendingReply &&
                (try? ChessMove(uci: pendingReply)).map { board.legalMoves().contains($0) } == true
        }
        return isFinished || board.sideToMove == solver
    }
    public var history: [String] {
        var board = (try? ChessPosition(fen: rootFEN)) ?? .initial
        var result = rootHistory
        for token in acceptedMoves {
            result.append(board.repetitionKey)
            guard let move = try? ChessMove(uci: token), let next = try? board.applying(move) else { break }
            board = next
        }
        return result
    }

    /// Reuse only the exact pinned line. Catalogue endpoints are established by
    /// the curated solution; game endpoints still need a verified defence.
    @discardableResult
    public mutating func submitStoredMove(_ move: ChessMove, verifiedDepth: Int? = nil, now: Date = Date()) -> Bool {
        guard !isFinished, pendingReply == nil, position.sideToMove == solver,
              let root = try? ChessPosition(fen: rootFEN),
              let proof = ReviewLineProof(position: root, moves: sourceFinding.continuation),
              acceptedMoves.count < proof.moves.count,
              acceptedMoves == Array(proof.moves.prefix(acceptedMoves.count)),
              proof.positions[acceptedMoves.count].fen == currentFEN,
              proof.moves[acceptedMoves.count] == move.uci, position.legalMoves().contains(move) else { return false }
        let remaining = Array(proof.moves.dropFirst(acceptedMoves.count))
        let catalogue = puzzleSnapshot.map {
            $0.id == attempt.puzzleID && $0.positionFEN == rootFEN && $0.solution == proof.moves
        } ?? false
        guard catalogue || (verifiedDepth ?? 0) >= ReviewMoveAcceptance.minimumDepth else { return false }
        let mates = (try? position.applying(move).outcome()) == .checkmate(winner: solver)
        guard catalogue || remaining.count > 1 || mates else { return false }
        accept(move, line: remaining, now: now, catalogueEndpoint: catalogue && remaining.count == 1)
        return true
    }

    public mutating func submit(_ move: ChessMove, evaluation: PositionEvaluation, now: Date = Date()) {
        guard !isFinished, pendingReply == nil, position.sideToMove == solver else { return }
        let board = position
        guard board.legalMoves().contains(move) else { feedback = "Choose a legal move."; return }
        switch ReviewMoveAcceptance.judge(move: move, position: board, evaluation: evaluation) {
        case .ungraded(let message):
            feedback = message
            attempt.decisions.append(ReviewDecision(positionFEN: board.fen, move: move.uci, grade: .ungraded, date: now))
        case .mistake(let message, let line):
            feedback = message; counterline = line
            attempt.decisions.append(ReviewDecision(positionFEN: board.fen, move: move.uci, grade: .mistake, date: now))
        case .accepted(let line):
            accept(move, line: line, now: now)
        }
    }

    private mutating func accept(_ move: ChessMove, line: [String], now: Date, catalogueEndpoint: Bool = false) {
        let board = position
        guard let next = try? board.applying(move) else { return }
        attempt.decisions.append(ReviewDecision(positionFEN: board.fen, move: move.uci, grade: .accepted, date: now))
        currentFEN = next.fen; acceptedMoves.append(move.uci); acceptedDecisions += 1
        attempt.line = acceptedMoves; feedback = nil; counterline = []
        remainingLine = Array(line.dropFirst())
        if catalogueEndpoint {
            attempt.outcome = .completed; attempt.endedAt = now; pendingReply = nil
        } else { finishOrPrepareReply(now: now) }
    }

    private mutating func finishOrPrepareReply(now: Date) {
        let board = position
        let terminal = board.outcome(repetitionCount: history.filter { $0 == board.repetitionKey }.count + 1)
        let objectiveReached: Bool
        switch goal {
        case .mate: objectiveReached = terminal == .checkmate(winner: solver)
        case .materialGain(let gain):
            objectiveReached = ReviewLineProof.material(board, for: solver) - ReviewLineProof.material((try? ChessPosition(fen: rootFEN)) ?? .initial, for: solver) >= gain
        case .openFile(let file):
            objectiveReached = board.squares.indices.contains { $0 % 8 == file && board.squares[$0] == Piece(kind: .rook, side: solver) } &&
                !board.squares.indices.contains { $0 % 8 == file && board.squares[$0]?.kind == .pawn }
        case .decisions: objectiveReached = true
        }
        if terminal == .checkmate(winner: solver) {
            attempt.outcome = .completed; attempt.endedAt = now; pendingReply = nil; return
        }
        guard terminal == .ongoing else {
            attempt.outcome = .ungraded; attempt.endedAt = now
            feedback = "The position has ended without verifying this exercise's objective."; return
        }
        if board.sideToMove != solver {
            guard let token = remainingLine.first, let reply = try? ChessMove(uci: token),
                  board.legalMoves().contains(reply) else {
                attempt.outcome = .ungraded; attempt.endedAt = now
                feedback = "Your choice was accepted; the follow-up needs more verification."; return
            }
            pendingReply = token
            return
        }
        // Check a non-mating payoff after the available defence, never on a
        // transient capture before an already known recapture is supplied.
        if objectiveReached && acceptedDecisions >= requiredDecisions {
            attempt.outcome = .completed; attempt.endedAt = now; pendingReply = nil; return
        }
        if acceptedDecisions >= requiredDecisions + 2 {
            attempt.outcome = .ungraded; attempt.endedAt = now; pendingReply = nil
            feedback = "Your moves are supported, but this branch has not established the stated goal. You can review it, try another continuation, or continue."
        }
    }

    public mutating func playReply(now: Date = Date()) {
        guard let token = pendingReply, !isFinished,
              let move = try? ChessMove(uci: token), let next = try? position.applying(move) else { return }
        acceptedMoves.append(token); currentFEN = next.fen; attempt.line = acceptedMoves
        pendingReply = nil
        if remainingLine.first == token { remainingLine.removeFirst() }
        finishOrPrepareReply(now: now)
    }

    public mutating func requestHelp(_ kind: ReviewExposureKind) {
        guard !isFinished else { return }
        attempt.help.append(kind)
        if kind == .hint { hintLevel += 1 }
    }
    public mutating func reviewAnswer(now: Date = Date()) {
        requestHelp(.solution)
        attempt.outcome = .revealed; attempt.endedAt = now; pendingReply = nil
    }
    public mutating func skip(now: Date = Date()) {
        guard !isFinished else { return }
        attempt.outcome = .skipped; attempt.endedAt = now; pendingReply = nil
    }

    /// A demonstration is browsable without becoming accepted attempt progress.
    public func explorationGame(prefix: MoveHistory? = nil) throws -> ChessGame {
        let root = try ChessPosition(fen: rootFEN)
        var history = prefix ?? MoveHistory(position: root)
        if let puzzle = puzzleSnapshot {
            history = try MoveHistory(position: ChessPosition(fen: puzzle.setupFEN)).appending([ChessMove(uci: puzzle.setupMove)])
        }
        guard history.positions.last?.fen == rootFEN else { throw ChessError.invalidMove("The stored source position changed.") }
        history = try history.appending(acceptedMoves.map(ChessMove.init(uci:)))
        if attempt.outcome == .revealed {
            let requested = acceptedMoves.isEmpty ? sourceFinding.continuation : remainingLine
            history = try history.appending(requested.map(ChessMove.init(uci:)))
        }
        return ChessGame(id: "pgn-practice-" + id, username: "Practice", white: "Practice continuation",
                         black: puzzleSnapshot.map { "Lichess puzzle " + $0.id } ?? sourceFinding.gameLabel,
                         playedAt: attempt.startedAt, playerSide: solver, moves: history.moves.map(\.uci).joined(separator: " "),
                         initialFEN: history.positions[0].fen, status: "resign")
    }
}
