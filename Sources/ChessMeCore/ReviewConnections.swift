import Foundation

public struct ReviewPuzzleConnection: Codable, Equatable, Identifiable, Sendable {
    public var id: String { puzzle.id }
    public let puzzle: TrainingPuzzle
    public let targetID: String
    public let explanation: String
    public static func match(puzzle: TrainingPuzzle, moment: ReviewMoment) -> Self? {
        guard let key = moment.ideaKey, key != "material-gain", key != "mate",
              (try? PuzzlePlaythrough(puzzle: puzzle)) != nil,
              let root = try? ChessPosition(fen: puzzle.positionFEN),
              let sourceRoot = try? ChessPosition(fen: moment.finding.positionFEN),
              sourceRoot.repetitionKey != root.repetitionKey,
              let proof = ReviewLineProof(position: root, moves: puzzle.solution),
              let idea = ReviewIdeaProof.identify(proof), idea.key == key else { return nil }
        // Legal continuations and an explicit shared mechanism, not catalogue
        // tags or an opening name, support the explanation of this connection.
        return Self(puzzle: puzzle, targetID: moment.id,
                    explanation: "\(moment.title) appears in another position. \(idea.explanation)")
    }
}

public extension TrainingPuzzle {
    var reviewFinding: MoveFinding {
        MoveFinding(id: "lichess-puzzle-\(id)", gameID: "", gameLabel: "Lichess catalogue puzzle",
                    positionFEN: positionFEN, playedMove: setupMove, bestMove: solution.first ?? "",
                    acceptedMoves: solution.first.map { [$0] } ?? [], continuation: solution,
                    centipawnLoss: 0, theme: "Find a strong continuation",
                    explanation: "A separate catalogue position. Inspect the complete supported line after your attempt.",
                    hint: "Consider the opponent's threats and forcing moves.", moveNumber: (try? ChessPosition(fen: positionFEN).fullmoveNumber) ?? 1,
                    source: "Lichess puzzle · CC0", isPuzzle: true)
    }
}

public enum ReviewGameConnections {
    public static func observations(game: ChessGame, journey: ReviewJourney, targets: [ReviewLearningTarget],
                                    now: Date = Date()) -> [ReviewGameObservation] {
        guard !game.id.hasPrefix("demo-"), game.timestampIsExact ?? !game.id.hasPrefix("pgn-") else { return [] }
        return journey.moments.compactMap { moment in
            guard let key = moment.ideaKey, key != "material-gain", key != "mate", let ply = moment.plies.first,
                  let target = targets.filter({
                      !$0.invalidated && $0.username.lowercased() == game.username.lowercased() &&
                      $0.finding.gameID != game.id && $0.createdAt < game.playedAt && $0.ideaKey == key
                  }).max(by: { $0.createdAt < $1.createdAt }),
                  !moment.keyLine.isEmpty,
                  let root = try? ChessPosition(fen: moment.finding.positionFEN),
                  ReviewLineProof(position: root, moves: moment.keyLine) != nil else { return nil }
            let sound = [.best, .excellent, .good, .brilliant].contains(moment.finding.estimatedQuality)
            let kind: ReviewGameObservation.Kind = moment.kind == .improvement || !sound ? .missedOpportunity : .soundChoice
            return ReviewGameObservation(targetID: target.id, game: game, ply: ply, kind: kind,
                                         positionFEN: root.fen, playedMove: moment.finding.playedMove,
                                         keyLine: moment.keyLine, explanation: moment.explanation,
                                         revision: journey.revision, lessonRevision: target.revision, now: now)
        }
    }
}
