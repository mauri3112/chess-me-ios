import Foundation
import Testing
@testable import ChessMeCore

struct OpeningBookTests {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private func game(_ moves: String, fen: String? = nil) -> ChessGame {
        ChessGame(id: "opening-test", username: "Learner", white: "Learner", black: "Partner", playedAt: Date(),
                  playerSide: .white, moves: moves, initialFEN: fen, status: "resign")
    }
    private func review(_ game: ChessGame, source: String = "device") throws -> GameAnalysis {
        let replay = try GameReplay(game: game)
        let assessments = replay.moves.indices.filter { replay.positions[$0].sideToMove == game.playerSide }.map { ply in
            MoveAssessment(ply: ply, positionFEN: replay.positions[ply].fen, playedMove: replay.moves[ply].uci,
                           bestMove: replay.positions[ply].legalMoves().first { $0 != replay.moves[ply] }!.uci,
                           quality: .mistake, centipawnLoss: 200, whiteScore: 200, completedDepth: 24, isProvisional: true)
        }
        let findings = assessments.map { value in
            MoveFinding(id: "\(game.id)-\(value.ply)", gameID: game.id, gameLabel: game.label, positionFEN: value.positionFEN,
                        playedMove: value.playedMove, bestMove: value.bestMove, acceptedMoves: [value.bestMove], continuation: [value.bestMove],
                        centipawnLoss: 200, theme: "Forcing moves", explanation: "Synthetic engine disagreement", hint: "Check",
                        moveNumber: replay.positions[value.ply].fullmoveNumber, source: source)
        }
        return GameAnalysis(gameID: game.id, findings: findings, analyzedPlies: assessments.count, totalPlies: assessments.count,
                            source: source, engineVersion: "saved-engine", configurationID: "saved-budget", moveAssessments: assessments)
    }

    @Test func completePinnedCatalogueCoversEveryECOVolume() throws {
        #expect(OpeningBook.shared.isAvailable)
        #expect(OpeningBook.shared.openingCount == 3865)
        #expect(OpeningBook.shared.maximumPly == 36)
        #expect(OpeningBook.shared.sourceCommit == "a6189a30dc273ccb21fc2536a9a2fefd5592a67a")
        #expect(try OpeningBook.licenseText().contains("CC0"))
        var codes = Set<String>(), count = 0
        for volume in ["a", "b", "c", "d", "e"] {
            let text = try String(contentsOf: root.appendingPathComponent("Vendor/LichessOpenings/\(volume).tsv"), encoding: .utf8)
            for line in text.split(separator: "\n").dropFirst() {
                codes.insert(String(line.split(separator: "\t")[0])); count += 1
            }
        }
        #expect(count == OpeningBook.shared.openingCount)
        #expect(codes.count == 500)
    }

    @Test func everyGeneratedPositionAndMoveAgreesWithTheSwiftChessRules() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/ChessMeCore/Resources/OpeningBook.json"))
        let index = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let positions = try #require(index["positions"] as? [String: [String: Any]])
        var edgeCount = 0
        for (key, record) in positions {
            let position = try ChessPosition(fen: key + " 0 1")
            #expect(position.repetitionKey == key)
            let moves = try #require(record["moves"] as? [String: Int])
            let legal = position.legalMoves()
            for (uci, ply) in moves {
                let move = try ChessMove(uci: uci)
                #expect(legal.contains(move), "Illegal catalogue move: \(key) \(uci)")
                #expect((0..<OpeningBook.shared.maximumPly).contains(ply))
                #expect(positions[try position.applying(move).repetitionKey] != nil)
                edgeCount += 1
            }
        }
        #expect(edgeCount == 8192)
    }

    @Test(arguments: [
        "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O", // Ruy Lopez
        "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6", // Najdorf
        "e4 e6 d4 d5 Nc3 Bb4", // French, Winawer
        "e4 c6 d4 d5 Nc3 dxe4 Nxe4", // Caro-Kann
        "e4 d5 exd5 Qxd5 Nc3 Qa5", // Scandinavian
        "e4 e5 f4 exf4 Nf3", // King's Gambit
        "e4 e5 Nf3 Nf6", // Petrov
        "d4 d5 c4 e6 Nc3 Nf6", // Queen's Gambit Declined
        "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6", // King's Indian
        "d4 Nf6 c4 e6 Nc3 Bb4", // Nimzo-Indian
        "d4 Nf6 c4 g6 Nc3 d5", // Gruenfeld
        "c4 e5 Nc3 Nf6", // English
        "d4 d5 Nf3 Nf6 Bf4" // London
    ])
    func majorOpeningsRecognizeEveryRecordedMove(_ moves: String) throws {
        let replay = try GameReplay(game: game(moves))
        let line = OpeningBook.shared.line(in: replay)
        #expect(line.moves.count == replay.moves.count, "Missing book move in \(moves)")
        #expect(line.opening != nil)
    }

    @Test func longVariationIsNotCutOffAtTenMovesAndShortLinesEndAtTheirOwnLength() throws {
        let moves = "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 O-O c3 d5 exd5 Nxd5 Nxe5 Nxe5 Rxe5 c6 d4 Bd6 Re1 Qh4 g3 Qh3 Be3 Bg4 Qd3 Rae8 Nd2 Re6 a4 Qh5"
        let replay = try GameReplay(game: game(moves))
        let line = OpeningBook.shared.line(in: replay)
        #expect(line.moves.count == 36)
        #expect(line.opening?.name.contains("Spassky") == true)
        let short = try GameReplay(game: game("e4 e5 h4 Nc6"))
        #expect(OpeningBook.shared.line(in: short).moves[0] != nil)
        #expect(OpeningBook.shared.line(in: short).moves[2] == nil)
        #expect(OpeningBook.shared.line(in: short).moves[3] == nil)
    }

    @Test func transpositionsMatchPositionsAndClocksDoNotChangeRecognition() throws {
        let a = try GameReplay(game: game("d4 d5 c4 e6 Nf3 Nf6 Nc3 Be7"))
        let b = try GameReplay(game: game("Nf3 d5 d4 Nf6 c4 e6 Nc3 Be7"))
        #expect(a.positions.last?.repetitionKey == b.positions.last?.repetitionKey)
        #expect(OpeningBook.shared.line(in: a).opening == OpeningBook.shared.line(in: b).opening)
        #expect(OpeningBook.shared.line(in: b).moves[7] != nil)
        let assessment = try #require(review(game("e4 e5 Nf3 Nc6")).moveAssessments?.last)
        let fields = assessment.positionFEN.split(separator: " ").prefix(4).joined(separator: " ")
        let changed = MoveAssessment(ply: assessment.ply, positionFEN: fields + " 17 2", playedMove: assessment.playedMove,
            bestMove: assessment.bestMove, quality: assessment.quality, centipawnLoss: 200, whiteScore: 200, completedDepth: 24, isProvisional: true)
        #expect(OpeningBook.shared.line(in: try GameReplay(game: game("e4 e5 Nf3 Nc6"))).recognizes(changed))
    }

    @Test func repeatedPositionsAndCustomStartsCannotRestartOpeningTheory() throws {
        let repeated = try GameReplay(game: game("Nf3 Nf6 Ng1 Ng8 e4 e5"))
        let line = OpeningBook.shared.line(in: repeated)
        #expect(line.moves[4] == nil && line.moves[5] == nil)
        let custom = try GameReplay(game: game("e4 e5 Nf3 Nc6", fen: "rnbqkbnr/ppppppp1/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"))
        #expect(OpeningBook.shared.line(in: custom).moves.isEmpty)
    }

    @Test func exploredBookVariationUsesItsOwnLineAndPreservesTheImportedGame() throws {
        var replay = try GameReplay(game: game("e4 e5 Nf3 Nc6 Bb5"))
        let original = replay.positions
        replay.navigate(to: 1)
        try replay.play(ChessMove(uci: "c7c5"))
        #expect(OpeningBook.shared.line(in: replay).opening?.name.contains("Ruy Lopez") == true)
        let explored = OpeningBook.shared.line(in: replay, includingVariation: true)
        #expect(explored.opening?.name == "Sicilian Defense")
        #expect(explored.moves[1] != nil)
        #expect(replay.positions == original && replay.index == 1)
    }

    @Test(arguments: ["device", "cloud"])
    func oldReviewsLoseBookMistakesWhileKeepingRealErrorsScoresAndProgress(_ source: String) throws {
        let game = game("e4 e5 h4 Nc6")
        let saved = try review(game, source: source)
        let line = OpeningBook.shared.line(in: try GameReplay(game: game))
        let result = line.annotating(saved)
        #expect(result.moveAssessments?.map(\.quality) == [.book, .mistake])
        #expect(result.moveAssessments?.first?.engineQuality == .mistake)
        #expect(result.findings.isEmpty, "Ordinary errors in the first 12 moves are not practice lessons")
        #expect(result.moveAssessments?.map(\.whiteScore) == saved.moveAssessments?.map(\.whiteScore))
        #expect(result.moveAssessments?.map(\.centipawnLoss) == saved.moveAssessments?.map(\.centipawnLoss))
        #expect(result.source == saved.source && result.engineVersion == saved.engineVersion)
        #expect(result.configurationID == saved.configurationID && result.completedAt == saved.completedAt)
        #expect(result.analyzedPlies == saved.analyzedPlies && result.totalPlies == saved.totalPlies)
        #expect(line.annotating(result) == result)
        #expect(try JSONDecoder().decode(GameAnalysis.self, from: JSONEncoder().encode(result)) == result)
    }

    @Test func namedTrapDoesNotHideVerifiedForcedMate() throws {
        let game = game("f3 e5 g4 Qh4#")
        let replay = try GameReplay(game: game)
        #expect(replay.positions.last?.outcome() == .checkmate(winner: .black))
        let saved = MoveAssessment(ply: 2, positionFEN: replay.positions[2].fen, playedMove: "g2g4", bestMove: "e2e4",
                                   quality: .blunder, centipawnLoss: 1000, whiteScore: -99_999, completedDepth: 24, isProvisional: true)
        let review = GameAnalysis(gameID: game.id, findings: [], analyzedPlies: 2, totalPlies: 2, moveAssessments: [saved])
        let line = OpeningBook.shared.line(in: replay)
        #expect(line.opening?.name.contains("Fool's Mate") == true)
        #expect(line.annotating(review).moveAssessments?.first?.quality == .blunder)
    }

    @Test func localAnalysisAndResumedCheckpointsApplyTheSameOpeningPolicy() throws {
        let game = game("e4 e5 Nf3 Nc6")
        let analyzer = LocalAnalyzer(options: AnalysisOptions(maximumDepth: 1, nodesPerMove: 500, maximumPositions: 1))
        let first = try analyzer.analyze(game: game)
        #expect(!first.isComplete && first.moveAssessments?.first?.quality == .book)
        let complete = try analyzer.analyze(game: game, previousAnalysis: first)
        #expect(complete.isComplete && complete.analyzedPlies == 2)
        #expect(complete.moveAssessments?.allSatisfy { $0.quality == .book } == true)
        #expect(complete.findings.isEmpty)
    }

    @Test func openingAdviceDoesNotTreatRepeatedTheoryAsARecurringMistake() throws {
        let games = (0..<30).map { index in
            ChessGame(id: "book-sample-\(index)", username: "Learner", white: "Learner", black: "Partner", playedAt: Date(),
                      playerSide: .white, moves: "e4 e5 Nf3 Nc6", status: "resign")
        }
        let report = OpeningCoach.report(games: games, analyses: try games.map { try review($0) }, username: "Learner")
        #expect(report.isReady && report.reviewedGames == 30)
        #expect(report.opportunities.isEmpty)
    }
}
