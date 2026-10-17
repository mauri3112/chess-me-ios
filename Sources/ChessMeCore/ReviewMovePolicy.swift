import Foundation

/// Practical error estimates, not calibrated human winning probabilities.
/// The sigmoid and 5/10/15 point bands follow Lichess. ChessMe additionally
/// requires a near-equal-or-better to losing transition for a cp blunder.
public enum ReviewMovePolicy {
    public static let lastOpeningMove = 12
    public static func chance(_ score: Int) -> Double { 100 / (1 + exp(-0.00368208 * Double(score))) }
    public static func quality(bestScore: Int, playedScore: Int, isBest: Bool = false, mateThreshold: Int = 90_000) -> MoveQuality {
        if isBest { return .best }
        if bestScore < -mateThreshold && playedScore < -mateThreshold { return .good }
        if bestScore > mateThreshold && playedScore > mateThreshold { return .excellent }
        if playedScore < -mateThreshold {
            return bestScore >= -700 ? .blunder : bestScore >= -999 ? .mistake : .inaccuracy
        }
        let loss = max(0, chance(bestScore) - chance(playedScore))
        if loss >= 15 { return bestScore >= -100 && playedScore <= -100 ? .blunder : .mistake }
        if loss >= 10 { return .mistake }
        if loss >= 5 { return .inaccuracy }
        return loss <= 1 ? .excellent : .good
    }
    public static func permitsLesson(bestScore: Int, quality: MoveQuality, moveNumber: Int) -> Bool {
        bestScore > -700 && [.inaccuracy, .mistake, .blunder].contains(quality) &&
        (moveNumber > lastOpeningMove || quality == .blunder)
    }

    /// Refresh saved grades and lessons without discarding searched evidence.
    /// Old cloud losses preserve the raw score difference, including mate.
    /// Old device mate losses used a fixed penalty; keep their original grade
    /// when the best score cannot be reconstructed.
    public static func normalizing(_ review: GameAnalysis) -> GameAnalysis {
        let threshold = review.source == "cloud" ? 9900 : 90_000
        let assessments = review.moveAssessments?.map { value -> MoveAssessment in
            let sign = (try? ChessPosition(fen: value.positionFEN).sideToMove) == .black ? -1 : 1
            let actual = value.whiteScore * sign
            let before = value.bestWhiteScore.map { $0 * sign } ?? (review.source == "cloud" || abs(actual) < threshold ? actual + value.centipawnLoss : nil)
            let grade = review.source == "cloud" && value.completedDepth < 2 ? .unclassified : before.map { quality(bestScore: $0, playedScore: actual, isBest: value.playedMove == value.bestMove, mateThreshold: threshold) } ?? (value.engineQuality ?? value.quality)
            let engineGrade = (value.engineQuality ?? value.quality) == .brilliant && grade == .best ? MoveQuality.brilliant : grade
            return MoveAssessment(ply: value.ply, positionFEN: value.positionFEN, playedMove: value.playedMove, bestMove: value.bestMove,
                                  quality: value.quality == .book && engineGrade != .blunder ? .book : engineGrade,
                                  centipawnLoss: value.centipawnLoss, whiteScore: value.whiteScore, completedDepth: value.completedDepth,
                                  isProvisional: value.isProvisional, opening: value.opening,
                                  engineQuality: value.quality == .book || value.engineQuality != nil ? engineGrade : nil,
                                  bestWhiteScore: value.bestWhiteScore)
        }
        let findings = review.findings.compactMap { finding -> MoveFinding? in
            let evidence = assessments?.first { $0.positionFEN == finding.positionFEN && $0.playedMove == finding.playedMove }
            let grade = evidence.map { $0.engineQuality ?? $0.quality } ?? finding.quality
            if let evidence, let board = try? ChessPosition(fen: evidence.positionFEN) {
                let sign = board.sideToMove == .white ? 1 : -1
                let actual = evidence.whiteScore * sign
                let before = evidence.bestWhiteScore.map { $0 * sign } ?? (review.source == "cloud" || abs(actual) < threshold ? actual + evidence.centipawnLoss : nil)
                if let before, !permitsLesson(bestScore: before, quality: grade ?? .unclassified, moveNumber: finding.moveNumber) { return nil }
            }
            if finding.moveNumber <= lastOpeningMove && grade != .blunder { return nil }
            guard let grade else { return finding }
            return MoveFinding(id: finding.id, gameID: finding.gameID, gameLabel: finding.gameLabel, positionFEN: finding.positionFEN,
                               playedMove: finding.playedMove, bestMove: finding.bestMove, acceptedMoves: finding.acceptedMoves,
                               continuation: finding.continuation, centipawnLoss: finding.centipawnLoss, theme: finding.theme,
                               explanation: finding.explanation, hint: finding.hint, moveNumber: finding.moveNumber,
                               source: finding.source, isPuzzle: finding.isPuzzle, quality: grade)
        }
        return GameAnalysis(gameID: review.gameID, findings: findings, analyzedPlies: review.analyzedPlies, totalPlies: review.totalPlies,
                            source: review.source, completedAt: review.completedAt, engineVersion: review.engineVersion,
                            configurationID: review.configurationID, moveAssessments: assessments)
    }
}
