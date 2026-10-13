import Foundation

public enum DeviceEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case stockfish, arasan, tactical, material
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .stockfish: return "Stockfish 19"
        case .arasan: return "Arasan 26"
        case .tactical: return "ChessMe Tactical"
        case .material: return "ChessMe Material"
        }
    }
    public var maximumDepth: Int { self == .stockfish ? 64 : (self == .arasan ? 32 : 8) }
    public var isNeural: Bool { self == .stockfish || self == .arasan }
    public var detail: String {
        switch self {
        case .stockfish: return "Stockfish and its neural network, bundled for offline analysis."
        case .arasan: return "Neural analysis, bundled for offline use."
        case .tactical: return "Lightweight tactical search."
        case .material: return "Lightweight material evaluation."
        }
    }
}

public struct DeviceEngineConfiguration: Codable, Equatable, Sendable {
    public var engine: DeviceEngine = .stockfish
    public var depth = 21
    public var nodesPerCandidate = 100_000
    public var memoryMB = 16
    public var secondsPerPosition = 3
    public var topMoves = 2
    public var searchNodeLimit: Int?
    public var engineThreads: Int?
    public init() {}

    public func bounded(forMemoryMB physicalMemory: Int, lowPower: Bool = false) -> Self {
        var result = self
        result.depth = min(lowPower ? (engine.isNeural ? 10 : 3) : engine.maximumDepth, max(1, depth))
        result.nodesPerCandidate = min(lowPower ? (engine.isNeural ? 50_000 : 4_000) : 100_000, max(64, nodesPerCandidate))
        result.memoryMB = min(Self.maximumCacheMB(physicalMemory: physicalMemory), max(1, memoryMB))
        result.secondsPerPosition = min(lowPower ? 3 : 15, max(1, secondsPerPosition))
        result.topMoves = min(3, max(1, topMoves))
        result.engineThreads = lowPower ? 1 : min(2, max(1, engineThreads ?? 1))
        if lowPower { result.searchNodeLimit = searchNodeLimit.map { min(500_000, $0) } }
        return result
    }

    public static func maximumCacheMB(physicalMemory: Int) -> Int {
        physicalMemory < 3_000 ? 8 : (physicalMemory < 6_000 ? 32 : 64)
    }

    public var options: AnalysisOptions {
        AnalysisOptions(maximumDepth: depth, nodesPerMove: nodesPerCandidate, maximumPositions: 4,
                        memoryMegabytes: memoryMB, timeLimitSeconds: Double(secondsPerPosition), engine: engine,
                        searchNodeLimit: searchNodeLimit, engineThreads: engineThreads ?? 1)
    }

    /// Completed work at this search budget can satisfy a smaller request.
    /// Memory and thread preferences do not require repeating a saved review.
    public func covers(_ requested: Self) -> Bool {
        guard engine == requested.engine, depth >= requested.depth,
              secondsPerPosition >= requested.secondsPerPosition else { return false }
        if let requestedNodes = requested.searchNodeLimit {
            guard let searchNodeLimit, searchNodeLimit >= requestedNodes else { return false }
        } else if nodesPerCandidate < requested.nodesPerCandidate { return false }
        return true
    }
}

public enum MoveQuality: String, Codable, CaseIterable, Sendable {
    case brilliant, best, excellent, good, inaccuracy, mistake, blunder, unclassified
    public var title: String {
        self == .brilliant ? "Brilliant candidate" : (self == .unclassified ? "Not assessed" : rawValue.capitalized)
    }
    public var symbol: String {
        switch self {
        case .brilliant: return "sparkles"
        case .best: return "star.fill"
        case .excellent: return "checkmark.seal.fill"
        case .good: return "checkmark"
        case .inaccuracy: return "exclamationmark.circle"
        case .mistake: return "exclamationmark.triangle.fill"
        case .blunder: return "xmark.octagon.fill"
        case .unclassified: return "questionmark.circle"
        }
    }
    public static func estimated(loss: Int, isBest: Bool = false) -> Self {
        if isBest { return .best }
        switch max(0, loss) {
        case 0...15: return .excellent
        case 16...50: return .good
        case 51...100: return .inaccuracy
        case 101...250: return .mistake
        default: return .blunder
        }
    }
}

public struct MoveAssessment: Codable, Identifiable, Equatable, Sendable {
    public var id: Int { ply }
    /// Zero-based index in the complete game mainline, including the opponent's moves.
    public let ply: Int
    public let positionFEN: String
    public let playedMove: String
    public let bestMove: String
    public let quality: MoveQuality
    public let centipawnLoss: Int
    public let whiteScore: Int
    public let completedDepth: Int
    public let isProvisional: Bool
    public init(ply: Int, positionFEN: String, playedMove: String, bestMove: String,
                quality: MoveQuality, centipawnLoss: Int, whiteScore: Int, completedDepth: Int, isProvisional: Bool) {
        self.ply = ply; self.positionFEN = positionFEN; self.playedMove = playedMove; self.bestMove = bestMove
        self.quality = quality; self.centipawnLoss = centipawnLoss; self.whiteScore = whiteScore
        self.completedDepth = completedDepth; self.isProvisional = isProvisional
    }
}

public extension PositionEvaluation {
    /// Only completed, comparable searches can label alternative moves as good.
    func goodMoves(in position: ChessPosition, limit: Int = 3) -> [PracticeMoveSuggestion] {
        guard completedDepth >= 2 else { return [] }
        let legalMoves = Set(position.legalMoves())
        return moves.compactMap { candidate in
            guard legalMoves.contains(candidate.move),
                  let grade = assessment(position: position, played: candidate.move, ply: 0),
                  grade.centipawnLoss <= 50 else { return nil }
            let quality: MoveQuality = candidate.move == best?.move ? .best : (grade.centipawnLoss <= 15 ? .excellent : .good)
            return PracticeMoveSuggestion(move: candidate.move, quality: quality)
        }.prefix(max(0, limit)).map { $0 }
    }

    func assessment(position: ChessPosition, played: ChessMove, ply: Int) -> MoveAssessment? {
        guard completedDepth > 0, let best, let actual = moves.first(where: { $0.move == played }) else { return nil }
        let equalMate = (best.isWinningMate && actual.isWinningMate) || (best.isLosingMate && actual.isLosingMate)
        let mateLost = (best.isWinningMate && !actual.isWinningMate) || (actual.isLosingMate && !best.isLosingMate)
        let loss = equalMate ? 0 : (mateLost ? 1_000 : max(0, best.score - actual.score))
        var quality = MoveQuality.estimated(loss: loss, isBest: best.move == played)
        // A candidate needs a searched sacrifice, a recovered evaluation and a clear
        // gap to other moves. It remains an estimate, never a provider award.
        if best.move == played, completedDepth >= 4, best.score >= 0, moves.count > 1,
           best.score - moves[1].score >= 100, best.continuation.count >= 4 {
            func material(_ board: ChessPosition) -> Int {
                board.squares.compactMap { $0 }.reduce(0) { $0 + ($1.side == position.sideToMove ? $1.kind.value : -$1.kind.value) }
            }
            let originalMaterial = material(position)
            var board = position
            var sacrifice = false
            for (index, move) in best.continuation.prefix(4).enumerated() {
                guard let next = try? board.applying(move) else { break }
                board = next
                if index == 1 && material(board) <= originalMaterial - 200 { sacrifice = true }
            }
            if sacrifice && material(board) >= originalMaterial { quality = .brilliant }
        }
        return MoveAssessment(ply: ply, positionFEN: position.fen, playedMove: played.uci,
                              bestMove: best.move.uci, quality: quality, centipawnLoss: loss,
                              whiteScore: actual.score * (position.sideToMove == .white ? 1 : -1),
                              completedDepth: completedDepth, isProvisional: true)
    }
}

public struct PracticeMoveSuggestion: Equatable, Sendable {
    public let move: ChessMove
    public let quality: MoveQuality
    public init(move: ChessMove, quality: MoveQuality) { self.move = move; self.quality = quality }
}

public extension MoveFinding {
    var estimatedQuality: MoveQuality { MoveQuality.estimated(loss: Int(min(100_000, max(0, centipawnLoss.isFinite ? centipawnLoss : 0)))) }
}

/// A centipawn bar is an engine estimate. Its fill is not a player's win probability.
public struct EvaluationDisplay: Equatable, Sendable {
    public let whiteScore: Int
    public init(sideToMoveScore: Int, side: Side) { whiteScore = sideToMoveScore * (side == .white ? 1 : -1) }
    public var label: String {
        if abs(whiteScore) == 100_000 { return "Mate" }
        if abs(whiteScore) > 90_000 {
            let moves = max(1, (100_000 - abs(whiteScore) + 1) / 2)
            return "\(whiteScore < 0 ? "−" : "")M\(moves)"
        }
        return String(format: "%+.1f", Double(whiteScore) / 100)
    }
    public var advantage: String {
        if abs(whiteScore) == 100_000 { return "\(whiteScore > 0 ? "White" : "Black") wins by checkmate" }
        if abs(whiteScore) > 90_000 { return "\(whiteScore > 0 ? "White" : "Black") has a mating line" }
        if abs(whiteScore) < 25 { return "Approximately equal" }
        return "\(whiteScore > 0 ? "White" : "Black") ahead by \(String(format: "%.1f", Double(abs(whiteScore)) / 100)) pawns"
    }
    public var whiteFraction: Double { min(0.97, max(0.03, 0.5 + Double(whiteScore) / (2 * (Double(abs(whiteScore)) + 400)))) }
}
