import Foundation
import CryptoKit

/// Public opening evidence only. Complete FEN and ordered history prevent
/// repetition, castling, en-passant and fifty-move-rule collisions.
public struct OpeningEvaluationCache: Sendable {
    public struct Entry: Codable, Sendable {
        public let positionFEN: String
        public let history: [String]
        public let configurationID: String
        public let evaluation: PositionEvaluation
        public init(positionFEN: String, history: [String], configurationID: String, evaluation: PositionEvaluation) {
            self.positionFEN = positionFEN; self.history = history; self.configurationID = configurationID; self.evaluation = evaluation
        }
    }
    public struct Archive: Codable, Sendable {
        public let schema: Int
        public let engineVersion: String
        public let entries: [Entry]
        public init(entries: [Entry], engineVersion: String = StockfishEngine.version, schema: Int = 1) {
            self.schema = schema; self.engineVersion = engineVersion; self.entries = entries
        }
    }
    public static let shared = OpeningEvaluationCache(data: Bundle.module.url(forResource: "OpeningEvaluations", withExtension: "json", subdirectory: "Resources").flatMap { try? Data(contentsOf: $0) })
    private let entries: [String: Entry]
    public var count: Int { entries.count }
    public init(data: Data?) {
        guard let data, data.count <= 5_000_000, let archive = try? JSONDecoder().decode(Archive.self, from: data),
              archive.schema == 1, archive.engineVersion == StockfishEngine.version else { entries = [:]; return }
        entries = Dictionary(archive.entries.map { (Self.key(fen: $0.positionFEN, history: $0.history, configuration: $0.configurationID), $0) }, uniquingKeysWith: { first, _ in first })
    }
    private static func key(fen: String, history: [String], configuration: String) -> String {
        let value = [StockfishEngine.version, "opening-cache-v1", configuration, fen] + history
        return SHA256.hash(data: Data(value.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public func evaluation(position: ChessPosition, history: [String], options: AnalysisOptions, requiredMove: ChessMove?) -> PositionEvaluation? {
        guard options.engine == .stockfish, position.fullmoveNumber <= 12,
              let entry = entries[Self.key(fen: position.fen, history: history, configuration: options.configurationID)],
              entry.evaluation.completedDepth >= options.maximumDepth, !entry.evaluation.moves.isEmpty,
              requiredMove == nil || entry.evaluation.moves.contains(where: { $0.move == requiredMove }) else { return nil }
        for candidate in entry.evaluation.moves {
            guard candidate.continuation.first == candidate.move, !candidate.continuation.isEmpty else { return nil }
            var board = position
            for move in candidate.continuation {
                guard let next = try? board.applying(move) else { return nil }
                board = next
            }
        }
        var result = entry.evaluation
        // Search evidence retains its actual depth. No new engine nodes were used.
        result = PositionEvaluation(moves: result.moves, completedDepth: result.completedDepth, nodes: 0,
                                    elapsedSeconds: 0, limit: "Precomputed opening analysis")
        return result
    }
}
