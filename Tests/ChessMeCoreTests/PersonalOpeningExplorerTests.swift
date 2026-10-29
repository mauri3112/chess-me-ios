import Foundation
import Testing
@testable import ChessMeCore

struct PersonalOpeningExplorerTests {
    private func game(_ id: String, _ moves: String, account: String = "Learner", white: String = "Learner", black: String = "Partner", result: GameResult? = nil, speed: GameSpeed = .rapid, fen: String? = nil, status: String = "resign") -> ChessGame {
        ChessGame(id: id, username: account, white: white, black: black, playedAt: Date(), playerSide: white == account ? .white : .black,
                  moves: moves, initialFEN: fen, status: status, result: result, speed: speed)
    }
    @Test func groupsActualMovesAndKeepsUnknownDenominator() throws {
        let a = game("a", "e4 e5 Nf3", result: .whiteWin)
        var index = try PersonalOpeningExplorer(games: [a, a, game("b", "e4 c5", result: .draw), game("c", "d4 d5")], account: "learner")
        #expect(index.results.count == 3)
        #expect(index.results.known == 2)
        #expect(index.results.unknown == 1)
        #expect(index.duplicateCount == 1)
        #expect(index.branches.first?.san == "e4")
        #expect(index.branches.first?.results.count == 2)
        try index.advance(index.branches.first!.move)
        #expect(Set(index.gameIDs) == ["a", "b"])
        #expect(Set(index.branches.map(\.san)) == ["e5", "c5"])
        index.back()
        #expect(index.position == .initial)
        try index.advance(index.branches.first!.move)
        index.reset()
        #expect(index.path.isEmpty)
        #expect(index.position == .initial)
    }
    @Test func preservesMoveOrderAcrossTranspositions() throws {
        var index = try PersonalOpeningExplorer(games: [game("a", "Nf3 d5 d4 Nf6 c4"), game("b", "d4 Nf6 Nf3 d5 g3")], account: "Learner")
        for san in ["Nf3", "d5", "d4", "Nf6"] {
            try index.advance(index.branches.first { $0.san == san }!.move)
        }
        #expect(index.gameIDs == ["a"])
        #expect(index.branches.map(\.san) == ["c4"])
    }
    @Test func filtersAccountColorAndSpeedAndCountsResultsForAccount() throws {
        let games = [game("a", "e4 e5", result: .whiteWin),
                     game("b", "d4 d5", white: "Partner", black: "Learner", result: .blackWin, speed: .blitz),
                     game("c", "e4 e5", account: "Other", white: "Other")]
        let index = try PersonalOpeningExplorer(games: games, account: "Learner", side: .black, speed: .blitz)
        #expect(index.gameIDs == ["b"])
        #expect(index.results.wins == 1)
        #expect(index.accounts == ["Learner", "Other"])
    }
    @Test func excludesDemoSetupInvalidAndUnfinishedAndBoundsArchive() throws {
        let games = [game("demo-a", "e4 e5"), game("setup", "e4", fen: ChessPosition.initial.fen),
                     game("invalid", "e4 broken"), game("live", "e4", status: "started"), game("a", "e4 e5"), game("b", "d4 d5")]
        let index = try PersonalOpeningExplorer(games: games, account: "Learner", maximumGames: 1)
        #expect(index.results.count == 1)
        #expect(index.excludedDemo == 1)
        #expect(index.excludedSetup == 1)
        #expect(index.excludedInvalid == 2)
        #expect(index.deferred == 1)
        #expect(index.results.unknown == 1)
    }
    @Test func rejectsMovesOutsideSavedPrefix() throws {
        var index = try PersonalOpeningExplorer(games: [game("a", "e4 e5")], account: "Learner", maximumPly: 1)
        #expect(throws: ChessError.self) { try index.advance(ChessPosition.initial.move(san: "d4")) }
        try index.advance(index.branches[0].move)
        #expect(index.branches.isEmpty)
        #expect(index.gameIDs == ["a"])
    }
}
