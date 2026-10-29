import Foundation
import ChessMeCore

/// A saved-line snapshot remains usable independently of its original game.
struct NotationExportRequest: Equatable {
    enum Source: Equatable {
        case game(String)
        case savedLine(String)

        func isRetained(games: [ChessGame], lines: [SavedReviewLine]) -> Bool {
            switch self {
            case .game(let id): return games.contains { $0.id == id }
            case .savedLine(let id): return lines.contains { $0.id == id }
            }
        }
    }
    let source: Source
    let generation: UUID

    func isCurrent(generation: UUID, games: [ChessGame], lines: [SavedReviewLine]) -> Bool {
        self.generation == generation && source.isRetained(games: games, lines: lines)
    }
}
