import Foundation
import Combine
import ChessMeCore

/// A small, transient catalogue preview. Only an explicit favorite saves a puzzle.
@MainActor
final class PuzzleTrainingCatalog: ObservableObject {
    static let themes = ["mate", "mateIn1", "mateIn2", "fork", "pin", "skewer", "hangingPiece", "defensiveMove", "promotion", "endgame", "discoveredAttack", "backRankMate", "exposedKing"]
    typealias Fetch = ([String: Double], Int, [String]) async throws -> [PuzzleMatch]
    @Published private(set) var puzzles: [TrainingPuzzle] = []
    @Published private(set) var isLoading = false
    @Published private(set) var notice: String?
    private var generation = UUID()
    private var recentPuzzleIDs: [String] = []
    private let fetch: Fetch

    init(service: PuzzleService = PuzzleService()) {
        fetch = { themes, rating, excluding in
            try await service.matches(themes: themes, rating: rating, excluding: excluding)
        }
    }
    init(fetch: @escaping Fetch) { self.fetch = fetch }

    func load(theme: String, rating: Int) async {
        let request = UUID()
        generation = request
        puzzles = []
        notice = nil
        guard Self.themes.contains(theme) else { return }
        isLoading = true
        defer { if generation == request { isLoading = false } }
        do {
            let matches = try await fetch([theme: 1], min(3000, max(400, rating)), recentPuzzleIDs)
            try Task.checkCancellation()
            guard generation == request else { return }
            puzzles = Self.unique(matches.map(\.puzzle)).prefix(3).map { $0 }
            recentPuzzleIDs = Array((recentPuzzleIDs + puzzles.map(\.id)).suffix(100))
            if puzzles.isEmpty { notice = "No puzzles found for this motif. Try another motif or target difficulty." }
        } catch is CancellationError {
            // A changed selection must not display an earlier request's results.
        } catch {
            guard generation == request else { return }
            notice = "The online catalogue is unavailable. Saved puzzles still work offline."
        }
    }

    func cancel() {
        generation = UUID()
        isLoading = false
        puzzles = []
        notice = nil
    }

    static func unique(_ puzzles: [TrainingPuzzle]) -> [TrainingPuzzle] {
        var seen = Set<String>()
        return puzzles.filter { seen.insert($0.id).inserted }
    }

    static func failed(in puzzles: [TrainingPuzzle], records: [PracticeRecord], attempts: [ReviewPracticeAttempt] = []) -> [TrainingPuzzle] {
        let recorded = records.filter { $0.failedCount > 0 }.map(\.findingID)
        let current = attempts.filter(\.hasMistake).compactMap(\.puzzleID).map { "lichess-puzzle-\($0)" }
        let failedIDs = Set(recorded + current)
        return unique(puzzles).filter { failedIDs.contains("lichess-puzzle-\($0.id)") }
    }
}
