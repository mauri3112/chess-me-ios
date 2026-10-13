import SwiftUI
import ChessMeCore

@MainActor
final class TrainingBoardMotion: ObservableObject {
    @Published private(set) var position: ChessPosition?
    @Published private(set) var lastMove: ChessMove?
    @Published private(set) var isAnimating = false
    @Published private(set) var rejectionCount = 0
    private var generation = UUID()

    func stop() {
        generation = UUID()
        position = nil; lastMove = nil; isAnimating = false
    }

    func shake() { rejectionCount += 1 }

    func replay(_ history: MoveHistory, reduceMotion: Bool) async {
        guard !history.moves.isEmpty else { return }
        stop()
        let ticket = generation
        isAnimating = true
        position = history.positions[0]
        defer { if generation == ticket { stop() } }
        do {
            try await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 450))
            for index in history.moves.indices {
                try Task.checkCancellation()
                guard generation == ticket else { return }
                position = history.positions[index + 1]
                lastMove = history.moves[index]
                try await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 500))
            }
        } catch { }
    }

    func returnAttempt(_ move: ChessMove, in board: ChessPosition, rejected: Bool, reduceMotion: Bool) async {
        guard let next = try? board.applying(move) else { return }
        stop()
        let ticket = generation
        isAnimating = true
        position = next; lastMove = move
        defer { if generation == ticket { stop() } }
        do {
            try await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 280))
            guard generation == ticket else { return }
            position = board
            if rejected { shake() }
            try await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 250))
        } catch { }
    }
}

enum PracticeFeedback {
    static func success() -> String { ["You found it.", "Well done!", "Right", "Correct!"].randomElement()! }
}

struct BoardShake: GeometryEffect {
    var count: CGFloat
    var animatableData: CGFloat { get { count } set { count = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(count * .pi * 6) * 4, y: 0))
    }
}

extension PracticeMoveSuggestion {
    var color: Color {
        switch quality {
        case .best: return Color(red: 0.08, green: 0.48, blue: 0.28)
        case .excellent: return Color(red: 0.34, green: 0.65, blue: 0.43)
        default: return Color(red: 0.57, green: 0.76, blue: 0.59)
        }
    }
    var mark: String { quality == .best ? "★" : (quality == .excellent ? "✓" : "+") }
}

struct MoveChoiceLegend: View {
    let suggestions: [PracticeMoveSuggestion]
    @Binding var comparing: Bool
    var allowsComparison = true
    var body: some View {
        HStack(spacing: 9) {
            ForEach([MoveQuality.best, .excellent, .good], id: \.self) { quality in
                if let suggestion = suggestions.first(where: { $0.quality == quality }) {
                    HStack(spacing: 4) {
                        Text(suggestion.mark).font(.caption2.weight(.bold))
                            .frame(width: 18, height: 18).background(suggestion.color.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                        Text(quality.title).font(.caption2)
                    }.foregroundStyle(ChessMeStyle.ink)
                }
            }
            Spacer(minLength: 0)
            if allowsComparison {
                Button(comparing ? "Back to position" : "Compare moves") { comparing.toggle() }
                    .font(.caption.weight(.semibold)).accessibilityIdentifier("training.compareMoves")
            }
        }.accessibilityElement(children: .contain)
    }
}
