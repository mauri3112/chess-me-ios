import Foundation
import ChessMeCore

struct PracticeRecord: Codable, Identifiable, Sendable {
    var id: String { findingID }
    let findingID: String
    var correctCount: Int
    var failedCount: Int
    var streak: Int? = 0
    var assistedCount: Int? = 0
    var dueAt: Date
    var lastPracticedAt: Date
}

struct CloudBatchRecord: Codable, Sendable {
    let accountID: String
    let gameIDs: [String]
    var submittedGameIDs: [String]
    let startedAt: Date
}

struct LibrarySnapshot: Codable, Sendable {
    var games: [ChessGame] = []
    var analyses: [GameAnalysis] = []
    var practice: [PracticeRecord] = []
    var isDemo = false
    var importedAt: Date?
    var skippedGames = 0
    var coverageNote: String?
    var analysisHistory: [GameAnalysis]?
    var favoriteGameIDs: [String]?
    var favoriteFindings: [MoveFinding]?
    var favoritePuzzles: [TrainingPuzzle]?
    var puzzleRecommendations: [PuzzleRecommendationSet]?
    var lastSyncedUsername: String?
    var puzzleRatingUsername: String?
    var lichessPuzzleRating: Int?
    var cloudReviews: [CloudReviewRecord]?
    var cloudReviewAccounts: [String]?
    var cloudEnabledAccounts: [String]?
    var cloudSubmissionKeys: [String: UUID]?
    var cloudBatch: CloudBatchRecord?
    var localAnalysisJobs: [LocalAnalysisJob]?
    var localAnalysisTimings: [LocalAnalysisTiming]?
    var review: ReviewLibrary?
}

final class LocalLibrary: @unchecked Sendable {
    private let url: URL
    // All file access uses one writer, including explicit saves and deletion.
    private let writer = DispatchQueue(label: "com.chessme.library-writer", qos: .utility)

    init(url: URL? = nil) throws {
        if let url { self.url = url; return }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ChessMe", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent("library.json")
    }

    func load() throws -> LibrarySnapshot {
        try writer.sync { try read() }
    }

    private func read() throws -> LibrarySnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return LibrarySnapshot() }
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: url))
        // Saved analysis must remain readable for charging tasks after the first
        // unlock, including a background relaunch while the screen is locked.
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        return snapshot
    }

    func save(_ snapshot: LibrarySnapshot) throws {
        try writer.sync { try write(snapshot) }
    }

    func saveInBackground(_ snapshot: LibrarySnapshot, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        writer.async {
            do { try self.write(snapshot); completion(.success(())) }
            catch { completion(.failure(error)) }
        }
    }

    private func write(_ snapshot: LibrarySnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func delete() throws {
        try writer.sync {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
}
