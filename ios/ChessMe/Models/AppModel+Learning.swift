import Foundation
import CryptoKit
import ChessMeCore

extension AppModel {
    func adoptPuzzleLevel(from account: LichessAccount, force: Bool = false) {
        guard automaticPuzzleLevel, !isDemo, account.perfs != nil else { return }
        let rating = account.suggestedPuzzleRating ?? 1200
        let sameUser = library.puzzleRatingUsername?.lowercased() == account.username.lowercased()
        // Preserve local progress while the provider's rating stays unchanged.
        guard force || !sameUser || library.lichessPuzzleRating != rating else { return }
        puzzleTargetRating = rating
        updateLibrary {
            $0.puzzleRatingUsername = account.username
            $0.lichessPuzzleRating = rating
        }
        if canSaveLibrary { persist() }
        schedulePuzzleMatches()
    }
    var favoriteGames: [ChessGame] { library.games.filter { (library.favoriteGameIDs ?? []).contains($0.id) }.sorted { $0.playedAt > $1.playedAt } }
    var favoriteFindings: [MoveFinding] { library.favoriteFindings ?? [] }
    var favoritePuzzles: [TrainingPuzzle] { library.favoritePuzzles ?? [] }
    var recommendedPuzzles: [TrainingPuzzle] {
        var seen = Set<String>()
        return (library.puzzleRecommendations ?? []).sorted { $0.matchedAt > $1.matchedAt }.flatMap(\.matches).map(\.puzzle).filter { seen.insert($0.id).inserted }
    }
    var nextRecommendedPuzzle: TrainingPuzzle? {
        recommendedPuzzles.first { puzzle in
            (library.practice.first { $0.findingID == "lichess-puzzle-\(puzzle.id)" }?.dueAt ?? .distantPast) <= Date()
        } ?? recommendedPuzzles.first
    }
    var puzzleFocus: [(theme: String, weight: Double)] {
        var weights: [String: Double] = [:]
        for finding in library.analyses.flatMap(\.findings) {
            let failed = library.practice.first { $0.findingID == finding.id }?.failedCount ?? 0
            let weight = min(10, max(1, finding.centipawnLoss / 100)) + Double(min(10, failed)) * 2
            for theme in PuzzleTheme.related(to: finding) { weights[theme, default: 0] += weight }
        }
        for puzzle in recommendedPuzzles {
            let failed = library.practice.first { $0.findingID == "lichess-puzzle-\(puzzle.id)" }?.failedCount ?? 0
            for theme in puzzle.themes where weights[theme] != nil { weights[theme, default: 0] += Double(min(10, failed)) * 2 }
        }
        return weights.map { ($0.key, $0.value) }.sorted { $0.weight == $1.weight ? $0.theme < $1.theme : $0.weight > $1.weight }
    }
    var puzzleMatchCoverage: (checked: Int, total: Int) {
        let ids = Set(library.games.filter { $0.isFinished && !$0.id.hasPrefix("demo-") }.map(\.id))
        let eligible = library.analyses.filter { $0.isComplete && !$0.findings.isEmpty && ids.contains($0.gameID) }
        let checked = eligible.filter { analysis in
            library.puzzleRecommendations?.contains { $0.gameID == analysis.gameID && $0.analysisSignature == Self.analysisSignature(analysis) && abs($0.rating - puzzleTargetRating) < 100 } == true
        }.count
        return (checked, eligible.count)
    }
    var openingReport: OpeningReport { OpeningCoach.report(games: library.games, analyses: library.analyses + (library.analysisHistory ?? []), username: authentication.account?.username) }
    func isFavorite(_ game: ChessGame) -> Bool { (library.favoriteGameIDs ?? []).contains(game.id) }
    func isFavorite(_ finding: MoveFinding) -> Bool { favoriteFindings.contains { $0.id == finding.id } }
    func isFavorite(_ puzzle: TrainingPuzzle) -> Bool { favoritePuzzles.contains { $0.id == puzzle.id } }
    func toggleFavorite(_ game: ChessGame) {
        var favorites = library.favoriteGameIDs ?? []
        if favorites.contains(game.id) { favorites.removeAll { $0 == game.id } } else { favorites.append(game.id) }
        updateLibrary { $0.favoriteGameIDs = favorites }; persist()
    }
    func toggleFavorite(_ finding: MoveFinding) {
        var favorites = favoriteFindings
        if isFavorite(finding) { favorites.removeAll { $0.id == finding.id } } else { favorites.append(finding) }
        updateLibrary { $0.favoriteFindings = favorites }; persist()
    }
    func toggleFavorite(_ puzzle: TrainingPuzzle) {
        var favorites = favoritePuzzles
        if isFavorite(puzzle) { favorites.removeAll { $0.id == puzzle.id } } else { favorites.append(puzzle) }
        updateLibrary { $0.favoritePuzzles = favorites }; persist()
    }
    func recommendation(for puzzle: TrainingPuzzle) -> (game: ChessGame, themes: [String])? {
        guard let set = library.puzzleRecommendations?.first(where: { $0.matches.contains { $0.puzzle.id == puzzle.id } }),
              let game = library.games.first(where: { $0.id == set.gameID }),
              let match = set.matches.first(where: { $0.puzzle.id == puzzle.id }) else { return nil }
        return (game, match.matchedThemes)
    }
    func recordPuzzle(_ puzzle: TrainingPuzzle, correct: Bool, assisted: Bool) {
        let id = "lichess-puzzle-\(puzzle.id)"
        var record = library.practice.first { $0.findingID == id } ?? PracticeRecord(findingID: id, correctCount: 0, failedCount: 0, dueAt: Date(), lastPracticedAt: Date())
        if correct && !assisted { record.correctCount += 1; record.streak = (record.streak ?? 0) + 1 }
        else if correct { record.assistedCount = (record.assistedCount ?? 0) + 1; record.streak = 0 }
        else { record.failedCount += 1; record.streak = 0 }
        record.dueAt = Date().addingTimeInterval(correct && !assisted ? min(30, pow(2.0, Double(min(max(0, (record.streak ?? 1) - 1), 5)))) * 86_400 : 86_400)
        record.lastPracticedAt = Date()
        updateLibrary { snapshot in
            snapshot.practice.removeAll { $0.findingID == id }; snapshot.practice.append(record)
        }
        if !isDemo && automaticPuzzleLevel && !assisted { puzzleTargetRating = min(3000, max(400, puzzleTargetRating + (correct ? 25 : -50))) }
        persist()
    }
    func schedulePuzzleMatches() {
        guard !isDemo, automaticPuzzleMatching, puzzleService.isConfigured, canSaveLibrary,
              !puzzlesLoading, puzzleMatchTask == nil else { return }
        let generation = puzzleMatchGeneration
        puzzleMatchTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshPuzzleMatches()
            guard generation == self.puzzleMatchGeneration else { return }
            self.puzzleMatchTask = nil
            // A game may finish analysis while the preceding request is in flight.
            if self.puzzleNotice == nil, self.puzzleMatchCoverage.checked < self.puzzleMatchCoverage.total {
                self.schedulePuzzleMatches()
            }
        }
    }
    func cancelPuzzleMatches() {
        puzzleMatchGeneration = UUID()
        puzzleMatchTask?.cancel(); puzzleMatchTask = nil
    }
    static func analysisSignature(_ analysis: GameAnalysis) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(analysis)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    func refreshPuzzleMatches(force: Bool = false) async {
        guard !isDemo, puzzleService.isConfigured, canSaveLibrary, !puzzlesLoading else { return }
        let generation = puzzleMatchGeneration
        puzzlesLoading = true; puzzleNotice = nil
        defer { puzzlesLoading = false }
        let rating = puzzleTargetRating
        let games = library.games.sorted { $0.playedAt > $1.playedAt }
        var refreshed = 0
        for game in games {
            guard !Task.isCancelled, generation == puzzleMatchGeneration else { return }
            guard game.isFinished, !game.id.hasPrefix("demo-"), let analysis = library.analyses.first(where: { $0.gameID == game.id }), analysis.isComplete, !analysis.findings.isEmpty else { continue }
            let signature = Self.analysisSignature(analysis)
            if !force && library.puzzleRecommendations?.contains(where: { $0.gameID == game.id && $0.analysisSignature == signature && abs($0.rating - rating) < 100 }) == true { continue }
            var themes: [String: Double] = [:]
            let global = Dictionary(uniqueKeysWithValues: puzzleFocus.map { ($0.theme, $0.weight) })
            for finding in analysis.findings {
                for theme in PuzzleTheme.related(to: finding) {
                    themes[theme, default: 0] += min(10, max(1, finding.centipawnLoss / 100)) + min(20, global[theme, default: 0] / 5)
                }
            }
            guard !themes.isEmpty else { continue }
            let ordered = themes.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            themes = Dictionary(uniqueKeysWithValues: ordered.prefix(12).map { ($0.key, min(100, $0.value)) })
            let excluding = (library.puzzleRecommendations ?? []).filter { $0.gameID != game.id }.flatMap(\.matches).map { $0.puzzle.id }
            do {
                let matches = try await puzzleService.matches(themes: themes, rating: rating, excluding: excluding)
                guard !Task.isCancelled, generation == puzzleMatchGeneration, !isDemo,
                      library.games.contains(where: { $0.id == game.id }),
                      library.analyses.first(where: { $0.gameID == game.id }).map(Self.analysisSignature) == signature else { continue }
                var sets = library.puzzleRecommendations ?? []
                sets.removeAll { $0.gameID == game.id }
                sets.append(PuzzleRecommendationSet(gameID: game.id, analysisSignature: signature, rating: rating, matches: matches, matchedAt: Date()))
                updateLibrary { $0.puzzleRecommendations = sets }; persist()
                refreshed += 1
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, generation == puzzleMatchGeneration else { return }
                puzzleNotice = error.localizedDescription; return
            }
            // Keep foreground refresh bounded. Remaining games are reported and handled on later refreshes.
            if refreshed >= 20 { puzzleNotice = "Matched 20 games. Refresh to continue with the remaining reviews."; break }
        }
    }
}
