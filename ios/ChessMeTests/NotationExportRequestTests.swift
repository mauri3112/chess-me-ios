import XCTest
import ChessMeCore
@testable import ChessMe

final class NotationExportRequestTests: XCTestCase {
    private func fixtures() throws -> (ChessGame, SavedReviewLine) {
        let game = ChessGame(id: "source", username: "Learner", white: "Learner", black: "Partner",
                             playedAt: Date(), playerSide: .white, moves: "e4 e5", status: "resign")
        var replay = try GameReplay(game: game)
        try replay.play(ChessMove(uci: "d2d4"))
        return (game, try SavedReviewLine(game: game, replay: replay))
    }

    func testPreparedGameAndExploredGameExportsLoseAccessWhenGameIsDeleted() throws {
        let (game, line) = try fixtures()
        let generation = UUID()
        let request = NotationExportRequest(source: .game(game.id), generation: generation)
        XCTAssertTrue(request.isCurrent(generation: generation, games: [game], lines: [line]))
        XCTAssertFalse(request.isCurrent(generation: generation, games: [], lines: [line]))
    }

    func testSavedLineExportsSurviveOriginalGameRemovalButNotLineDeletion() throws {
        let (game, line) = try fixtures()
        let generation = UUID()
        let request = NotationExportRequest(source: .savedLine(line.id), generation: generation)
        XCTAssertTrue(request.isCurrent(generation: generation, games: [], lines: [line]))
        XCTAssertFalse(request.isCurrent(generation: generation, games: [game], lines: []))
        XCTAssertFalse(request.isCurrent(generation: generation, games: [], lines: []))
    }

    func testLateCompletionFromAnEarlierLibraryGenerationIsRejected() throws {
        let (game, line) = try fixtures()
        let oldGeneration = UUID(), newGeneration = UUID()
        for source in [NotationExportRequest.Source.game(game.id), .savedLine(line.id)] {
            let request = NotationExportRequest(source: source, generation: oldGeneration)
            XCTAssertFalse(request.isCurrent(generation: newGeneration, games: [game], lines: [line]))
        }
    }

    func testRetainedLineCanPrepareANewExportAfterGenerationChanges() throws {
        let (_, line) = try fixtures()
        let generation = UUID()
        let request = NotationExportRequest(source: .savedLine(line.id), generation: generation)
        XCTAssertTrue(request.isCurrent(generation: generation, games: [], lines: [line]))
        let replay = try GameReplay(game: line.replayGame())
        let notation = try GameNotationExport.line(position: replay.positions[0], moves: replay.moves)
        XCTAssertTrue(notation.contains("1. d4 *"))
    }
}
