import Foundation
import Testing
@testable import ChessMeCore

struct GameClocksTests {
    private func replay(status: String = "resign", readings: [Int?], initial: Int = 300, increment: Int = 3) throws -> GameClockTimeline {
        let game = ChessGame(id: "clocktest", username: "You", white: "You", black: "Partner", playedAt: Date(), playerSide: .white,
                             moves: "e4 e5 Nf3 Nc6", status: status)
        return GameClockTimeline(data: GameClockData(initialSeconds: initial, incrementSeconds: increment, remainingCentiseconds: readings),
                                 positions: try GameReplay(game: game).positions, status: status)
    }

    @Test func clocksFollowEachPlayerAndUseCentisecondsWithIncrement() throws {
        let timeline = try replay(readings: [30_000, 30_000, 29_120, 28_450])
        #expect(timeline.snapshots[0].white == 30_000)
        #expect(timeline.snapshots[1].black == 30_000)
        #expect(timeline.snapshots[3].white == 29_120)
        #expect(timeline.snapshots[3].black == 30_000)
        #expect(timeline.moves[2].before == 30_000)
        #expect(timeline.moves[2].estimatedSpent == 1_180)
        #expect(timeline.moves[3].estimatedSpent == 1_850)
        #expect(timeline.moves[0].firstMoveUntimed)
        #expect(timeline.moves[0].estimatedSpent == nil)
        #expect(GameClockData.clockLabel(29_120) == "4:51")
        #expect(GameClockData.clockLabel(940) == "0:09.4")
        #expect(GameClockData.clockLabel(360_000) == "1:00:00")
        #expect(timeline.lastMove(for: .white, at: 0) == nil)
        #expect(timeline.lastMove(for: .black, at: 1) == nil)
        #expect(timeline.lastMove(for: .white, at: 3)?.estimatedSpent == 1_180)
        #expect(timeline.lastMove(for: .black, at: 3)?.firstMoveUntimed == true)
        #expect(timeline.lastMove(for: .white, at: 4)?.estimatedSpent == 1_180)
        #expect(timeline.lastMove(for: .black, at: 4)?.estimatedSpent == 1_850)
    }

    @Test func berserkStartingClocksAndMissingReadingsNeverInventTime() throws {
        let timeline = try replay(readings: [15_000, 30_000, nil, 28_450])
        #expect(timeline.snapshots[0].white == 15_000)
        #expect(timeline.snapshots[0].black == 30_000)
        #expect(timeline.snapshots[3].white == nil)
        #expect(timeline.moves[2].estimatedSpent == nil)
        let berserk = try replay(readings: [15_003, 30_003, 14_947, 30_299])
        #expect(berserk.moves[2].estimatedSpent == nil, "A modified starting clock does not establish the player's increment")
        #expect(berserk.moves[3].estimatedSpent == 4)
        let truncated = try replay(readings: [30_000, 30_000, 29_000])
        #expect(truncated.snapshots[4].black == nil)
        #expect(truncated.moves[3].estimatedSpent == nil)
        #expect(truncated.lastMove(for: .black, at: 4)?.estimatedSpent == nil, "Never reuse an older player's duration for a missing latest clock")
        #expect(GameClockData.clockLabel(nil) == "—")
    }

    @Test func matingMoveGetsNoIncrementAndAsyncTerminationIsNotAnotherMove() throws {
        let game = ChessGame(id: "clockmate", username: "You", white: "You", black: "Partner", playedAt: Date(), playerSide: .white,
                             moves: "f3 e5 g4 Qh4#", status: "mate")
        let positions = try GameReplay(game: game).positions
        let timeline = GameClockTimeline(data: GameClockData(initialSeconds: 300, incrementSeconds: 3,
                                                            remainingCentiseconds: [30_000, 30_000, 29_000, 28_000]), positions: positions, status: "mate")
        #expect(timeline.moves[3].estimatedSpent == 2_000)
        let resign = try replay(readings: [30_000, 30_000, 29_000, 28_000, 26_000])
        #expect(resign.snapshots.count == 5)
        #expect(resign.snapshots.last?.white == 29_000)
        #expect(resign.moves[3].estimatedSpent == 2_300)
    }

    @Test func addedTimeAndUnknownIncrementDoNotProduceFalseThinkingTimes() throws {
        let timeline = try replay(readings: [30_000, 30_000, 40_000, 29_000])
        #expect(timeline.moves[2].estimatedSpent == nil)
        let positions = try GameReplay(game: DemoContent.games()[0]).positions
        let unknown = GameClockTimeline(data: GameClockData(initialSeconds: nil, incrementSeconds: nil,
            remainingCentiseconds: [30_000, 30_000, 29_000]), positions: positions, status: "resign")
        #expect(unknown.moves[2].estimatedSpent == nil)
        #expect(unknown.moves[2].after == 29_000)
    }

    @Test func blackToMoveFENPreservesClockOwnership() throws {
        let game = ChessGame(id: "clockfen", username: "You", white: "Partner", black: "You", playedAt: Date(), playerSide: .black,
                             moves: "e5 Nf3 Nc6", initialFEN: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", status: "resign")
        let timeline = GameClockTimeline(data: GameClockData(initialSeconds: 300, incrementSeconds: 0, remainingCentiseconds: [20_000, 25_000, 19_000]),
                                         positions: try GameReplay(game: game).positions, status: "resign")
        #expect(timeline.snapshots[0].black == 20_000)
        #expect(timeline.snapshots[0].white == 25_000)
        #expect(timeline.moves[2].side == .black)
        #expect(timeline.moves[2].estimatedSpent == 1_000)
        #expect(timeline.lastMove(for: .black, at: 1)?.side == .black)
        #expect(timeline.lastMove(for: .white, at: 1) == nil)
        #expect(timeline.lastMove(for: .black, at: 3)?.estimatedSpent == 1_000)
    }

    @Test func pgnClockCommentsStayOnMainlineAndPreserveMissingValues() throws {
        let pgn = """
        [TimeControl "300+3"]
        [Result "1-0"]
        1.e4 { [%clk 0:04:58.25] } (1.d4 {[%clk 0:00:01]}) e5
        2.Nf3 { note [%clk 0:04:51] } Nc6 {[%clk 0:04:48]} 1-0
        """
        let document = try PGNDocument(pgn)
        #expect(document.moves == ["e4", "e5", "Nf3", "Nc6"])
        let data = try #require(document.clockData)
        #expect(data.remainingCentiseconds == [29_825, nil, 29_100, 28_800])
        #expect(data.initialSeconds == 300 && data.incrementSeconds == 3)
        let timeline = GameClockTimeline(data: data, positions: try document.replay(), status: "resign")
        #expect(timeline.moves[0].before == 30_000)
        #expect(timeline.moves[0].estimatedSpent == 475)
        #expect(timeline.moves[3].before == nil && timeline.moves[3].estimatedSpent == nil)
        #expect(try PGNDocument("1.e4 {[%clk 0:99:99]} e5 1-0").clockData == nil)
        #expect(try PGNDocument("[TimeControl \"40/7200:3600\"]\n1.e4 {[%clk 1:59:00]} e5 1-0").clockData?.incrementSeconds == nil)
        let lichess = try PGNDocument("[Site \"https://lichess.org/clock123\"]\n[TimeControl \"300+3\"]\n1.e4 {[%clk 0:05:00]} e5 {[%clk 0:05:00]} 1-0")
        let exportedData = try #require(lichess.clockData)
        #expect(exportedData.source == .lichess)
        #expect(GameClockTimeline(data: exportedData, positions: try lichess.replay(), status: "resign").moves[0].firstMoveUntimed)
    }

    @Test func legacyGamesDecodeAndAddingClocksDoesNotChangeTheMainline() throws {
        let json = Data(#"{"id":"legacy","username":"You","white":"You","black":"Partner","playedAt":0,"playerSide":"white","moves":"e4 e5","status":"resign"}"#.utf8)
        let game = try JSONDecoder().decode(ChessGame.self, from: json)
        #expect(game.clockData == nil && game.clockDataFetchedAt == nil)
        let upgraded = game.withClockData(GameClockData(initialSeconds: 300, incrementSeconds: 0, remainingCentiseconds: [30_000, 30_000]), fetchedAt: Date())
        #expect(upgraded.hasSameMainline(as: game))
        #expect(try JSONDecoder().decode(ChessGame.self, from: JSONEncoder().encode(upgraded)) == upgraded)
    }

    @Test func cachedHistorySurvivesAppendingAndSlicing() throws {
        let history = try MoveHistory(position: .initial).appending([ChessMove(uci: "e2e4"), ChessMove(uci: "e7e5"), ChessMove(uci: "g1f3")])
        #expect(history.notation(at: 1) == "1. e4")
        #expect(history.notation(at: 2) == "1… e5")
        #expect(history.leadIn(plies: 1).notation(at: 0) == "Start")
        #expect(history.leadIn(plies: 1).notation(at: 1) == "2. Nf3")
        #expect(history.notation(at: 999) == "Start")
    }
}
