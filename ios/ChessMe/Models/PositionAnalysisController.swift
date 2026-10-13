import Foundation
import SwiftUI
import ChessMeCore

@MainActor
final class PositionAnalysisController: ObservableObject {
    @Published private(set) var evaluation: PositionEvaluation?
    private(set) var evaluationPosition: ChessPosition?
    @Published private(set) var isCalculating = false
    @Published private(set) var message: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var requestKey: String?
    private(set) var lines: [String: String] = [:]
    private var cache: [String: (PositionEvaluation, [String: String])] = [:]
    private var cacheOrder: [String] = []

    func start(position: ChessPosition, history: [String] = [], configuration: DeviceEngineConfiguration) {
        let key = position.fen + configuration.options.configurationID + history.joined()
        guard key != requestKey else { return }
        stop()
        requestKey = key
        evaluationPosition = position
        lines = [:]
        evaluation = nil
        message = nil
        if let cached = cache[key] {
            lines = cached.1; evaluation = cached.0; message = cached.0.limit
            return
        }
        guard ProcessInfo.processInfo.thermalState != .serious && ProcessInfo.processInfo.thermalState != .critical else {
            message = "Analysis paused while your iPhone cools down."
            requestKey = nil
            return
        }
        isCalculating = true
        let ticket = generation
        let options = configuration.options
        task = Task { [weak self] in
            do {
                // Scrubbing can cross many positions in one gesture. Start only the position
                // the user settles on, while board navigation remains immediate.
                try await Task.sleep(for: .milliseconds(120))
                try Task.checkCancellation()
                let work = Task.detached(priority: .utility) { [weak self] () throws -> (PositionEvaluation?, String?, [String: String]) in
                    let outcome = position.outcome(repetitionCount: history.filter { $0 == position.repetitionKey }.count + 1)
                    guard outcome == .ongoing else {
                        return (nil, outcome == .repetitionDraw ? "Draw by repetition." : "This position has ended.", [:])
                    }
                    let result = try LocalAnalyzer(options: options).evaluate(position: position, repetitionHistory: history,
                    cancellation: { Task.isCancelled }, update: { snapshot in
                        let lines = Self.formatLines(snapshot, position: position)
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == ticket, self.isCalculating,
                                  (self.evaluation?.completedDepth ?? -1) <= snapshot.completedDepth else { return }
                            self.lines = lines
                            self.evaluation = snapshot
                        }
                    })
                    return (result, result.limit, Self.formatLines(result, position: position))
                }
                let result = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
                guard let self, self.generation == ticket, !Task.isCancelled else { return }
                self.lines = result.2
                self.evaluation = result.0
                self.isCalculating = false
                self.message = result.1
                if let evaluation = result.0 {
                    self.cache[key] = (evaluation, result.2)
                    self.cacheOrder.append(key)
                    if self.cacheOrder.count > 24 { self.cache.removeValue(forKey: self.cacheOrder.removeFirst()) }
                }
            } catch {
                guard let self, self.generation == ticket else { return }
                self.isCalculating = false
                if !Task.isCancelled { self.message = error.localizedDescription }
            }
        }
    }

    func stop() {
        generation = UUID()
        requestKey = nil
        task?.cancel()
        task = nil
        isCalculating = false
    }

    func evaluation(for position: ChessPosition) -> PositionEvaluation? {
        evaluationPosition == position ? evaluation : nil
    }

    nonisolated private static func formatLines(_ evaluation: PositionEvaluation, position: ChessPosition) -> [String: String] {
        Dictionary(evaluation.moves.prefix(3).map { candidate in
            var board = position
            let notation = candidate.continuation.prefix(6).compactMap { move -> String? in
                guard let san = try? board.san(move), let next = try? board.applying(move) else { return nil }
                board = next
                return san
            }.joined(separator: " ")
            return (candidate.move.uci, notation)
        }, uniquingKeysWith: { first, _ in first })
    }

    func evaluateAttempt(move: ChessMove, position: ChessPosition, configuration: DeviceEngineConfiguration) async throws -> PositionEvaluation {
        let work = Task.detached(priority: .utility) {
            try LocalAnalyzer(options: configuration.options).evaluate(
                position: position, requiredMove: move, cancellation: { Task.isCancelled })
        }
        return try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
    }
}
