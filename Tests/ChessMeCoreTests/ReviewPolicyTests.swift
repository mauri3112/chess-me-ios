import Foundation
import Testing
@testable import ChessMeCore

struct ReviewPolicyTests {
    @Test(arguments: [(-2000, -2700, MoveQuality.excellent), (0, -300, .blunder), (400, 100, .mistake),
                      (-400, -99999, .blunder), (-2000, -99999, .inaccuracy), (-99990, -99999, .good),
                      (-150, -800, .mistake), (100, 100, .excellent),
                      (-100, -400, .blunder), (-101, -400, .mistake), (300, -99, .mistake), (-700, -99999, .blunder), (-701, -99999, .mistake)])
    func practicalGrades(best: Int, played: Int, expected: MoveQuality) {
        #expect(ReviewMovePolicy.quality(bestScore: best, playedScore: played) == expected)
    }
    @Test func openingAndLostPositionLessonGates() {
        #expect(!ReviewMovePolicy.permitsLesson(bestScore: -2000, quality: .mistake, moveNumber: 20))
        #expect(!ReviewMovePolicy.permitsLesson(bestScore: 100, quality: .mistake, moveNumber: 2))
        #expect(ReviewMovePolicy.permitsLesson(bestScore: 100, quality: .mistake, moveNumber: 13))
        #expect(ReviewMovePolicy.permitsLesson(bestScore: -400, quality: .blunder, moveNumber: 2))
        #expect(!ReviewMovePolicy.permitsLesson(bestScore: -700, quality: .blunder, moveNumber: 20))
    }
    @Test(arguments: [Side.white, Side.black])
    func savedReviewRegradingUsesMoverPerspective(side: Side) throws {
        let board = try ChessPosition(fen: side == .white ? "7k/8/8/8/8/8/8/K7 w - - 0 20" : "7k/8/8/8/8/8/8/K7 b - - 0 20")
        let moves = board.legalMoves()
        let sign = side == .white ? 1 : -1
        let assessment = MoveAssessment(ply: 38, positionFEN: board.fen, playedMove: moves[1].uci, bestMove: moves[0].uci,
                                        quality: .blunder, centipawnLoss: 700, whiteScore: -2700 * sign, completedDepth: 21, isProvisional: true)
        let finding = MoveFinding(id: "lost", gameID: "game", gameLabel: "Game", positionFEN: board.fen,
                                  playedMove: moves[1].uci, bestMove: moves[0].uci, acceptedMoves: [moves[0].uci], continuation: [moves[0].uci],
                                  centipawnLoss: 700, theme: "Material loss", explanation: "Old grade", hint: "", moveNumber: 20)
        let saved = GameAnalysis(gameID: "game", findings: [finding], analyzedPlies: 1, totalPlies: 1, moveAssessments: [assessment])
        let result = ReviewMovePolicy.normalizing(saved)
        #expect(result.findings.isEmpty)
        #expect(result.moveAssessments?.first?.quality == .excellent)
        #expect(result.analyzedPlies == 1 && result.completedAt == saved.completedAt)
        #expect(ReviewMovePolicy.normalizing(result) == result)
    }
    @Test func oldCloudMateEvidenceCanRecoverAnAlreadyLostPosition() throws {
        let board = try ChessPosition(fen: "7k/8/8/8/8/8/8/K7 w - - 0 20")
        let moves = board.legalMoves()
        let evidence = MoveAssessment(ply: 38, positionFEN: board.fen, playedMove: moves[1].uci, bestMove: moves[0].uci,
                                      quality: .blunder, centipawnLoss: 7999, whiteScore: -9999, completedDepth: 21, isProvisional: false)
        let finding = MoveFinding(id: "old-mate", gameID: "game", gameLabel: "Game", positionFEN: board.fen,
                                  playedMove: moves[1].uci, bestMove: moves[0].uci, acceptedMoves: [moves[0].uci], continuation: [moves[0].uci],
                                  centipawnLoss: 7999, theme: "King safety", explanation: "Old grade", hint: "", moveNumber: 20, source: "cloud")
        let saved = GameAnalysis(gameID: "game", findings: [finding], analyzedPlies: 1, totalPlies: 1, source: "cloud", moveAssessments: [evidence])
        let result = ReviewMovePolicy.normalizing(saved)
        #expect(result.findings.isEmpty)
        #expect(result.moveAssessments?.first?.quality == .inaccuracy)
    }

    @Test func speedAndLegacyMetadata() throws {
        #expect(GameSpeed.from(seconds: 60, increment: 1) == .bullet)
        #expect(GameSpeed.from(seconds: 180, increment: 0) == .blitz)
        #expect(GameSpeed.from(seconds: 300, increment: 5) == .rapid)
        #expect(GameSpeed.from(seconds: 1800, increment: 0) == .classical)
        #expect(GameSpeed.from(seconds: Int.max, increment: Int.max) == .unknown)
        #expect(GameSpeed.from(seconds: -1, increment: 0) == .unknown)
        let game = ChessGame(id: "game", username: "Me", white: "Me", black: "Them", playedAt: Date(), playerSide: .white,
                             moves: "e4 e5", speed: .rapid)
        #expect(game.withClockData(nil, fetchedAt: Date()).withResult(.whiteWin).timeControl == .rapid)
        #expect(GameSpeedFilter.rapid.includes(game) && !GameSpeedFilter.bullet.includes(game))
        #expect(try JSONDecoder().decode(ChessGame.self, from: JSONEncoder().encode(game)).speed == .rapid)
    }
    @Test func bundledOpeningEvidenceSkipsSearchAndHonorsCancellation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/ChessMeCore/Resources/OpeningEvaluations.json"))
        let archive = try JSONDecoder().decode(OpeningEvaluationCache.Archive.self, from: data)
        #expect(OpeningEvaluationCache.shared.count >= 100)
        let options = DeviceEngineConfiguration().options
        let entry = try #require(archive.entries.first { $0.configurationID == options.configurationID })
        let board = try ChessPosition(fen: entry.positionFEN)
        let played = try #require(entry.evaluation.moves.first?.move)
        let result = try LocalAnalyzer(options: options).evaluate(position: board, repetitionHistory: entry.history, requiredMove: played)
        #expect(result.completedDepth >= 21 && result.nodes == 0)
        #expect(result.limit == "Precomputed opening analysis")
        #expect(throws: ChessError.cancelled) {
            try LocalAnalyzer(options: options).evaluate(position: board, repetitionHistory: entry.history, requiredMove: played, cancellation: { true })
        }
    }

    @Test func openingCacheRequiresExactEvidenceAndLegalLines() throws {
        let board = ChessPosition.initial
        let move = try board.move(san: "e4")
        let options = DeviceEngineConfiguration().options
        let result = PositionEvaluation(moves: [MoveEvaluation(move: move, score: 25, continuation: [move])], completedDepth: 21, nodes: 123)
        let entry = OpeningEvaluationCache.Entry(positionFEN: board.fen, history: [], configurationID: options.configurationID, evaluation: result)
        func cache(_ archive: OpeningEvaluationCache.Archive) throws -> OpeningEvaluationCache {
            OpeningEvaluationCache(data: try JSONEncoder().encode(archive))
        }
        let valid = try cache(.init(entries: [entry]))
        #expect(valid.evaluation(position: board, history: [], options: options, requiredMove: move)?.nodes == 0)
        #expect(valid.evaluation(position: board, history: [], options: options, requiredMove: try board.move(san: "d4")) == nil)
        #expect(valid.evaluation(position: board, history: [board.repetitionKey], options: options, requiredMove: move) == nil)
        var deeper = options; deeper.maximumDepth = 24
        #expect(valid.evaluation(position: board, history: [], options: deeper, requiredMove: move) == nil)
        #expect(try cache(.init(entries: [entry], engineVersion: "different-network")).count == 0)
        let changedClock = try ChessPosition(fen: board.repetitionKey + " 1 1")
        #expect(valid.evaluation(position: changedClock, history: [], options: options, requiredMove: move) == nil)
        let bad = OpeningEvaluationCache.Entry(positionFEN: board.fen, history: [], configurationID: options.configurationID,
            evaluation: PositionEvaluation(moves: [MoveEvaluation(move: move, score: 0, continuation: [move, move])], completedDepth: 21, nodes: 1))
        #expect(try cache(.init(entries: [bad])).evaluation(position: board, history: [], options: options, requiredMove: move) == nil)
    }
}
