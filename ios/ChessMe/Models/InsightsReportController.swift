import Foundation
import Combine
import ChessMeCore

struct InsightsReportInput: Equatable, Sendable {
    let games: [ChessGame]
    let analyses: [GameAnalysis]
    let review: ReviewLibrary
    let username: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.games == rhs.games && lhs.analyses == rhs.analyses && lhs.username == rhs.username &&
        lhs.review.targets == rhs.review.targets && lhs.review.attempts == rhs.review.attempts
    }
}

@MainActor
final class InsightsReportController: ObservableObject {
    typealias Calculate = @Sendable (InsightsReportInput) async -> LearningInsights
    @Published private(set) var report: LearningInsights?
    private var publishedInput: InsightsReportInput?
    private var generation = UUID()
    private var work: Task<LearningInsights, Never>?
    private let calculate: Calculate

    init(calculate: @escaping Calculate = { input in
        LearningInsights(games: input.games, analyses: input.analyses, review: input.review, username: input.username)
    }) {
        self.calculate = calculate
    }

    // Hide old evidence before SwiftUI starts its replacement task.
    func report(for input: InsightsReportInput) -> LearningInsights? {
        publishedInput == input ? report : nil
    }

    func refresh(_ input: InsightsReportInput) async {
        cancel()
        let request = generation
        let calculate = calculate
        let worker = Task.detached(priority: .utility) { await calculate(input) }
        work = worker
        let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        guard !Task.isCancelled, !worker.isCancelled, request == generation else { return }
        work = nil
        publishedInput = input
        report = result
    }

    func cancel() {
        generation = UUID()
        work?.cancel()
        work = nil
        publishedInput = nil
        report = nil
    }
}
