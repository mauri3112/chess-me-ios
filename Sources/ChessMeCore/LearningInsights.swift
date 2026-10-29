import Foundation

/// Describes saved evidence only. It never infers archive completeness or an accuracy rating.
public struct LearningInsights: Sendable {
    public struct Results: Sendable {
        public var games = 0
        public var wins = 0
        public var draws = 0
        public var losses = 0
        public var known: Int { wins + draws + losses }
        public var unknown: Int { games - known }
        mutating func add(_ game: ChessGame) {
            games += 1
            switch game.finishedResult?.outcome(for: game.playerSide) {
            case .won: wins += 1
            case .draw: draws += 1
            case .lost: losses += 1
            case nil: break
            }
        }
    }
    public struct Breakdown: Identifiable, Sendable {
        public var id: String { title }
        public let title: String
        public var results: Results
    }
    public struct Estimate: Identifiable, Sendable {
        public var id: String { source }
        public let source: String
        public var games = 0
        public var completeGames = 0
        public var decisions = 0
        public var mistakes = 0
        public var blunders = 0
        public var openingDecisions = 0
        public var laterDecisions = 0
    }
    public let username: String?
    public var results = Results()
    public var colors: [Breakdown] = []
    public var speeds: [Breakdown] = []
    public var openings: [Breakdown] = []
    public var estimates: [Estimate] = []
    public var practiceAttempts = 0
    public var unaidedCompletions = 0
    public var assistedCompletions = 0
    public var revealedAttempts = 0
    public var otherAttempts = 0
    public var dueLessons = 0
    public var excludedGames = 0

    public init(games: [ChessGame], analyses: [GameAnalysis], review: ReviewLibrary,
                username requestedUsername: String? = nil, now: Date = Date()) {
        let real = games.filter { !$0.id.hasPrefix("demo-") && $0.isFinished }
        username = requestedUsername ?? real.max { $0.playedAt < $1.playedAt }?.username
        let matching = real.filter { $0.username.caseInsensitiveCompare(username ?? "") == .orderedSame }
        // Prefer the last saved version when an import enriches a game with result or clock metadata.
        var unique: [String: ChessGame] = [:]
        for game in matching { unique[game.id] = game }
        excludedGames = Set(real.map(\.id)).count - unique.count
        var colorRows: [String: Results] = [:], speedRows: [String: Results] = [:], openingRows: [String: Results] = [:]
        var sourceRows: [String: Estimate] = [:]
        let byGame = Dictionary(grouping: analyses.filter { ["device", "cloud"].contains($0.source) }, by: \.gameID)
        for game in unique.values {
            if Task.isCancelled { break }
            results.add(game)
            colorRows[game.playerSide.title, default: Results()].add(game)
            speedRows[game.timeControl.title, default: Results()].add(game)
            let history = try? MoveHistory(game: game)
            let opening = history.flatMap { OpeningBook.shared.line(positions: $0.positions, moves: $0.moves).opening?.name } ?? "Unclassified opening"
            openingRows[opening, default: Results()].add(game)
            // A device review and a cloud review remain independent estimates. History never adds a second vote.
            let available = byGame[game.id] ?? []
            let latest = Dictionary(grouping: available, by: \.source).compactMapValues { $0.max { $0.completedAt < $1.completedAt } }
            for (source, analysis) in latest {
                let assessed = GameReviewSummary(game: game, analysis: analysis, history: history).assessments
                guard !assessed.isEmpty else { continue }
                var row = sourceRows[source] ?? Estimate(source: source)
                row.games += 1
                if analysis.isComplete { row.completeGames += 1 }
                row.decisions += assessed.count
                row.mistakes += assessed.filter { $0.quality == .mistake }.count
                row.blunders += assessed.filter { $0.quality == .blunder }.count
                let early = assessed.filter { ((try? ChessPosition(fen: $0.positionFEN).fullmoveNumber) ?? Int.max) <= 10 }.count
                row.openingDecisions += early
                row.laterDecisions += assessed.count - early
                sourceRows[source] = row
            }
        }
        func rows(_ values: [String: Results]) -> [Breakdown] {
            values.map { Breakdown(title: $0.key, results: $0.value) }.sorted {
                $0.results.games == $1.results.games ? $0.title < $1.title : $0.results.games > $1.results.games
            }
        }
        colors = rows(colorRows); speeds = rows(speedRows); openings = rows(openingRows)
        estimates = sourceRows.values.sorted { $0.source < $1.source }
        let targets = Dictionary(review.targets.filter {
            !$0.finding.gameID.hasPrefix("demo-") && $0.username.caseInsensitiveCompare(username ?? "") == .orderedSame
        }.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        dueLessons = targets.values.filter { $0.ready(at: now) }.count
        let demoTargets = Set(review.targets.filter { $0.finding.gameID.hasPrefix("demo-") }.map(\.id))
        let attempts = Dictionary(review.attempts.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last }).values.filter { attempt in
            guard !demoTargets.contains(attempt.targetID), !(attempt.sourceGameID?.hasPrefix("demo-") ?? false) else { return false }
            if let owner = attempt.sourceUsername { return owner.caseInsensitiveCompare(username ?? "") == .orderedSame }
            if let gameID = attempt.sourceGameID { return unique[gameID] != nil }
            return targets[attempt.targetID] != nil
        }
        practiceAttempts = attempts.count
        unaidedCompletions = attempts.filter(\.cleanCompletion).count
        assistedCompletions = attempts.filter { $0.outcome == .completed && $0.assisted }.count
        revealedAttempts = attempts.filter { $0.outcome == .revealed }.count
        otherAttempts = practiceAttempts - unaidedCompletions - assistedCompletions - revealedAttempts
    }
}
