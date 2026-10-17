import Foundation
import Testing
@testable import ChessMeCore

struct ReviewTests {
    @Test func variationsNeverReplaceTheImportedGame() throws {
        var replay = try GameReplay(game: DemoContent.games()[0])
        let original = replay.positions
        try replay.play(ChessMove(uci: "d2d4"))
        try replay.play(ChessMove(uci: "d7d5"))
        #expect(replay.isVariation)
        #expect(replay.variationSAN == "d4 d5")
        #expect(replay.repetitionHistory.count == 2)
        #expect(replay.positions == original)
        replay.previous()
        #expect(replay.variationMoves.count == 1)
        replay.previous()
        #expect(!replay.isVariation)
        #expect(replay.position == .initial)
        replay.navigate(to: 4)
        #expect(replay.position == original[4])
        #expect(replay.repetitionHistory.count == 4)
        try replay.play(replay.position.legalMoves()[0])
        replay.navigate(to: 4)
        #expect(!replay.isVariation)
        #expect(replay.position == original[4])
        #expect(throws: ChessError.self) { try replay.play(ChessMove(uci: "a8a1")) }
    }

    @Test func evaluationSignAndMateDisplayFollowWhite() {
        let black = EvaluationDisplay(sideToMoveScore: 250, side: .black)
        #expect(black.whiteScore == -250)
        #expect(black.label == "-2.5")
        #expect(black.whiteFraction < 0.5)
        #expect(black.advantage == "Black ahead by 2.5 pawns")
        #expect(EvaluationDisplay(sideToMoveScore: 99_997, side: .white).label == "M2")
        #expect(EvaluationDisplay(sideToMoveScore: 99_999, side: .black).label == "−M1")
        #expect(EvaluationDisplay(sideToMoveScore: 0, side: .white).whiteFraction == 0.5)
    }

    @Test func hardwareAndLowPowerLimitsBoundSearch() {
        var settings = DeviceEngineConfiguration()
        settings.depth = 30; settings.memoryMB = 256; settings.nodesPerCandidate = 1_000_000
        settings.secondsPerPosition = 100; settings.topMoves = 8
        let small = settings.bounded(forMemoryMB: 2_048)
        #expect(small.depth == 30 && small.memoryMB == 8 && small.nodesPerCandidate == 100_000)
        #expect(small.secondsPerPosition == 15 && small.topMoves == 3)
        let lowPower = settings.bounded(forMemoryMB: 8_192, lowPower: true)
        #expect(lowPower.depth == 10 && lowPower.nodesPerCandidate == 50_000 && lowPower.secondsPerPosition == 3)
        settings.engine = .tactical
        #expect(settings.bounded(forMemoryMB: 8_192).depth == 8)
        #expect(settings.bounded(forMemoryMB: 8_192, lowPower: true).depth == 3)
    }

    @Test func progressiveSnapshotsContainOnlyCompleteIterations() throws {
        var snapshots: [PositionEvaluation] = []
        let position = try ChessPosition(fen: "7k/8/8/8/8/8/1r1Q4/7K b - - 0 1")
        let evaluation = try LocalAnalyzer(options: AnalysisOptions(maximumDepth: 3, nodesPerMove: 2_000)).evaluate(position: position, update: { snapshots.append($0) })
        #expect(snapshots.first?.completedDepth == 0)
        #expect(snapshots.last?.completedDepth == evaluation.completedDepth)
        for snapshot in snapshots {
            #expect(snapshot.moves.count == position.legalMoves().count)
            #expect(snapshot.moves.map(\.score) == snapshot.moves.map(\.score).sorted(by: >))
            for candidate in snapshot.moves {
                var board = position
                for move in candidate.continuation { board = try board.applying(move) }
            }
        }
    }

    @Test func aTimeBudgetKeepsCompletedWorkAndCancels() throws {
        let started = ProcessInfo.processInfo.systemUptime
        let result = try LocalAnalyzer(options: AnalysisOptions(maximumDepth: 8, nodesPerMove: 100_000, timeLimitSeconds: 0.03)).evaluate(position: .initial)
        #expect(ProcessInfo.processInfo.systemUptime - started < 1)
        #expect(result.limit == "Time budget reached")
        #expect(result.completedDepth < 8)
        #expect(result.moves.count == 20)
        #expect(throws: ChessError.cancelled) { try LocalAnalyzer().evaluate(position: .initial, cancellation: { true }) }
    }

    @Test func allExaminedPlayerMovesGetEstimatedLabels() throws {
        let game = DemoContent.games()[0]
        let analyzer = LocalAnalyzer(options: AnalysisOptions(maximumDepth: 1, nodesPerMove: 800))
        let result = try analyzer.analyze(game: game)
        let assessments = try #require(result.moveAssessments)
        #expect(assessments.count == result.analyzedPlies)
        let missedMate = try #require(assessments.first { $0.ply == 6 })
        #expect(missedMate.playedMove == "h5h7")
        #expect(missedMate.quality == .blunder, "Losing the queen instead of mating crosses into a losing game")
        #expect(missedMate.isProvisional)
        #expect(result.configurationID == analyzer.options.configurationID)
        #expect(assessments.allSatisfy { $0.quality != .brilliant })
        #expect(MoveQuality.estimated(loss: 0) == .excellent)
        #expect(MoveQuality.estimated(loss: 30) == .good)
        #expect(MoveQuality.estimated(loss: 80) == .inaccuracy)
        #expect(MoveQuality.estimated(loss: 120) == .mistake)
        #expect(MoveQuality.estimated(loss: 300) == .blunder)
    }

    @Test func checkpointsCannotMixSearchSettingsAndLegacyLibrariesDecode() throws {
        let game = DemoContent.games()[0]
        let checkpoint = try LocalAnalyzer(options: AnalysisOptions(maximumDepth: 1, maximumPositions: 1)).analyze(game: game)
        #expect(throws: ChessError.self) { try LocalAnalyzer(options: AnalysisOptions(maximumDepth: 2)).analyze(game: game, previousAnalysis: checkpoint) }
        let legacy = Data("{\"gameID\":\"old\",\"findings\":[],\"analyzedPlies\":1,\"totalPlies\":1,\"source\":\"device\",\"completedAt\":0,\"engineVersion\":\"local-tactical-v1\"}".utf8)
        let decoded = try JSONDecoder().decode(GameAnalysis.self, from: legacy)
        #expect(decoded.moveAssessments == nil && decoded.configurationID == nil)
    }
}
