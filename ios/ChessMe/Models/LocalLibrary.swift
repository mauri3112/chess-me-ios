import Foundation
import ChessMeCore

struct PracticeRecord: Codable, Identifiable {
    var id: String { findingID }
    let findingID: String
    var correctCount: Int
    var failedCount: Int
    var streak: Int? = 0
    var assistedCount: Int? = 0
    var dueAt: Date
    var lastPracticedAt: Date
}

struct CloudBatchRecord: Codable {
    let accountID: String
    let gameIDs: [String]
    var submittedGameIDs: [String]
    let startedAt: Date
}

struct LibrarySnapshot: Codable {
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
}

final class LocalLibrary {
    private let url: URL

    init(url: URL? = nil) throws {
        if let url { self.url = url; return }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ChessMe", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent("library.json")
    }

    func load() throws -> LibrarySnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return LibrarySnapshot() }
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: url))
        // Saved analysis must remain readable for charging tasks after the first
        // unlock, including a background relaunch while the screen is locked.
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        return snapshot
    }

    func save(_ snapshot: LibrarySnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func delete() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
