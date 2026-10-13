import Foundation
import CArasan

public enum ArasanEngine {
    public static let version = "arasan-26.0-v8-20260622"
    public static var license: String {
        guard let url = Bundle.module.url(forResource: "ArasanLicense", withExtension: "txt", subdirectory: "Resources") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}

enum ArasanError: LocalizedError {
    case missingNetwork, invalidPosition, failed, noCompletedSearch
    var errorDescription: String? {
        switch self {
        case .missingNetwork: return "Arasan's bundled network could not be loaded."
        case .invalidPosition: return "Arasan could not read this position."
        case .failed: return "Arasan could not finish the search."
        case .noCompletedSearch: return "The search limit was reached before a complete result. Try more time."
        }
    }
}

private final class ArasanCallbacks {
    struct Payload: Decodable {
        struct Line: Decodable { let score: Int; let moves: [String] }
        let depth: Int
        let nodes: Int
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
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(String(cString: text).utf8)) else { return }
        let candidates = payload.lines.compactMap { line -> MoveEvaluation? in
            var board = position
            var moves: [ChessMove] = []
            for token in line.moves {
                guard let move = try? ChessMove(uci: token), let next = try? board.applying(move) else { break }
                moves.append(move); board = next
            }
            guard let first = moves.first else { return nil }
            return MoveEvaluation(move: first, score: line.score, continuation: moves)
        }
        let value = PositionEvaluation(moves: candidates, completedDepth: payload.depth, nodes: payload.nodes,
                                       limit: payload.limit.isEmpty ? nil : payload.limit)
        result = value
        update(value)
    }
}

struct ArasanAnalyzer {
    let options: AnalysisOptions
    func evaluate(position: ChessPosition, repetitionHistory: [String], requiredMove: ChessMove?,
                  cancellation: @escaping () -> Bool, update: @escaping (PositionEvaluation) -> Void) throws -> PositionEvaluation {
        if cancellation() { throw ChessError.cancelled }
        guard position.outcome(repetitionCount: repetitionHistory.filter { $0 == position.repetitionKey }.count + 1) == .ongoing else {
            return PositionEvaluation(moves: [], completedDepth: 0, nodes: 0)
        }
        guard let network = Bundle.module.url(forResource: "arasanv8-20260622", withExtension: "nnue", subdirectory: "Resources") else {
            throw ArasanError.missingNetwork
        }
        let callbacks = ArasanCallbacks(position: position, cancellation: cancellation, update: update)
        let context = Unmanaged.passUnretained(callbacks).toOpaque()
        let code = chessme_arasan_analyze(network.path, position.fen, repetitionHistory.joined(separator: "\n"),
                                        requiredMove?.uci ?? "", Int32(options.maximumDepth), Int32(options.memoryMegabytes),
                                        Int32((options.timeLimitSeconds ?? 3) * 1_000),
                                        UInt64(options.nodesPerMove * max(1, position.legalMoves().count)), context,
            { pointer in
                guard let pointer else { return 1 }
                return Unmanaged<ArasanCallbacks>.fromOpaque(pointer).takeUnretainedValue().cancellation() ? 1 : 0
            }, { text, pointer in
                guard let text, let pointer else { return }
                Unmanaged<ArasanCallbacks>.fromOpaque(pointer).takeUnretainedValue().receive(text)
            })
        switch code {
        case 0:
            guard let result = callbacks.result, result.completedDepth > 0, !result.moves.isEmpty else { throw ArasanError.noCompletedSearch }
            return result
        case 1: throw ChessError.cancelled
        case 2: throw ArasanError.missingNetwork
        case 3: throw ArasanError.invalidPosition
        default: throw ArasanError.failed
        }
    }
}
