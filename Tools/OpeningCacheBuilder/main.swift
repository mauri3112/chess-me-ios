import Foundation
import ChessMeCore

let lines = [
    "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O h3 Nb8 d4 Nbd7 Nbd2 Bb7 Bc2 Re8",
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6 f3 Be7 Qd2 O-O O-O-O Nbd7 g4 b5 g5 b4",
    "d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O Nf3 h6 Bh4 b6 cxd5 Nxd5 Bxe7 Qxe7 Nxd5 exd5 Rc1 Be6 Bd3 c5",
    "e4 e6 d4 d5 Nc3 Bb4 e5 c5 a3 Bxc3+ bxc3 Ne7",
    "e4 c6 d4 d5 Nc3 dxe4 Nxe4 Bf5 Ng3 Bg6 h4 h6",
    "e4 d5 exd5 Qxd5 Nc3 Qa5 d4 Nf6 Nf3 c6 Bc4 Bf5",
    "e4 e5 Nf3 Nf6 Nxe5 d6 Nf3 Nxe4 d4 d5 Bd3 Bd6",
    "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5",
    "d4 Nf6 c4 e6 Nc3 Bb4 e3 O-O Bd3 d5 Nf3 c5",
    "d4 d5 Nf3 Nf6 Bf4 e6 e3 c5 c3 Nc6 Nbd2 Bd6",
    "c4 e5 Nc3 Nf6 Nf3 Nc6 g3 d5 cxd5 Nxd5 Bg2 Nb6"
]
var profiles = [DeviceEngineConfiguration()]
var quick = DeviceEngineConfiguration()
quick.depth = 8; quick.secondsPerPosition = 1; quick.searchNodeLimit = 100_000
profiles.append(quick)
var entries: [OpeningEvaluationCache.Entry] = []
var seen = Set<String>()
var searches = 0
let started = ProcessInfo.processInfo.systemUptime
for line in lines {
    var board = ChessPosition.initial
    var history: [String] = []
    for san in line.split(separator: " ") {
        let played = try board.move(san: String(san))
        for profile in profiles {
            let key = profile.options.configurationID + board.fen + history.joined(separator: ";")
            if seen.insert(key).inserted {
                let evaluation = try LocalAnalyzer(options: profile.options).evaluate(position: board, repetitionHistory: history, requiredMove: played)
                searches += 1
                if evaluation.completedDepth >= profile.depth {
                    entries.append(.init(positionFEN: board.fen, history: history, configurationID: profile.options.configurationID, evaluation: evaluation))
                }
            }
        }
        history.append(board.repetitionKey)
        board = try board.applying(played)
    }
    print("\(entries.count) usable entries from \(searches) searches")
}
let output = CommandLine.arguments.dropFirst().first ?? "Sources/ChessMeCore/Resources/OpeningEvaluations.json"
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(OpeningEvaluationCache.Archive(entries: entries))
try data.write(to: URL(fileURLWithPath: output), options: .atomic)
print("Saved \(entries.count) entries, \(data.count) bytes, \(Int(ProcessInfo.processInfo.systemUptime - started)) seconds")
