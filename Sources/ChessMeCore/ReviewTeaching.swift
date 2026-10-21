import Foundation

public struct ReviewLineProof: Equatable, Sendable {
    public let rootFEN: String
    public let moves: [String]
    public let positions: [ChessPosition]
    public let notation: [String]
    public var solver: Side { positions[0].sideToMove }
    public var materialGain: Int {
        Self.material(positions.last!, for: solver) - Self.material(positions[0], for: solver)
    }
    public var endsInMate: Bool { positions.last?.outcome() == .checkmate(winner: solver) }
    public init?(position: ChessPosition, moves: [String]) {
        guard !moves.isEmpty else { return nil }
        var board = position
        var positions = [position], notation: [String] = []
        for token in moves {
            guard let move = try? ChessMove(uci: token), let san = try? board.san(move),
                  let next = try? board.applying(move) else { return nil }
            notation.append(san); positions.append(next); board = next
        }
        self.rootFEN = position.fen; self.moves = moves; self.positions = positions; self.notation = notation
    }
    public static func material(_ board: ChessPosition, for side: Side) -> Int {
        board.squares.compactMap { $0 }.reduce(0) { $0 + ($1.side == side ? $1.kind.value : -$1.kind.value) }
    }
    public static func square(_ value: Int) -> String {
        String(UnicodeScalar(97 + value % 8)!) + String(value / 8 + 1)
    }
}

/// A mechanism supported by the shown legal line. These keys never imply that
/// every opponent reply is forced, or reveal what a player intended to do.
public struct ReviewIdeaProof: Equatable, Sendable {
    public let key: String
    public let title: String
    public let explanation: String
    public let line: ReviewLineProof

    public static func identify(_ line: ReviewLineProof) -> Self? {
        guard let first = try? ChessMove(uci: line.moves[0]),
              let piece = line.positions[0].squares[first.from] else { return nil }
        if line.endsInMate {
            let end = line.positions.last!
            let lastMove = try? ChessMove(uci: line.moves.last!)
            let matingPiece = lastMove.flatMap { end.squares[$0.to] }
            let king = end.squares.indices.first { end.squares[$0] == Piece(kind: .king, side: line.solver.opposite) }
            var key = "mate", detail = "The shown line finishes with \(line.notation.last!) and checkmate."
            if let king, let lastMove, (matingPiece?.kind == .rook || matingPiece?.kind == .queen),
               king / 8 == (line.solver == .white ? 7 : 0), lastMove.to / 8 == king / 8 {
                let front = king / 8 + (line.solver == .white ? -1 : 1)
                let exits = (-1...1).compactMap { offset -> Int? in
                    let file = king % 8 + offset
                    return (0..<8).contains(file) ? front * 8 + file : nil
                }
                if exits.allSatisfy({ end.squares[$0]?.side == line.solver.opposite }) {
                    key = "back-rank-mate"
                    detail = "The king is confined on its back rank by its own pieces. \(line.notation.last!) mates along that rank."
                }
            }
            if let king, matingPiece?.kind == .knight {
                let adjacent = end.squares.indices.filter {
                    $0 != king && abs($0 % 8 - king % 8) <= 1 && abs($0 / 8 - king / 8) <= 1
                }
                if adjacent.allSatisfy({ end.squares[$0]?.side == line.solver.opposite }) {
                    key = "smothered-mate"
                    detail = "The knight delivers mate while the king's own pieces occupy every neighbouring square."
                }
            }
            return Self(key: key, title: "Build a mating attack",
                        explanation: detail + " Inspect the replies in this line; another reply needs its own verification.", line: line)
        }
        if first.promotion != nil {
            return Self(key: "promotion", title: "Make the promotion count",
                        explanation: "\(line.notation[0]) promotes the pawn on \(ReviewLineProof.square(first.to)). The shown continuation lets you inspect the resulting position.", line: line)
        }
        let after = line.positions[1]
        let targets = after.squares.indices.filter {
            guard let target = after.squares[$0], target.side != piece.side,
                  target.kind == .king || target.kind.value >= 300 else { return false }
            return attacks(piece: after.squares[first.to] ?? piece, from: first.to, to: $0, board: after)
        }
        let forkPayoff = line.moves.indices.dropFirst(2).contains { index in
            guard let capture = try? ChessMove(uci: line.moves[index]), targets.contains(capture.to),
                  line.positions[index].sideToMove == line.solver,
                  let victim = line.positions[index].squares[capture.to], victim.side != line.solver,
                  victim == after.squares[capture.to] else { return false }
            return true
        }
        if targets.count >= 2, line.materialGain >= 100, forkPayoff {
            let names = targets.prefix(2).map { "\(after.squares[$0]!.kind.rawValue) on \(ReviewLineProof.square($0))" }
            return Self(key: "fork-\(piece.kind.rawValue)", title: "Create two threats",
                        explanation: "\(line.notation[0]) attacks the \(names.joined(separator: " and ")). The shown replies lead to a material gain; compare a different defence in Explore.", line: line)
        }
        if line.materialGain >= 100 {
            let captures = line.moves.indices.compactMap { index -> String? in
                guard let move = try? ChessMove(uci: line.moves[index]),
                      line.positions[index].sideToMove == line.solver,
                      let victim = line.positions[index].squares[move.to] else { return nil }
                return "\(line.notation[index]) captures the \(victim.kind.rawValue) on \(ReviewLineProof.square(move.to))"
            }
            if let capture = captures.first {
                return Self(key: "material-gain", title: "Win material with a continuation",
                            explanation: capture + ". Follow the replies to see the resulting material balance. This is a demonstrated line, not a claim that every reply is forced.", line: line)
            }
        }
        return nil
    }

    private static func attacks(piece: Piece, from: Int, to: Int, board: ChessPosition) -> Bool {
        let dx = to % 8 - from % 8, dy = to / 8 - from / 8
        switch piece.kind {
        case .knight: return abs(dx) * abs(dy) == 2
        case .pawn: return abs(dx) == 1 && dy == (piece.side == .white ? 1 : -1)
        case .king: return max(abs(dx), abs(dy)) == 1
        case .bishop, .rook, .queen:
            let diagonal = abs(dx) == abs(dy) && dx != 0
            let straight = (dx == 0) != (dy == 0)
            guard (piece.kind != .bishop && straight) || (piece.kind != .rook && diagonal) else { return false }
            let sx = dx == 0 ? 0 : (dx > 0 ? 1 : -1), sy = dy == 0 ? 0 : (dy > 0 ? 1 : -1)
            var file = from % 8 + sx, rank = from / 8 + sy
            while file != to % 8 || rank != to / 8 {
                guard board.squares[rank * 8 + file] == nil else { return false }
                file += sx; rank += sy
            }
            return true
        }
    }
}

public struct ReviewMoment: Identifiable, Sendable {
    public enum Kind: String, Sendable { case improvement, strength, plan }
    public let id: String
    public let finding: MoveFinding
    public let kind: Kind
    public let plies: [Int]
    public let ideaKey: String?
    public let keyLine: [String]
    public let explanation: String
    public var title: String { finding.theme }
    /// Lesson identity changes with its playable objective, independently of
    /// unrelated decisions or completion timestamps elsewhere in the game.
    public var evidenceRevision: String {
        ReviewIdentity.make([id, finding.positionFEN, finding.bestMove, finding.continuation.joined(separator: " "),
                             String(finding.isPuzzle), finding.source, ideaKey ?? ""])
    }
}

public struct ReviewJourney: Sendable {
    public let gameID: String
    public let revision: String
    public let moments: [ReviewMoment]
    public let mainTakeawayID: String?
    public let coverage: String

    public init(game: ChessGame, analysis: GameAnalysis?) {
        self.gameID = game.id
        guard let analysis, let replay = try? GameReplay(game: game) else {
            revision = "unavailable"; moments = []; mainTakeawayID = nil; coverage = "Analysis unavailable"; return
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let evidence = (try? encoder.encode(analysis)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        revision = ReviewIdentity.make([game.id, game.moves, game.initialFEN ?? "", evidence])
        coverage = "\(analysis.analyzedPlies)/\(analysis.totalPlies) player decisions · \(analysis.source)"
        let assessments = Dictionary(analysis.moveAssessments?.map { ($0.ply, $0) } ?? [], uniquingKeysWith: { first, _ in first })
        var items: [ReviewMoment] = []
        for original in analysis.findings {
            guard let ply = replay.positions.indices.dropLast().first(where: {
                replay.positions[$0].fen == original.positionFEN && replay.moves[$0].uci == original.playedMove
            }), original.moveNumber == replay.positions[ply].fullmoveNumber else { continue }
            let tokens = original.continuation.first == original.bestMove ? original.continuation : [original.bestMove]
            let proof = ReviewLineProof(position: replay.positions[ply], moves: tokens)
            let idea = proof.flatMap(ReviewIdeaProof.identify)
            let text = idea?.explanation ?? original.explanation
            let finding = Self.finding(original, explanation: text, continuation: proof?.moves ?? [])
            items.append(ReviewMoment(id: finding.id, finding: finding, kind: .improvement, plies: [ply],
                                      ideaKey: idea?.key, keyLine: proof?.moves ?? [], explanation: text))
        }

        // Positive moments need both a concrete board mechanism and completed
        // favourable assessments of the actual player decisions in the line.
        for assessment in assessments.values.sorted(by: { $0.ply < $1.ply }) {
            let ply = assessment.ply
            guard replay.moves.indices.contains(ply), replay.positions[ply].fen == assessment.positionFEN,
                  replay.moves[ply].uci == assessment.playedMove,
                  [.best, .excellent, .brilliant].contains(assessment.quality), assessment.completedDepth >= 6,
                  assessment.playedMove == assessment.bestMove, assessment.centipawnLoss <= 35,
                  replay.positions[ply].sideToMove == game.playerSide,
                  !items.contains(where: { $0.plies.contains(ply) }) else { continue }
            let end = min(replay.moves.count, ply + 5)
            let own = (ply..<end).filter { replay.positions[$0].sideToMove == game.playerSide }
            guard own.allSatisfy({ index in
                guard let value = assessments[index] else { return false }
                return value.positionFEN == replay.positions[index].fen && value.playedMove == replay.moves[index].uci &&
                    value.completedDepth >= 6 && [.best, .excellent, .good, .brilliant].contains(value.quality)
            }) else { continue }
            let tokens = replay.moves[ply..<end].map(\.uci)
            guard let line = ReviewLineProof(position: replay.positions[ply], moves: tokens),
                  let idea = ReviewIdeaProof.identify(line) else { continue }
            let id = ReviewIdentity.make([game.username.lowercased(), game.id, String(ply), line.rootFEN, "strength"])
            let finding = MoveFinding(id: id, gameID: game.id, gameLabel: game.label, positionFEN: line.rootFEN,
                                      playedMove: assessment.playedMove, bestMove: assessment.bestMove,
                                      acceptedMoves: [assessment.bestMove], continuation: tokens,
                                      centipawnLoss: 0, theme: idea.title, explanation: idea.explanation,
                                      hint: "Look at the threats and the opponent's strongest reply.",
                                      moveNumber: replay.positions[ply].fullmoveNumber, source: analysis.source,
                                      isPuzzle: true, quality: assessment.quality)
            items.append(ReviewMoment(id: id, finding: finding, kind: .strength, plies: [ply],
                                      ideaKey: idea.key, keyLine: tokens, explanation: idea.explanation))
        }
        let plans = Self.filePlans(game: game, replay: replay, assessments: assessments, source: analysis.source)
        let planRoots = Set(plans.compactMap { $0.plies.first })
        items.removeAll { planRoots.contains($0.plies.first ?? -1) }
        items.append(contentsOf: plans)
        moments = items.sorted { ($0.plies.first ?? 0) < ($1.plies.first ?? 0) }
        mainTakeawayID = moments.max {
            let lhs = $0.finding.centipawnLoss + ($0.kind == .plan ? 120 : 0)
            let rhs = $1.finding.centipawnLoss + ($1.kind == .plan ? 120 : 0)
            return lhs < rhs
        }?.id
    }

    private static func finding(_ original: MoveFinding, explanation: String, continuation: [String]) -> MoveFinding {
        MoveFinding(id: original.id, gameID: original.gameID, gameLabel: original.gameLabel,
                    positionFEN: original.positionFEN, playedMove: original.playedMove, bestMove: original.bestMove,
                    acceptedMoves: original.acceptedMoves, continuation: continuation,
                    centipawnLoss: original.centipawnLoss, theme: original.theme, explanation: explanation,
                    hint: original.hint, moveNumber: original.moveNumber, source: original.source,
                    isPuzzle: original.isPuzzle && !continuation.isEmpty, quality: original.quality)
    }

    /// Connect a pawn exchange to a rook's later use of the opened file in the
    /// actual game. The sequence explains an observable plan, not private intent.
    private static func filePlans(game: ChessGame, replay: GameReplay, assessments: [Int: MoveAssessment],
                                  source: String) -> [ReviewMoment] {
        var plans: [ReviewMoment] = []
        for ply in replay.moves.indices {
            let root = replay.positions[ply], pawnMove = replay.moves[ply]
            guard root.sideToMove == game.playerSide, root.squares[pawnMove.from]?.kind == .pawn,
                  pawnMove.from % 8 != pawnMove.to % 8, root.squares[pawnMove.to] != nil,
                  let firstGrade = assessments[ply], firstGrade.completedDepth >= 6, firstGrade.quality != .book else { continue }
            let file = pawnMove.from % 8
            func pawnOnFile(_ board: ChessPosition) -> Bool {
                board.squares.indices.contains { $0 % 8 == file && board.squares[$0]?.kind == .pawn }
            }
            guard !pawnOnFile(replay.positions[ply + 1]) else { continue }
            let last = min(replay.moves.count - 1, ply + 8)
            guard last > ply, let rookPly = ((ply + 1)...last).first(where: { index in
                let move = replay.moves[index], board = replay.positions[index]
                return board.sideToMove == game.playerSide && board.squares[move.from]?.kind == .rook &&
                    move.to % 8 == file && !pawnOnFile(board)
            }) else { continue }
            let own = (ply...rookPly).filter { replay.positions[$0].sideToMove == game.playerSide }
            guard own.allSatisfy({ index in
                guard let grade = assessments[index] else { return false }
                return grade.completedDepth >= 6 && grade.positionFEN == replay.positions[index].fen && grade.playedMove == replay.moves[index].uci
            }) else { continue }
            let tokens = replay.moves[ply...rookPly].map(\.uci)
            guard let proof = ReviewLineProof(position: root, moves: tokens) else { continue }
            let good = own.allSatisfy { [.best, .excellent, .good, .brilliant].contains(assessments[$0]!.quality) }
            let fileName = String(UnicodeScalar(97 + file)!)
            let explanation = "\(proof.notation[0]) removes the last pawn from the \(fileName)-file. In the played sequence, \(proof.notation.last!) brings a rook onto that file. \(good ? "The reviewed choices preserve the position in the available analysis." : "One or more reviewed choices lost value; compare the stronger replies before adopting this plan.") The line shows what happened in this game, not a forced sequence."
            let id = ReviewIdentity.make([game.username.lowercased(), game.id, String(ply), "open-file", String(file)])
            let finding = MoveFinding(id: id, gameID: game.id, gameLabel: game.label, positionFEN: root.fen,
                                      playedMove: pawnMove.uci, bestMove: firstGrade.bestMove, acceptedMoves: [firstGrade.bestMove],
                                      continuation: firstGrade.playedMove == firstGrade.bestMove ? tokens : [],
                                      centipawnLoss: Double(own.compactMap { assessments[$0]?.centipawnLoss }.max() ?? 0),
                                      theme: good ? "Open a file and activate the rook" : "An open-file plan to examine",
                                      explanation: explanation, hint: "Consider which file your rook could use.",
                                      moveNumber: root.fullmoveNumber, source: source, isPuzzle: good && firstGrade.playedMove == firstGrade.bestMove,
                                      quality: own.compactMap { assessments[$0] }.max(by: { $0.centipawnLoss < $1.centipawnLoss })?.quality ?? firstGrade.quality)
            plans.append(ReviewMoment(id: id, finding: finding, kind: .plan, plies: own,
                                      ideaKey: "open-file", keyLine: tokens, explanation: explanation))
        }
        return plans
    }
}

public enum ReviewMoveVerdict: Sendable {
    case accepted(line: [String])
    case mistake(message: String, line: [String])
    case ungraded(message: String)
}

public enum ReviewMoveAcceptance {
    public static let minimumDepth = 6
    public static func judge(move: ChessMove, position: ChessPosition, evaluation: PositionEvaluation) -> ReviewMoveVerdict {
        guard position.legalMoves().contains(move) else { return .ungraded(message: "Choose a legal move.") }
        if (try? position.applying(move).outcome()) == .checkmate(winner: position.sideToMove) {
            return .accepted(line: [move.uci])
        }
        guard evaluation.completedDepth >= minimumDepth, let best = evaluation.best,
              let chosen = evaluation.moves.first(where: { $0.move == move }),
              let line = ReviewLineProof(position: position, moves: chosen.continuation.map(\.uci)),
              line.moves.first == move.uci else {
            return .ungraded(message: "This choice needs more analysis. Retry analysis, explore it, or continue.")
        }
        let sameWinningMate = best.isWinningMate && chosen.isWinningMate
        let lostMate = best.isWinningMate && !chosen.isWinningMate || chosen.isLosingMate && !best.isLosingMate
        let scoreLoss = max(0, best.score - chosen.score)
        let practicalLoss = max(0, ReviewMovePolicy.chance(best.score) - ReviewMovePolicy.chance(chosen.score))
        let comparable = scoreLoss <= 60 || practicalLoss <= 2 && chosen.score >= 100
        if sameWinningMate || !lostMate && comparable {
            return .accepted(line: line.moves)
        }
        let message: String
        if chosen.isLosingMate && !best.isLosingMate {
            message = "This move allows a mating line. Show why to inspect the opponent's reply."
        } else if line.materialGain < 0 {
            message = "The shown replies leave you down material. Show why to inspect the exchanges."
        } else if line.notation.count > 1 {
            message = "\(line.notation[1]) is the critical reply in this line. Compare the resulting position."
        } else {
            return .ungraded(message: "The calculation does not yet explain this difference. Try more analysis.")
        }
        return .mistake(message: message, line: line.moves)
    }

    public static func explanation(move: ChessMove, position: ChessPosition, evaluation: PositionEvaluation) -> String {
        guard let chosen = evaluation.moves.first(where: { $0.move == move }),
              let proof = ReviewLineProof(position: position, moves: chosen.continuation.map(\.uci)) else {
            return "This move has not yet been evaluated in this position."
        }
        let idea = ReviewIdeaProof.identify(proof)
        let comparison: String
        switch judge(move: move, position: position, evaluation: evaluation) {
        case .accepted: comparison = "This is a supported alternative at the available search depth."
        case .mistake(let message, _): comparison = message
        case .ungraded(let message): comparison = message
        }
        return [idea?.explanation, comparison, "Shown line: " + proof.notation.joined(separator: " ")].compactMap { $0 }.joined(separator: "\n\n")
    }
}
