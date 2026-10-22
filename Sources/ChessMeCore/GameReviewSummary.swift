import Foundation

/// Display only saved assessments that belong to this player's actual moves.
/// This is a move breakdown, not a new accuracy or performance rating.
public struct GameReviewSummary: Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case sound, book, inaccuracy, mistake, blunder
        public var title: String {
            switch self {
            case .sound: "Sound"
            case .book: "Book"
            case .inaccuracy: "Inaccuracies"
            case .mistake: "Mistakes"
            case .blunder: "Blunders"
            }
        }
        public func contains(_ quality: MoveQuality) -> Bool {
            switch self {
            case .sound: [.best, .excellent, .good, .brilliant].contains(quality)
            case .book: quality == .book
            case .inaccuracy: quality == .inaccuracy
            case .mistake: quality == .mistake
            case .blunder: quality == .blunder
            }
        }
    }
    public let assessments: [MoveAssessment]
    public let totalPlies: Int
    public var classifiedCount: Int { assessments.filter { $0.quality != .unclassified }.count }
    public func count(_ group: Group) -> Int { assessments.filter { group.contains($0.quality) }.count }

    public init(game: ChessGame, analysis: GameAnalysis?, history: MoveHistory?) {
        totalPlies = history?.moves.count ?? 0
        guard let analysis, analysis.gameID == game.id, let history else { assessments = []; return }
        var seen = Set<Int>()
        assessments = (analysis.moveAssessments ?? []).filter { value in
            guard history.moves.indices.contains(value.ply),
                  history.positions[value.ply].sideToMove == game.playerSide,
                  history.positions[value.ply].fen == value.positionFEN,
                  history.moves[value.ply].uci == value.playedMove,
                  value.completedDepth > 0 else { return false }
            return seen.insert(value.ply).inserted
        }.sorted { $0.ply < $1.ply }
    }
}

public extension ReviewBookmark {
    /// Reconcile both the cursor and visited count when a review changes while closed.
    func reconciled(with journey: ReviewJourney) -> Self {
        guard gameID == journey.gameID else { return self }
        var value = self
        let ids = Set(journey.moments.map(\.id))
        var seen = Set<String>()
        value.visited = visited.filter { ids.contains($0) && seen.insert($0).inserted }
        value.revision = journey.revision
        if let moment = journey.moments.first(where: { $0.id == momentID }) {
            value.step = min(max(0, step), max(0, moment.plies.count - 1))
        } else {
            value.momentID = nil; value.step = 0
            if place == .moment { value.place = .overview }
        }
        value.finished = finished && value.visited.count == ids.count
        return value
    }
}
