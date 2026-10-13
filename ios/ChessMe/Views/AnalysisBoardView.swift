import SwiftUI
import ChessMeCore

/// Only the board and engine panel observe streaming evaluations. A depth update
/// must not reconstruct the enclosing game history, clock timeline or findings.
struct LiveAnalysis<Content: View>: View {
    @ObservedObject var controller: PositionAnalysisController
    let position: ChessPosition
    @ViewBuilder let content: (PositionEvaluation?) -> Content
    var body: some View { content(controller.evaluation(for: position)) }
}

struct AnalysisBoardView: View {
    let position: ChessPosition
    var perspective: Side = .white
    var selectedSquare: Int?
    var targets: Set<Int> = []
    var highlightedSquares: Set<Int> = []
    var moveMarker: BoardMoveMarker?
    var suggestions: [PracticeMoveSuggestion] = []
    var rejectionCount = 0
    var evaluation: PositionEvaluation?
    var evaluationPosition: ChessPosition?
    var topMoves = 2
    var fallbackMove: String?
    var showArrows = true
    var revealEvaluation = true
    var onSquare: ((Int) -> Void)?
    @AppStorage("analysis.showEvaluationBar") private var showEvaluationBar = true
    @State private var outcomePosition: ChessPosition?
    @State private var cachedOutcome: PositionOutcome = .ongoing

    private var arrows: [BoardArrow] {
        guard showArrows else { return [] }
        if let evaluation, !evaluation.moves.isEmpty {
            return evaluation.moves.prefix(topMoves).enumerated().map { BoardArrow(move: $0.element.move, rank: $0.offset) }
        }
        if let fallbackMove, let move = try? ChessMove(uci: fallbackMove), position.legalMoves().contains(move) {
            return [BoardArrow(move: move)]
        }
        return []
    }
    private var display: EvaluationDisplay? {
        guard revealEvaluation else { return nil }
        let evaluatedPosition = evaluationPosition ?? position
        let outcome = outcomePosition == evaluatedPosition ? cachedOutcome : .ongoing
        if case .checkmate(let winner) = outcome {
            return EvaluationDisplay(sideToMoveScore: 100_000, side: winner)
        }
        if outcome != .ongoing { return EvaluationDisplay(sideToMoveScore: 0, side: .white) }
        return evaluation?.best.map { EvaluationDisplay(sideToMoveScore: $0.score, side: evaluatedPosition.sideToMove) }
    }
    var body: some View {
        let display = display
        HStack(alignment: .top, spacing: 8) {
            if showEvaluationBar {
            GeometryReader { geometry in
                ZStack(alignment: perspective == .white ? .bottom : .top) {
                    RoundedRectangle(cornerRadius: 7).fill(ChessMeStyle.ink)
                    Rectangle().fill(Color.white).frame(height: geometry.size.height * (display?.whiteFraction ?? 0.5))
                    VStack {
                        Spacer()
                        Text(display?.label ?? "?").font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(ChessMeStyle.ink).padding(.vertical, 6).frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.9))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .animation(.easeInOut(duration: 0.25), value: display?.whiteFraction)
            }
            .frame(width: 28)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Evaluation, \(display?.advantage ?? "hidden until you request analysis")")
            .accessibilityValue(display?.label ?? "?")
            .accessibilityIdentifier("analysis.evaluation")
            }
            ChessBoardView(position: position, perspective: perspective, selectedSquare: selectedSquare,
                           targets: targets, highlightedSquares: highlightedSquares, arrows: arrows, moveMarker: moveMarker,
                           suggestions: suggestions, rejectionCount: rejectionCount, onSquare: onSquare)
        }
        .aspectRatio(showEvaluationBar ? 1.11 : 1, contentMode: .fit)
        .onChange(of: evaluationPosition ?? position, initial: true) { _, value in
            cachedOutcome = value.outcome(); outcomePosition = value
        }
    }
}

struct AnalysisPanel: View {
    let position: ChessPosition
    @ObservedObject var controller: PositionAnalysisController
    let configuration: DeviceEngineConfiguration
    var referenceEvaluation: PositionEvaluation?
    var showMoves = true
    @State private var showDetails = false
    private var evaluation: PositionEvaluation? { referenceEvaluation ?? controller.evaluation(for: position) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                if controller.isCalculating { ProgressView().controlSize(.small) }
                Text("\(configuration.engine.title) · device").font(.caption.weight(.semibold))
                Spacer()
                if let evaluation {
                    Button { showDetails.toggle() } label: {
                        Text("Depth \(evaluation.completedDepth)").font(.caption.monospacedDigit())
                    }.buttonStyle(.plain).accessibilityLabel("Search details").accessibilityIdentifier("analysis.details")
                }
            }.foregroundStyle(ChessMeStyle.green)
            if let evaluation {
                if showMoves {
                    ForEach(Array(evaluation.moves.prefix(configuration.topMoves).enumerated()), id: \.element.move.uci) { _, candidate in
                        HStack(alignment: .top, spacing: 9) {
                            Text(line(candidate.continuation)).font(.subheadline.weight(.medium)).lineLimit(2)
                            Spacer()
                            Text(EvaluationDisplay(sideToMoveScore: candidate.score, side: position.sideToMove).label)
                                .font(.caption.monospacedDigit()).foregroundStyle(ChessMeStyle.muted)
                        }
                    }
                }
                if showDetails {
                    Text("\(evaluation.nodes.formatted()) nodes · target depth \(configuration.depth)\(controller.message.map { " · \($0)" } ?? "")")
                        .font(.caption2).foregroundStyle(ChessMeStyle.muted)
                }
            } else if let message = controller.message { Text(message).font(.caption).foregroundStyle(ChessMeStyle.muted) }
        }
        .padding(14).background(ChessMeStyle.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain).accessibilityIdentifier("analysis.panel")
    }
    private func line(_ moves: [ChessMove]) -> String {
        if referenceEvaluation == nil, controller.evaluation(for: position) != nil,
           let move = moves.first, let notation = controller.lines[move.uci] { return notation }
        var board = position
        return moves.prefix(6).compactMap { move in
            guard let san = try? board.san(move), let next = try? board.applying(move) else { return nil }
            board = next
            return san
        }.joined(separator: " ")
    }
}

struct MoveQualityBadge: View {
    let quality: MoveQuality
    var estimated = true
    private var color: Color {
        switch quality {
        case .brilliant, .best, .excellent, .good: return ChessMeStyle.green
        case .inaccuracy: return .orange
        case .mistake, .blunder: return .red
        case .unclassified: return ChessMeStyle.muted
        }
    }
    var body: some View {
        Label(quality.title, systemImage: quality.symbol)
            .font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.09), in: Capsule())
            .accessibilityLabel((estimated && quality != .unclassified ? "Estimated " : "") + quality.title)
    }
}

struct EvaluationTimelineGeometry {
    let size: CGSize
    let totalPlies: Int
    private var inset: CGFloat { min(8, min(size.width, size.height) / 2) }
    func point(for assessment: MoveAssessment) -> CGPoint {
        let fraction = min(1, max(0, CGFloat(assessment.ply + 1) / CGFloat(max(1, totalPlies))))
        return CGPoint(x: inset + fraction * max(0, size.width - 2 * inset),
                       y: inset + max(0, size.height - 2 * inset) *
                          (0.5 - CGFloat(min(1_000, max(-1_000, assessment.whiteScore))) / 2_000))
    }
    func nearest(to x: CGFloat, assessments: [MoveAssessment]) -> MoveAssessment? {
        assessments.min { abs(point(for: $0).x - x) < abs(point(for: $1).x - x) }
    }
}

struct EvaluationTimeline: View {
    let assessments: [MoveAssessment]
    let totalPlies: Int
    let selectedPly: Int
    var source = "device"
    var highlightedQuality: MoveQuality?
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Evaluation · \(source == "cloud" ? "cloud" : "on device")").font(.caption.weight(.medium)).foregroundStyle(ChessMeStyle.muted)
            HStack(spacing: 8) {
            VStack(alignment: .leading) {
                Text("+10")
                Spacer()
                Text("0")
                Spacer()
                Text("−10")
            }.font(.caption2.monospacedDigit()).foregroundStyle(ChessMeStyle.muted).frame(height: 74).padding(.vertical, 8)
            GeometryReader { geometry in
                Canvas { context, size in
                    let sorted = assessments.sorted { $0.ply < $1.ply }
                    let layout = EvaluationTimelineGeometry(size: size, totalPlies: totalPlies)
                    var zero = Path()
                    zero.move(to: CGPoint(x: 0, y: size.height / 2))
                    zero.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    context.stroke(zero, with: .color(ChessMeStyle.muted.opacity(0.25)), lineWidth: 1)
                    var line = Path()
                    for (index, assessment) in sorted.enumerated() {
                        if index == 0 || assessment.ply - sorted[index - 1].ply > 2 { line.move(to: layout.point(for: assessment)) }
                        else { line.addLine(to: layout.point(for: assessment)) }
                    }
                    context.stroke(line, with: .color(ChessMeStyle.green.opacity(highlightedQuality == nil ? 1 : 0.3)), lineWidth: 2)
                    for assessment in sorted {
                        let matches = highlightedQuality == assessment.quality
                        let p = layout.point(for: assessment), radius: CGFloat = matches || assessment.ply + 1 == selectedPly ? 5 : 3
                        let dot = Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
                        let color: Color = assessment.quality == .blunder || assessment.quality == .mistake ? .red : assessment.quality == .inaccuracy ? .orange : ChessMeStyle.green
                        context.fill(dot, with: .color(color.opacity(highlightedQuality == nil || matches ? 1 : 0.18)))
                        if matches {
                            context.stroke(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color(color), lineWidth: 1)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let candidates = highlightedQuality.map { quality in assessments.filter { $0.quality == quality } } ?? assessments
                    if let nearest = EvaluationTimelineGeometry(size: geometry.size, totalPlies: totalPlies).nearest(to: location.x, assessments: candidates) { onSelect(nearest.ply + 1) }
                }
                .accessibilityHidden(true)
            }.frame(height: 90)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Evaluation graph")
                .accessibilityValue(highlightedQuality.map { quality in
                    let count = assessments.filter { $0.quality == quality }.count
                    return "\(count) \(quality.title) \(count == 1 ? "move" : "moves") highlighted"
                } ?? "All reviewed moves")
                .accessibilityIdentifier("game.evaluationPlot")
                .accessibilityAdjustableAction { direction in
                    let candidates = assessments.filter { highlightedQuality == nil || $0.quality == highlightedQuality }.sorted { $0.ply < $1.ply }
                    let next = direction == .increment ? candidates.first { $0.ply + 1 > selectedPly } : candidates.last { $0.ply + 1 < selectedPly }
                    if let next { onSelect(next.ply + 1) }
                }
            }
            HStack {
                Text("Start")
                Spacer()
                Text("\(totalPlies) plies")
            }.font(.caption2).foregroundStyle(ChessMeStyle.muted)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("game.evaluationTimeline")
    }
}
