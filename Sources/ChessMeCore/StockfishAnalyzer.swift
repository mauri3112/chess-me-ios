// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CStockfish
#if os(iOS)
import os
#endif

public enum StockfishEngine {
    public static let version = "stockfish-19-1a298aa575a0-chessme-v1"
    public static let sourceURL = URL(string: "https://github.com/official-stockfish/Stockfish/tree/edb0d9db6731067ec50ce619ff372b463bc4dd5d")!
    public static var license: String {
        guard let url = Bundle.module.url(forResource: "StockfishLicense", withExtension: "txt", subdirectory: "Resources") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    public static func trimMemory() { chessme_stockfish_trim_memory() }
    /// Advisory app headroom, queried afresh before each search. Physical device
    /// RAM is not the amount iOS lets this process allocate.
    public static var availableMemoryMegabytes: Int? {
        #if os(iOS) && !targetEnvironment(simulator)
        return Int(os_proc_available_memory() / 1_048_576)
        #else
        // Simulator processes do not have the physical iOS app memory limit.
        // The API can return zero there even when allocation is possible.
        return nil
        #endif
    }
}

enum StockfishError: LocalizedError {
    case missingNetwork, invalidPosition, invalidHistory, noCompletedSearch, failed
    var errorDescription: String? {
        switch self {
        case .missingNetwork: return "Stockfish's bundled network could not be loaded."
        case .invalidPosition: return "Stockfish could not read this position."
        case .invalidHistory: return "The position history could not be reconstructed safely."
        case .noCompletedSearch: return "The search limit was reached before comparable results. Try more time."
        case .failed: return "Stockfish could not finish this search."
        }
    }
}

private final class StockfishCallbacks {
    struct Payload: Decodable {
        struct Line: Decodable { let score: Int; let moves: [String] }
        let depth: Int
        let nodes: Int
        let elapsedMilliseconds: Int?
        let limit: String
        let lines: [Line]
    }
    let position: ChessPosition
    let cancellation: () -> Bool
    let update: (PositionEvaluation) -> Void
    var result: PositionEvaluation?
    init(position: ChessPosition, cancellation: @escaping () -> Bool, update: @escaping (PositionEvaluation) -> Void) {
        self.position = position; self.cancellation = cancellation; self.update = update
    }
    func receive(_ text: UnsafePointer<CChar>) {
        guard let value = try? JSONDecoder().decode(Payload.self, from: Data(String(cString: text).utf8)) else { return }
        let lines = value.lines.compactMap { line -> MoveEvaluation? in
            var board = position
            var moves: [ChessMove] = []
            for token in line.moves {
                guard let move = try? ChessMove(uci: token), let next = try? board.applying(move) else { break }
                moves.append(move); board = next
            }
            guard let first = moves.first else { return nil }
            return MoveEvaluation(move: first, score: line.score, continuation: moves)
        }
        let snapshot = PositionEvaluation(moves: lines, completedDepth: value.depth, nodes: value.nodes,
                                          elapsedSeconds: value.elapsedMilliseconds.map { Double($0) / 1_000 },
                                          limit: value.limit.isEmpty ? nil : value.limit)
        result = snapshot
        update(snapshot)
    }
}

struct StockfishAnalyzer {
    let options: AnalysisOptions

    /// Reconstruct real moves, rather than loading unrelated FENs and losing
    /// repetition history. The final fifty-move counter must also match.
    static func nativePosition(_ position: ChessPosition, history: [String]) throws -> (fen: String, moves: String) {
        guard let first = history.first else { return (position.fen, "") }
        let blackMoves = history.filter { $0.split(separator: " ").dropFirst().first == "b" }.count
        let fen = "\(first) \(max(0, position.halfmoveClock - history.count)) \(max(1, position.fullmoveNumber - blackMoves))"
        var board = try ChessPosition(fen: fen)
        var moves: [String] = []
        for key in Array(history.dropFirst()) + [position.repetitionKey] {
            guard let move = board.legalMoves().first(where: { board.applyingUnchecked($0).repetitionKey == key }) else {
                throw StockfishError.invalidHistory
            }
            moves.append(move.uci); board = board.applyingUnchecked(move)
        }
        guard board.repetitionKey == position.repetitionKey, board.halfmoveClock == position.halfmoveClock,
              board.fullmoveNumber == position.fullmoveNumber else { throw StockfishError.invalidHistory }
        return (fen, moves.joined(separator: " "))
    }

    func evaluate(position: ChessPosition, repetitionHistory: [String], requiredMove: ChessMove?,
                  cancellation: @escaping () -> Bool, update: @escaping (PositionEvaluation) -> Void) throws -> PositionEvaluation {
        if cancellation() { throw ChessError.cancelled }
        guard position.outcome(repetitionCount: repetitionHistory.filter { $0 == position.repetitionKey }.count + 1) == .ongoing else {
            return PositionEvaluation(moves: [], completedDepth: 0, nodes: 0)
        }
        guard requiredMove == nil || position.legalMoves().contains(requiredMove!) else { throw StockfishError.invalidPosition }
        if let cached = OpeningEvaluationCache.shared.evaluation(position: position, history: repetitionHistory, options: options, requiredMove: requiredMove) {
            if cancellation() { throw ChessError.cancelled }
            update(cached)
            return cached
        }
        guard let cacheMB = LocalAnalysisMemoryPolicy.cacheMegabytes(requested: options.memoryMegabytes,
                                                                   availableToAppMB: StockfishEngine.availableMemoryMegabytes) else {
            throw LocalAnalysisResourceError.insufficientMemory
        }
        guard let network = Bundle.module.url(forResource: "nn-1a298aa575a0", withExtension: "nnue", subdirectory: "Resources") else {
            throw StockfishError.missingNetwork
        }
        let root = try Self.nativePosition(position, history: repetitionHistory)
        let callbacks = StockfishCallbacks(position: position, cancellation: cancellation, update: update)
        let context = Unmanaged.passUnretained(callbacks).toOpaque()
        let code = chessme_stockfish_analyze(network.path, root.fen, root.moves, requiredMove?.uci ?? "",
            Int32(options.maximumDepth), Int32(cacheMB), Int32((options.timeLimitSeconds ?? 3) * 1_000),
            UInt64(options.searchNodeLimit ?? options.nodesPerMove * max(1, position.legalMoves().count)),
            Int32(options.engineThreads), context,
            { pointer in
                guard let pointer else { return 1 }
                return Unmanaged<StockfishCallbacks>.fromOpaque(pointer).takeUnretainedValue().cancellation() ? 1 : 0
            }, { text, pointer in
                guard let text, let pointer else { return }
                Unmanaged<StockfishCallbacks>.fromOpaque(pointer).takeUnretainedValue().receive(text)
            })
        switch code {
        case 0:
            guard let result = callbacks.result, result.completedDepth > 0, !result.moves.isEmpty,
                  requiredMove == nil || result.moves.contains(where: { $0.move == requiredMove }) else { throw StockfishError.noCompletedSearch }
            return result
        case 1: throw ChessError.cancelled
        case 2: throw StockfishError.missingNetwork
        case 3: throw StockfishError.invalidPosition
        case 4: throw StockfishError.noCompletedSearch
        default: throw StockfishError.failed
        }
    }
}
