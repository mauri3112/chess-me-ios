import Foundation
import Testing
@testable import ChessMeCore

struct SavedLineRehearsalTests {
    @Test func importedPrefixCanContinuePastAnUnclaimedDraw() throws {
        let game = ChessGame(id: "long-ending", username: "Learner", white: "Learner", black: "Partner",
            playedAt: Date(), playerSide: .white, moves: "Ra2 Rh7 Rxa7",
            initialFEN: "4k2r/p7/8/8/8/8/8/R3K3 w Qk - 99 51", status: "resign")
        var replay = try GameReplay(game: game)
        replay.navigate(to: 3)
        try replay.play(ChessMove(uci: "h7h8"))
        try replay.play(ChessMove(uci: "a7a2"))
        let saved = try SavedReviewLine(game: game, replay: replay)
        var rehearsal = try SavedLineRehearsal(line: saved)
        let replied = rehearsal.playReply()
        #expect(replied)
        let result = rehearsal.submit(try ChessMove(uci: "a7a2"))
        #expect(result == .accepted && rehearsal.cleanCompletion)
    }

    private func line(side: Side = .white, fen: String? = nil, moves: [String] = ["e2e4", "e7e5", "g1f3"]) throws -> SavedReviewLine {
        let game = ChessGame(id: "rehearsal", username: "Learner", white: "White", black: "Black",
                             playedAt: Date(timeIntervalSince1970: 0), playerSide: side, moves: "",
                             initialFEN: fen, status: "resign")
        var replay = try GameReplay(game: game)
        for token in moves { try replay.play(ChessMove(uci: token)) }
        return try SavedReviewLine(game: game, replay: replay)
    }
    private func replacing(_ line: SavedReviewLine, _ key: String, _ value: Any) throws -> SavedReviewLine {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(line)) as? [String: Any])
        json[key] = value
        return try JSONDecoder().decode(SavedReviewLine.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func cleanCompletionWaitsForExplicitReplyAndRestartResetsRun() throws {
        let saved = try line()
        var run = try SavedLineRehearsal(line: saved)
        #expect(run.isPlayerTurn && run.totalPlayerMoves == 2)
        let result1 = run.submit(try ChessMove(uci: "e2e4"))
        #expect(result1 == .accepted)
        #expect(run.index == 1 && run.awaitingReply)
        let result2 = run.submit(try ChessMove(uci: "e7e5"))
        #expect(result2 == .unavailable)
        let result3 = run.playReply()
        #expect(result3 && run.index == 2)
        let result4 = run.playReply()
        #expect(!result4)
        let result5 = run.submit(try ChessMove(uci: "g1f3"))
        #expect(result5 == .accepted)
        #expect(run.isComplete && run.cleanCompletion && run.completedPlayerMoves == 2)
        let result6 = run.playReply()
        let result7 = run.reveal()
        #expect(!result6 && result7 == nil)
        run.restart()
        #expect(run.index == 0 && !run.assisted && run.isPlayerTurn)
        #expect(saved.moves == ["e2e4", "e7e5", "g1f3"])
    }

    @Test func blackStartsWithAutomaticWhiteMoveAndFinishesAfterReply() throws {
        var run = try SavedLineRehearsal(line: line(side: .black))
        #expect(run.awaitingReply && run.totalPlayerMoves == 1)
        let result8 = run.playReply()
        #expect(result8)
        #expect(run.isPlayerTurn)
        let result9 = run.submit(try ChessMove(uci: "e7e5"))
        #expect(result9 == .accepted)
        #expect(!run.isComplete && run.awaitingReply)
        let result10 = run.playReply()
        #expect(result10 && run.cleanCompletion)
    }

    @Test func wrongAndIllegalMovesLeavePositionUntouchedAndMarkRetry() throws {
        var run = try SavedLineRehearsal(line: line())
        let position = run.position
        let result11 = run.submit(try ChessMove(uci: "d2d4"))
        #expect(result11 == .wrongMove)
        let result12 = run.submit(ChessMove(from: -1, to: 99))
        #expect(result12 == .illegalMove)
        #expect(run.index == 0 && run.position == position && run.mistakes == 2 && run.assisted)
        _ = run.reveal(); _ = run.playReply(); _ = run.reveal()
        #expect(run.isComplete && !run.cleanCompletion)
    }

    @Test func hintAndRevealAreGuidedAndResetOnRestart() throws {
        var run = try SavedLineRehearsal(line: line())
        run.hint()
        #expect(run.hintSquare == ChessMove.square("e2") && run.usedHelp && run.index == 0)
        let result13 = run.reveal()
        #expect(result13?.uci == "e2e4" && run.hintSquare == nil)
        _ = run.playReply(); _ = run.reveal()
        #expect(run.isComplete && run.assisted)
        run.restart()
        #expect(!run.usedHelp && run.mistakes == 0 && run.hintSquare == nil)
    }

    @Test func underpromotionMustMatchTheSavedPromotion() throws {
        var run = try SavedLineRehearsal(line: line(fen: "7k/P7/8/8/8/8/8/7K w - - 0 1", moves: ["a7a8r"]))
        let result14 = run.submit(try ChessMove(uci: "a7a8q"))
        #expect(result14 == .wrongMove)
        let result15 = run.submit(try ChessMove(uci: "a7a8"))
        #expect(result15 == .illegalMove)
        let result16 = run.submit(try ChessMove(uci: "a7a8r"))
        #expect(result16 == .accepted)
        #expect(run.isComplete && run.position.squares[56]?.kind == .rook)
    }

    @Test func corruptAndUnboundedSerializedLinesFailClosed() throws {
        let saved = try line()
        for broken in [try replacing(saved, "moves", []),
                       try replacing(saved, "moves", ["e2e5"]),
                       try replacing(saved, "moves", Array(repeating: "e2e4", count: 513)),
                       try replacing(saved, "prefix", ["d2d4"]),
                       try replacing(saved, "positionFEN", "missing"),
                       try replacing(saved, "repetitionHistory", ["wrong"])] {
            #expect(throws: ChessError.self) { try SavedLineRehearsal(line: broken) }
        }
        #expect(throws: ChessError.self) { try SavedLineRehearsal(line: line(side: .black, moves: ["e2e4"])) }
    }
}
