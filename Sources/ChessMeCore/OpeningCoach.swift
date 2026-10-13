import Foundation

public struct OpeningOpportunity: Identifiable, Equatable, Sendable {
    public var id: String { positionFEN + " " + suggestedMove }
    public let positionFEN: String
    public let playedMove: String
    public let suggestedMove: String
    public let visits: Int
    public let mistakes: Int
    public let averageLoss: Double
    public let totalLoss: Int
    public let sampleLoss: Int
    public let sampleGameID: String
    public let source: String
    public var moveNumber: Int { (try? ChessPosition(fen: positionFEN).fullmoveNumber) ?? 1 }
    public var playedSAN: String { notation(playedMove) }
    public var suggestedSAN: String { notation(suggestedMove) }
    private func notation(_ uci: String) -> String {
        guard let board = try? ChessPosition(fen: positionFEN), let move = try? ChessMove(uci: uci) else { return uci }
        return (try? board.san(move)) ?? uci
    }
}

public struct OpeningReport: Sendable {
    public let username: String?
    public let eligibleGames: Int
    public let reviewedGames: Int
    public let requiredGames: Int
    public let opportunities: [OpeningOpportunity]
    public var isReady: Bool { reviewedGames >= requiredGames }
}

public enum OpeningCoach {
    public static let minimumGames = 30
    public static let minimumVisits = 5
    public static let lastOpeningMove = 10

    /// Only sufficiently reviewed, standard-start openings count towards the sample threshold.
    /// Positions are shared across transpositions and clocks, with one observation per game.
    public static func report(games: [ChessGame], analyses: [GameAnalysis], username: String? = nil) -> OpeningReport {
        var eligible = 0, reviewed = 0
        let player = username ?? games.filter { !$0.id.hasPrefix("demo-") }.max { $0.playedAt < $1.playedAt }?.username
        var observations: [String: [(game: ChessGame, assessment: MoveAssessment, source: String)]] = [:]
        let latest = Dictionary(grouping: analyses.filter { !($0.moveAssessments ?? []).isEmpty }, by: \.gameID).compactMapValues { $0.max { $0.completedAt < $1.completedAt } }
        let uniqueGames = Dictionary(grouping: games, by: \.id).compactMapValues(\.first)
        for game in uniqueGames.values {
            guard game.username.caseInsensitiveCompare(player ?? "") == .orderedSame,
                  game.isFinished, !game.id.hasPrefix("demo-"), let replay = try? GameReplay(game: game),
                  replay.positions.first?.repetitionKey == ChessPosition.initial.repetitionKey, !replay.moves.isEmpty else { continue }
            eligible += 1
            guard let savedAnalysis = latest[game.id] else { continue }
            let analysis = OpeningBook.shared.line(in: replay).annotating(savedAnalysis)
            let openingPlies = replay.moves.indices.filter { replay.positions[$0].sideToMove == game.playerSide && replay.positions[$0].fullmoveNumber <= lastOpeningMove }
            let assessments = Dictionary(grouping: analysis.moveAssessments ?? [], by: \.ply).compactMapValues(\.first)
            let valid = openingPlies.compactMap { ply -> MoveAssessment? in
                guard let value = assessments[ply], value.completedDepth >= 2,
                      value.playedMove == replay.moves[ply].uci,
                      let position = try? ChessPosition(fen: value.positionFEN), position == replay.positions[ply],
                      let best = try? ChessMove(uci: value.bestMove), position.legalMoves().contains(best) else { return nil }
                return value
            }
            guard valid.count == openingPlies.count else { continue }
            reviewed += 1
            var seen = Set<String>()
            for assessment in valid {
                let key = (try! ChessPosition(fen: assessment.positionFEN)).repetitionKey
                guard seen.insert(key).inserted else { continue }
                observations[key, default: []].append((game, assessment, analysis.source))
            }
        }
        guard reviewed >= minimumGames else {
            return OpeningReport(username: player, eligibleGames: eligible, reviewedGames: reviewed, requiredGames: minimumGames, opportunities: [])
        }
        let opportunities = observations.values.compactMap { values -> OpeningOpportunity? in
            guard values.count >= minimumVisits else { return nil }
            let errors = values.filter { $0.assessment.quality != .book && $0.assessment.centipawnLoss >= 100 && $0.assessment.bestMove != $0.assessment.playedMove }
            guard errors.count >= 3 else { return nil }
            let suggestions = Dictionary(grouping: values, by: { $0.assessment.bestMove })
            guard let best = suggestions.keys.sorted(by: { suggestions[$0]!.count == suggestions[$1]!.count ? $0 < $1 : suggestions[$0]!.count > suggestions[$1]!.count }).first,
                  Double(suggestions[best]!.count) / Double(values.count) >= 0.6,
                  let sample = errors.filter({ $0.assessment.bestMove == best }).sorted(by: { $0.assessment.centipawnLoss > $1.assessment.centipawnLoss }).first else { return nil }
            let total = values.reduce(0) { $0 + ($1.assessment.quality == .book ? 0 : min(1000, max(0, $1.assessment.centipawnLoss))) }
            let sources = Set(values.map(\.source)).sorted().joined(separator: " + ")
            return OpeningOpportunity(positionFEN: sample.assessment.positionFEN, playedMove: sample.assessment.playedMove,
                                      suggestedMove: best, visits: values.count, mistakes: errors.count,
                                      averageLoss: Double(total) / Double(values.count), totalLoss: total,
                                      sampleLoss: sample.assessment.centipawnLoss,
                                      sampleGameID: sample.game.id, source: sources)
        }.sorted { $0.totalLoss == $1.totalLoss ? $0.id < $1.id : $0.totalLoss > $1.totalLoss }
        return OpeningReport(username: player, eligibleGames: eligible, reviewedGames: reviewed, requiredGames: minimumGames, opportunities: Array(opportunities.prefix(5)))
    }
}
