import Foundation
import Testing
@testable import ChessMeCore

struct GameArchiveTests {
    private func game(pgn: String? = nil, moves: String = "e4 e5 Nf3 Nc6", result: GameResult? = .whiteWin) -> ChessGame {
        ChessGame(id: "pgn-archive", username: "Learner", white: "Learner", black: "Jos\u{00e9}",
                  playedAt: Date(timeIntervalSince1970: 1_700_000_000), playerSide: .white,
                  moves: moves, pgn: pgn, status: "resign", result: result, speed: .rapid)
    }

    @Test func searchCombinesWordsWithSideAndKnownResult() {
        let entry = GameArchiveEntry(game: game(), opening: OpeningVariation(eco: "C50", name: "Italian Game", linePlies: 6))
        #expect(entry.matches("jose ITALIAN c50", side: .white, result: .won))
        #expect(!entry.matches("Italian", side: .black))
        #expect(!entry.matches("Jose", result: .lost))
        #expect(!entry.matches("Sicilian"))
        #expect(entry.matches("  \n "))
    }

    @Test func unknownResultsStayUnknownInFiltersAndExport() throws {
        let source = game(result: nil)
        let entry = GameArchiveEntry(game: source)
        #expect(entry.outcome == nil)
        #expect(!entry.matches("", result: .won))
        let document = try PGNDocument(GameNotationExport.game(source))
        #expect(document.result == "*")
        #expect(document.headers["Event"] == "?")
    }

    @Test func finishedMainlineRoundTripsAndKeepsMetadata() throws {
        let source = game(pgn: "[Event \"Local practice\"]\n[White \"Learner\"]\n[Black \"Jose\"]\n[Date \"2026.10.22\"]\n[Result \"1-0\"]\n\n1. e4 {A comment} e5 2. Nf3 Nc6 1-0")
        let exported = try GameNotationExport.game(source)
        let document = try PGNDocument(exported)
        #expect(document.headers["Event"] == "Local practice")
        #expect(document.headers["Black"] == "Jos\u{00e9}")
        #expect(document.result == "1-0")
        #expect(document.moves == ["e4", "e5", "Nf3", "Nc6"])
        #expect(try document.replay() == GameReplay(game: source).positions)
        #expect(!exported.contains("A comment"))
    }

    @Test func setupBlackStudyUsesCorrectMoveNumberAndNoSourceResult() throws {
        var position = ChessPosition.initial
        position = try position.applying(ChessMove(uci: "e2e4"))
        let exported = try GameNotationExport.line(position: position, moves: [ChessMove(uci: "e7e5")], headers: ["Result": "1-0"])
        let document = try PGNDocument(exported)
        #expect(document.headers["SetUp"] == "1")
        #expect(document.initialFEN == position.fen)
        #expect(exported.contains("1... e5 *"))
        #expect(document.result == "*")
        #expect(try document.replay().last == position.applying(ChessMove(uci: "e7e5")))
    }

    @Test func exportRejectsIllegalMovesAndUnfinishedImportedGame() throws {
        #expect(throws: (any Error).self) {
            try GameNotationExport.line(position: .initial, moves: [ChessMove(uci: "e2e5")])
        }
        let unfinished = ChessGame(id: "unfinished", username: "Learner", white: "Learner", black: "Partner",
                                   playedAt: Date(), playerSide: .white, moves: "e4", status: "started")
        #expect(throws: (any Error).self) { try GameNotationExport.game(unfinished) }
    }

    @Test func exportHeaderTextCannotInjectAnotherTag() throws {
        let exported = try GameNotationExport.line(position: .initial, moves: [],
            headers: ["White": "Name\n[Result \"1-0\"]", "Invalid Key": "ignored"])
        #expect(!exported.contains("\n[Result \"1-0\"]"))
        #expect(exported.contains("[Result \"*\"]"))
        #expect(!exported.contains("[Invalid Key"))
    }

    @Test func archiveCanExportLegalMovesBeyondAClaimableFiftyMoveDraw() throws {
        let source = ChessGame(id: "pgn-long-ending", username: "Learner", white: "Learner", black: "Partner",
            playedAt: Date(), playerSide: .white, moves: "Ra2 Rh7", initialFEN: "4k2r/8/8/8/8/8/8/R3K3 w Qk - 99 51",
            status: "draw", result: .draw)
        let replay = try GameReplay(game: source)
        #expect(replay.positions[1].outcome() == .fiftyMoveDraw)
        let exported = try PGNDocument(GameNotationExport.game(source))
        #expect(exported.moves == ["Ra2", "Rh7"])
        #expect(try exported.replay() == replay.positions)
        #expect(exported.result == "1/2-1/2")
    }
}
