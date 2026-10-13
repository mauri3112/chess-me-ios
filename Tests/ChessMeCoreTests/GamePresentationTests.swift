import Foundation
import Testing
@testable import ChessMeCore

struct GamePresentationTests {
    private func game(side: Side = .white, result: GameResult? = nil, pgn: String? = nil, status: String = "resign") -> ChessGame {
        ChessGame(id: "result-example", username: "Learner", white: "Learner", black: "Partner", playedAt: Date(),
                  playerSide: side, moves: "e4 e5 Nf3 Nc6", pgn: pgn, status: status, result: result)
    }
    @Test func resultsUseThePlayersSideAndPreserveUnknownResignations() {
        #expect(game(result: .whiteWin).finishedResult?.outcome(for: .white) == .won)
        #expect(game(side: .black, result: .whiteWin).finishedResult?.outcome(for: .black) == .lost)
        #expect(game(side: .black, result: .blackWin).finishedResult?.outcome(for: .black) == .won)
        #expect(game(result: .draw).finishedResult?.outcome(for: .white) == .draw)
        #expect(game().finishedResult == nil)
        #expect(game(status: "draw").finishedResult == .draw)
        #expect(game(result: .whiteWin, status: "started").finishedResult == nil)
    }
    @Test func oldPGNResultsRemainVisibleAndRecordedWinnerTakesPriority() throws {
        let pgn = "[Result \"0-1\"]\n\n1. e4 e5 2. Nf3 Nc6 0-1"
        let old = game(pgn: pgn)
        #expect(old.finishedResult == .blackWin)
        #expect(game(result: .whiteWin, pgn: pgn).finishedResult == .whiteWin)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object.removeValue(forKey: "result")
        let restored = try JSONDecoder().decode(ChessGame.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.finishedResult == .blackWin)
        #expect(restored.reviewLabel == "You vs Partner")
    }
    @Test func resultMetadataSurvivesClockBackfillAndMateIsOnlyInferredFromTheBoard() throws {
        let won = game(result: .whiteWin).withClockData(nil, fetchedAt: Date())
        #expect(won.result == .whiteWin)
        #expect(won.withResult(.blackWin).finishedResult == .blackWin)
        #expect(game(status: "mate").finishedResult == nil)
        let mate = ChessGame(id: "mate-result", username: "Learner", white: "Learner", black: "Partner", playedAt: Date(),
                             playerSide: .white, moves: "f3 e5 g4 Qh4#", status: "mate")
        #expect(mate.finishedResult == .blackWin)
    }
    @Test func historyBranchesFromEarlierMovesWithoutChangingTheImportedLine() throws {
        let history = try MoveHistory(game: game())
        let prefix = history.prefix(through: 1)
        let branch = try prefix.appending([ChessMove(uci: "c7c5")])
        #expect(prefix.moves.map(\.uci) == ["e2e4"])
        #expect(branch.moves.map(\.uci) == ["e2e4", "c7c5"])
        #expect(branch.notation(at: 2) == "1… c5")
        #expect(history.moves.map(\.uci) == ["e2e4", "e7e5", "g1f3", "b8c6"])
        #expect(history.prefix(through: -1).moves.isEmpty)
        #expect(history.prefix(through: 100) == history)
    }
}
