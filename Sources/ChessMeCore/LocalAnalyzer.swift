import Foundation

public struct AnalysisOptions: Sendable {
    public var maximumDepth: Int
    public var nodesPerMove: Int
    public var maximumPositions: Int
    public var minimumLoss: Int
    public var alternativeTolerance: Int
    public var memoryMegabytes: Int
    public var timeLimitSeconds: Double?
    public var searchNodeLimit: Int?
    public var engineThreads: Int
    public var engine: DeviceEngine

    public init(maximumDepth: Int = 2, nodesPerMove: Int = 1_200, maximumPositions: Int = 80,
                minimumLoss: Int = 120, alternativeTolerance: Int = 35,
                memoryMegabytes: Int = 16, timeLimitSeconds: Double? = nil, engine: DeviceEngine = .tactical, searchNodeLimit: Int? = nil, engineThreads: Int = 1) {
        self.maximumDepth = min(engine.maximumDepth, max(1, maximumDepth))
        self.nodesPerMove = min(100_000, max(64, nodesPerMove))
        self.maximumPositions = max(1, maximumPositions)
        self.minimumLoss = max(50, minimumLoss)
        self.alternativeTolerance = max(0, alternativeTolerance)
        self.memoryMegabytes = min(engine == .stockfish ? 256 : 64, max(1, memoryMegabytes))
        self.timeLimitSeconds = timeLimitSeconds.map { min(engine == .stockfish ? 300 : 30, max(0.01, $0)) }
        self.searchNodeLimit = searchNodeLimit.map { min(250_000_000, max(128, $0)) }
        self.engineThreads = min(2, max(1, engineThreads))
        self.engine = engine
    }

    public var configurationID: String {
        "\(engine.rawValue)-d\(maximumDepth)-n\(nodesPerMove)-m\(memoryMegabytes)-t\(timeLimitSeconds ?? 0)-l\(minimumLoss)-a\(alternativeTolerance)" + (engine == .stockfish ? "-total\(searchNodeLimit ?? 0)-threads\(engineThreads)" : "")
    }
}

public struct MoveEvaluation: Equatable, Sendable {
    public let move: ChessMove
    /// Centipawns from the side-to-move's perspective, or a mate score near 100,000.
    public let score: Int
    public let continuation: [ChessMove]
    public var isWinningMate: Bool { score > 90_000 }
    public var isLosingMate: Bool { score < -90_000 }
}

public struct PositionEvaluation: Sendable {
    public let moves: [MoveEvaluation]
    public let completedDepth: Int
    public let nodes: Int
    public var elapsedSeconds: Double? = nil
    public var limit: String? = nil
    public var best: MoveEvaluation? { moves.first }
}

/// Device analysis using bundled Stockfish, Arasan or the original lightweight Swift search.
/// Move grades remain estimates rather than calibrated provider accuracy scores.
public struct LocalAnalyzer: Sendable {
    public static let engineVersion = "local-tactical-v2"
    public var engineVersion: String {
        switch options.engine { case .stockfish: return StockfishEngine.version; case .arasan: return ArasanEngine.version; default: return Self.engineVersion }
    }
    public let options: AnalysisOptions
    public init(options: AnalysisOptions = AnalysisOptions()) { self.options = options }

    /// The Swift engine gives each candidate the same depth and node allowance.
    /// Arasan publishes completed MultiPV iterations within shared time/node limits.
    public func evaluate(position: ChessPosition, repetitionHistory: [String] = [], requiredMove: ChessMove? = nil,
                         cancellation: @escaping () -> Bool = { false },
                         update: @escaping (PositionEvaluation) -> Void = { _ in }) throws -> PositionEvaluation {
        if options.engine == .stockfish {
            return try StockfishAnalyzer(options: options).evaluate(position: position, repetitionHistory: repetitionHistory,
                requiredMove: requiredMove, cancellation: cancellation, update: update)
        }
        if options.engine == .arasan {
            return try ArasanAnalyzer(options: options).evaluate(position: position, repetitionHistory: repetitionHistory,
                requiredMove: requiredMove, cancellation: cancellation, update: update)
        }
        if cancellation() { throw ChessError.cancelled }
        let started = ProcessInfo.processInfo.systemUptime
        let deadline = options.timeLimitSeconds.map { started + $0 }
        let cache = SearchCache(megabytes: options.memoryMegabytes)
        let moves = position.legalMoves()
        if moves.isEmpty { return PositionEvaluation(moves: [], completedDepth: 0, nodes: 0) }
        if position.hasInsufficientMaterial || position.halfmoveClock >= 100 || repetitionHistory.filter({ $0 == position.repetitionKey }).count >= 2 {
            return PositionEvaluation(moves: [], completedDepth: 0, nodes: 0)
        }
        var scores = moves.map { move -> MoveEvaluation in
            let next = position.applyingUnchecked(move)
            let score = next.legalMoves().isEmpty ? (next.isInCheck ? Search.mateScore - 1 : 0) : -Search.staticEvaluation(next, engine: options.engine)
            return MoveEvaluation(move: move, score: score, continuation: [move])
        }
        func ranked(_ values: [MoveEvaluation]) -> [MoveEvaluation] {
            values.sorted { $0.score == $1.score ? $0.move.uci < $1.move.uci : $0.score > $1.score }
        }
        scores = ranked(scores)
        var completedDepth = 0, nodes = 0, lastUpdate = started
        var limit: String?
        update(PositionEvaluation(moves: scores, completedDepth: 0, nodes: 0))
        depthLoop: for depth in 1...options.maximumDepth {
            var iteration: [MoveEvaluation] = []
            for move in moves {
                if cancellation() { throw ChessError.cancelled }
                if let deadline, ProcessInfo.processInfo.systemUptime >= deadline { limit = "Time budget reached"; break depthLoop }
                let search = Search(nodeLimit: options.nodesPerMove, deadline: deadline, cache: cache,
                                    engine: options.engine, cancellation: cancellation, heartbeat: {
                    if ProcessInfo.processInfo.systemUptime - lastUpdate >= 2 {
                        update(PositionEvaluation(moves: scores, completedDepth: completedDepth, nodes: nodes))
                        lastUpdate = ProcessInfo.processInfo.systemUptime
                    }
                })
                do {
                    let result = try search.negamax(position.applyingUnchecked(move), depth: depth - 1,
                                                    alpha: -Search.infinity, beta: Search.infinity, ply: 1,
                                                    history: repetitionHistory + [position.repetitionKey])
                    iteration.append(MoveEvaluation(move: move, score: -result.score, continuation: [move] + result.line))
                    nodes += search.nodes
                } catch SearchError.nodeLimit {
                    nodes += search.nodes
                    limit = "Node budget reached"
                    break depthLoop
                } catch SearchError.timeLimit {
                    nodes += search.nodes
                    limit = "Time budget reached"
                    break depthLoop
                }
                if ProcessInfo.processInfo.systemUptime - lastUpdate >= 2 {
                    // Publish only complete, comparable iterations. Never blend depths.
                    update(PositionEvaluation(moves: scores, completedDepth: completedDepth, nodes: nodes))
                    lastUpdate = ProcessInfo.processInfo.systemUptime
                }
            }
            scores = ranked(iteration)
            completedDepth = depth
            update(PositionEvaluation(moves: scores, completedDepth: completedDepth, nodes: nodes))
            lastUpdate = ProcessInfo.processInfo.systemUptime
        }
        let result = PositionEvaluation(moves: scores, completedDepth: completedDepth, nodes: nodes, limit: limit)
        update(result)
        return result
    }

    public func analyze(game: ChessGame, previousAnalysis: GameAnalysis? = nil,
                        cancellation: @escaping () -> Bool = { false },
                        progress: (Int, Int) -> Void = { _, _ in },
                        evaluationUpdate: @escaping (PositionEvaluation) -> Void = { _ in }) throws -> GameAnalysis {
        guard game.isFinished else { throw ChessError.invalidPGN("only finished games can be reviewed") }
        let document = try game.mainline()
        guard document.result != "*" else { throw ChessError.invalidPGN("the game is unfinished") }
        guard !document.moves.isEmpty else { throw ChessError.invalidPGN("the game has no moves") }
        var position = try (game.initialFEN ?? document.initialFEN).map(ChessPosition.init(fen:)) ?? .initial
        var replay: [(ChessPosition, ChessMove)] = []
        // Validate the complete mainline before producing partial analysis.
        for token in document.moves {
            if cancellation() { throw ChessError.cancelled }
            let move = try position.move(san: token)
            replay.append((position, move))
            position = position.applyingUnchecked(move)
        }
        let decisions = replay.enumerated().filter { $0.element.0.sideToMove == game.playerSide }
        let repetitionKeys = replay.map { $0.0.repetitionKey }
        if let previousAnalysis {
            guard previousAnalysis.gameID == game.id,
                  previousAnalysis.source == "device",
                  previousAnalysis.engineVersion == engineVersion,
                  previousAnalysis.configurationID == options.configurationID,
                  previousAnalysis.totalPlies == decisions.count,
                  (0...decisions.count).contains(previousAnalysis.analyzedPlies),
                  previousAnalysis.findings.allSatisfy({ $0.gameID == game.id && $0.source == "device" }),
                  Set(previousAnalysis.findings.map(\.id)).count == previousAnalysis.findings.count else {
                throw ChessError.invalidPGN("saved analysis does not match this game or device engine")
            }
        }
        var findings = previousAnalysis?.findings ?? []
        var assessments = previousAnalysis?.moveAssessments ?? []
        var analyzed = previousAnalysis?.analyzedPlies ?? 0
        progress(analyzed, decisions.count)
        for (ply, (position, played)) in decisions.dropFirst(analyzed).prefix(options.maximumPositions) {
            if cancellation() { throw ChessError.cancelled }
            let history = Array(repetitionKeys.prefix(ply))
            let evaluation = try evaluate(position: position, repetitionHistory: history, requiredMove: played, cancellation: cancellation, update: evaluationUpdate)
            if let assessment = evaluation.assessment(position: position, played: played, ply: ply) { assessments.append(assessment) }
            if let finding = finding(game: game, ply: ply, position: position, played: played, evaluation: evaluation) {
                findings.append(finding)
            }
            analyzed += 1
            progress(analyzed, decisions.count)
        }
        let analysis = GameAnalysis(gameID: game.id, findings: findings, analyzedPlies: analyzed, totalPlies: decisions.count,
                                    engineVersion: engineVersion, configurationID: options.configurationID, moveAssessments: assessments)
        let opening = OpeningBook.shared.line(positions: replay.map { $0.0 } + [position], moves: replay.map { $0.1 })
        return opening.annotating(analysis)
    }

    private func finding(game: ChessGame, ply: Int, position: ChessPosition,
                         played: ChessMove, evaluation: PositionEvaluation) -> MoveFinding? {
        // A search interrupted before depth 1 provides no teaching evidence.
        guard evaluation.completedDepth >= 1, evaluation.moves.count > 1,
              let best = evaluation.best, let actual = evaluation.moves.first(where: { $0.move == played }),
              best.move != played else { return nil }
        if best.isWinningMate && actual.isWinningMate { return nil }
        if best.isLosingMate && actual.isLosingMate { return nil }
        let missedMate = best.isWinningMate && !actual.isWinningMate
        let allowsMate = actual.isLosingMate && !best.isLosingMate
        let loss = missedMate || allowsMate ? 1_000 : max(0, best.score - actual.score)
        guard loss >= options.minimumLoss else { return nil }
        let accepted: [MoveEvaluation]
        if best.isWinningMate { accepted = evaluation.moves.filter { $0.isWinningMate } }
        else { accepted = evaluation.moves.filter { !$0.isLosingMate && best.score - $0.score <= options.alternativeTolerance } }
        let afterBest = position.applyingUnchecked(best.move)
        let check = afterBest.isInCheck
        let captured = position.squares[best.move.to]?.kind
        let theme: String
        let explanation: String
        let hint: String
        let bestSAN = (try? position.san(best.move)) ?? best.move.uci
        let playedSAN = (try? position.san(played)) ?? played.uci
        if missedMate {
            theme = "Missed checkmate"
            explanation = "You played \(playedSAN). The local search finds a forced checkmate after \(bestSAN). Replay the line to see how the king's escape squares are covered."
            hint = "Look for a forcing check. Count the king's escape squares."
        } else if allowsMate {
            theme = "King safety"
            explanation = "After \(playedSAN), the opponent has a forced checkmate in this search. \(bestSAN) avoids that line. Check the threats around your king before moving."
            hint = "What is the opponent threatening against your king?"
        } else if let captured, captured.value >= PieceKind.knight.value {
            theme = "Winning material"
            explanation = "The search prefers \(bestSAN) to \(playedSAN). It wins or preserves material in the displayed line. Check whether the captured piece can be defended."
            hint = "Look for a loose piece, then calculate the recapture."
        } else if check {
            theme = "Forcing moves"
            explanation = "The search prefers the check \(bestSAN) to \(playedSAN). A forcing move gives the opponent fewer useful replies. Replay the line and compare the resulting material."
            hint = "Start with checks, then captures."
        } else {
            theme = "Preventing material loss"
            explanation = "The local search evaluates \(bestSAN) above \(playedSAN). Compare the displayed line with your original move and look for an undefended piece. This is a short tactical estimate."
            hint = "Which of your pieces would be left undefended?"
        }
        // A small local engine cannot grade ambiguous quiet positions confidently.
        let decisive = missedMate || allowsMate || captured != nil || check || best.move.promotion != nil
        let isPuzzle = decisive && accepted.count <= 3
        return MoveFinding(id: "\(game.id)-\(ply)", gameID: game.id, gameLabel: game.label,
                           positionFEN: position.fen, playedMove: played.uci, bestMove: best.move.uci,
                           acceptedMoves: accepted.map { $0.move.uci }, continuation: best.continuation.map(\.uci),
                           centipawnLoss: Double(loss), theme: theme, explanation: explanation,
                           hint: hint, moveNumber: position.fullmoveNumber, source: "device", isPuzzle: isPuzzle)
    }
}

private enum SearchError: Error { case nodeLimit, timeLimit }
private struct SearchResult { let score: Int; let line: [ChessMove] }

private final class SearchCache {
    private var values: [String: SearchResult] = [:]
    private var bytes = 0
    private let maximumBytes: Int
    init(megabytes: Int) { maximumBytes = megabytes * 1_024 * 1_024 }
    subscript(key: String) -> SearchResult? {
        get { values[key] }
        set {
            guard let newValue, values[key] == nil else { return }
            // Include key, line and dictionary overhead in the cache allowance.
            let cost = key.utf8.count * 2 + newValue.line.count * 32 + 512
            guard cost <= maximumBytes else { return }
            if bytes + cost > maximumBytes { values.removeAll(keepingCapacity: false); bytes = 0 }
            values[key] = newValue
            bytes += cost
        }
    }
}

private final class Search {
    static let mateScore = 100_000
    static let infinity = 200_000
    let nodeLimit: Int
    let cancellation: () -> Bool
    let deadline: Double?
    let cache: SearchCache
    let engine: DeviceEngine
    let heartbeat: () -> Void
    var nodes = 0
    init(nodeLimit: Int, deadline: Double?, cache: SearchCache, engine: DeviceEngine, cancellation: @escaping () -> Bool,
         heartbeat: @escaping () -> Void) {
        self.nodeLimit = nodeLimit; self.deadline = deadline; self.cache = cache
        self.engine = engine; self.cancellation = cancellation
        self.heartbeat = heartbeat
    }

    func negamax(_ position: ChessPosition, depth: Int, alpha: Int, beta: Int, ply: Int,
                 history: [String]) throws -> SearchResult {
        try visit()
        let moves = position.legalMoves()
        if moves.isEmpty { return SearchResult(score: position.isInCheck ? -Self.mateScore + ply : 0, line: []) }
        let key = position.repetitionKey
        if position.hasInsufficientMaterial || position.halfmoveClock >= 100 || history.filter({ $0 == key }).count >= 2 {
            return SearchResult(score: 0, line: [])
        }
        if depth <= 0 {
            return try quiescence(position, moves: moves, alpha: alpha, beta: beta, ply: ply, remaining: 3, history: history)
        }
        let cacheKey = "\(position.fen)|\(depth)|\(ply)|\(history.suffix(position.halfmoveClock + 1).joined(separator: ","))"
        if let result = cache[cacheKey] { return result }
        var bestScore = -Self.infinity, bestLine: [ChessMove] = [], bound = alpha
        var cutoff = false
        for move in ordered(moves, in: position) {
            let result = try negamax(position.applyingUnchecked(move), depth: depth - 1,
                                     alpha: -beta, beta: -bound, ply: ply + 1, history: history + [key])
            let score = -result.score
            if score > bestScore { bestScore = score; bestLine = [move] + result.line }
            bound = max(bound, score)
            if bound >= beta { cutoff = true; break }
        }
        let result = SearchResult(score: bestScore, line: bestLine)
        // Fail-low and cutoff scores are bounds, not exact reusable evaluations.
        if !cutoff && bestScore > alpha { cache[cacheKey] = result }
        return result
    }

    private func quiescence(_ position: ChessPosition, moves: [ChessMove], alpha: Int, beta: Int,
                            ply: Int, remaining: Int, history: [String]) throws -> SearchResult {
        let inCheck = position.isInCheck
        let staticScore = Self.staticEvaluation(position, engine: engine)
        if remaining <= 0 { return SearchResult(score: staticScore, line: []) }
        var bound = alpha, bestScore = inCheck ? -Self.infinity : staticScore, bestLine: [ChessMove] = []
        if !inCheck {
            if staticScore >= beta { return SearchResult(score: staticScore, line: []) }
            bound = max(bound, staticScore)
        }
        for move in ordered(moves.filter { inCheck || position.isCapture($0) || $0.promotion != nil }, in: position) {
            try visit()
            let next = position.applyingUnchecked(move)
            let replies = next.legalMoves()
            let result: SearchResult
            if replies.isEmpty { result = SearchResult(score: next.isInCheck ? -Self.mateScore + ply + 1 : 0, line: []) }
            else if next.hasInsufficientMaterial || next.halfmoveClock >= 100 || history.filter({ $0 == next.repetitionKey }).count >= 2 {
                result = SearchResult(score: 0, line: [])
            } else {
                result = try quiescence(next, moves: replies, alpha: -beta, beta: -bound, ply: ply + 1,
                                        remaining: remaining - 1, history: history + [position.repetitionKey])
            }
            let score = -result.score
            if score > bestScore { bestScore = score; bestLine = [move] + result.line }
            bound = max(bound, score)
            if bound >= beta { break }
        }
        return SearchResult(score: bestScore, line: bestLine)
    }

    private func visit() throws {
        if cancellation() { throw ChessError.cancelled }
        if let deadline, ProcessInfo.processInfo.systemUptime >= deadline { throw SearchError.timeLimit }
        guard nodes < nodeLimit else { throw SearchError.nodeLimit }
        nodes += 1
        if nodes % 256 == 0 { heartbeat() }
    }

    private func ordered(_ moves: [ChessMove], in position: ChessPosition) -> [ChessMove] {
        moves.sorted {
            func priority(_ move: ChessMove) -> Int {
                let captured = position.squares[move.to]?.kind.value ?? (position.isCapture(move) ? 100 : 0)
                let attacker = position.squares[move.from]?.kind.value ?? 0
                return captured * 10 - (captured > 0 ? attacker : 0) + (move.promotion?.value ?? 0) * 10
            }
            let lhs = priority($0), rhs = priority($1)
            return lhs == rhs ? $0.uci < $1.uci : lhs > rhs
        }
    }

    static func staticEvaluation(_ position: ChessPosition, engine: DeviceEngine) -> Int {
        var score = 0
        var bishops = [Side.white: 0, Side.black: 0]
        for (square, optionalPiece) in position.squares.enumerated() {
            guard let piece = optionalPiece else { continue }
            let file = square % 8, rank = piece.side == .white ? square / 8 : 7 - square / 8
            let centrality = 6 - abs(file * 2 - 7) - abs(rank * 2 - 7)
            var value = piece.kind.value
            if engine == .material {
                score += piece.side == .white ? value : -value
                continue
            }
            switch piece.kind {
            case .pawn: value += rank * 6 + max(0, 3 - abs(file - 3)) * 3
            case .knight: value += centrality * 5
            case .bishop: value += centrality * 3; bishops[piece.side, default: 0] += 1
            case .rook: value += rank == 6 ? 20 : 0
            case .queen: value += centrality
            case .king:
                if rank == 0 && [1, 2, 6].contains(file) { value += 20 }
            }
            score += piece.side == .white ? value : -value
        }
        if bishops[.white, default: 0] >= 2 { score += 25 }
        if bishops[.black, default: 0] >= 2 { score -= 25 }
        return position.sideToMove == .white ? score : -score
    }
}
