import Foundation
import Testing
@testable import ChessMeCore

/// Run alone in Release so engine tests and compilation do not distort timings:
/// CHESSME_REVIEW_BENCHMARK=1 swift test -c release --filter ReviewPerformanceTests
struct ReviewPerformanceTests {
    // The 125-ply finished game in Lichess's official game-export example.
    static let game = ChessGame(id: "q7ZvsdUF", username: "Lance5500", white: "Lance5500", black: "TryingHard87",
        playedAt: Date(timeIntervalSince1970: 1_514_505_150), playerSide: .white,
        moves: "d4 d5 c4 c6 Nc3 e6 e4 Nd7 exd5 cxd5 cxd5 exd5 Nxd5 Nb6 Bb5+ Bd7 Qe2+ Ne7 Nxb6 Qxb6 Bxd7+ Kxd7 Nf3 Qa6 Ne5+ Ke8 Qf3 f6 Nd3 Qc6 Qe2 Kf7 O-O Kg8 Bd2 Re8 Rac1 Nf5 Be3 Qe6 Rfe1 g6 b3 Bd6 Qd2 Kf7 Bf4 Qd7 Bxd6 Nxd6 Nc5 Rxe1+ Rxe1 Qc6 f3 Re8 Rxe8 Nxe8 Kf2 Nc7 Qb4 b6 Qc4+ Nd5 Nd3 Qe6 Nb4 Ne7 Qxe6+ Kxe6 Ke3 Kd6 g3 h6 Kd3 h5 Nc2 Kd5 a3 Nc6 Ne3+ Kd6 h4 Nd8 g4 Ne6 Ke4 Ng7 Nc4+ Ke6 d5+ Kd7 a4 g5 gxh5 Nxh5 hxg5 fxg5 Kf5 Nf4 Ne3 Nh3 Kg4 Ng1 Nc4 Kc7 Nd2 Kd6 Kxg5 Kxd5 f4 Nh3+ Kg4 Nf2+ Kf3 Nd3 Ke3 Nc5 Kf3 Ke6 Ke3 Kf5 Kd4 Ne6+ Kc4", status: "draw")

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CHESSME_REVIEW_BENCHMARK"] == "1"))
    func reviewRenderingWorkload() throws {
        var checksum = 0
        func measure(_ name: String, work: () throws -> Void) rethrows {
            var samples: [Double] = []
            for _ in 0..<20 {
                let start = ProcessInfo.processInfo.systemUptime
                try work()
                samples.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            }
            samples.sort()
            print("REVIEW_BENCHMARK \(name) median_ms=\(samples[10]) p95_ms=\(samples[18])")
        }
        try measure("prepare") { checksum += try GameReplay(game: Self.game).moves.count }
        try measure("legacy_render") {
            let history = try MoveHistory(game: Self.game)
            for index in 40..<52 { checksum += history.notation(at: index).count }
        }
        var replay = try GameReplay(game: Self.game)
        measure("cached_navigation_and_render") {
            replay.navigate(to: (replay.index + 1) % replay.positions.count)
            checksum += replay.position.fullmoveNumber
            for index in 40..<52 { checksum += replay.moveHistory.notation(at: index).count }
        }
        #expect(checksum > 0)
    }
}
