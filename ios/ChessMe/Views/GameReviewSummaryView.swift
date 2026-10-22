import SwiftUI
import ChessMeCore

struct GameReviewSummaryView: View {
    let summary: GameReviewSummary
    let source: String
    let onSelect: (Int) -> Void
    @State private var selectedPly = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 14) {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) { heading }
                } else {
                    HStack { heading }
                }
                if summary.classifiedCount > 0 {
                    GeometryReader { geometry in
                        HStack(spacing: 3) {
                            ForEach(GameReviewSummary.Group.allCases, id: \.self) { group in
                                let count = summary.count(group)
                                if count > 0 {
                                    Capsule().fill(color(group))
                                        .frame(width: max(0, geometry.size.width - CGFloat(visibleGroups - 1) * 3) * CGFloat(count) / CGFloat(summary.classifiedCount))
                                }
                            }
                        }
                    }.frame(height: 10).accessibilityHidden(true)
                    if typeSize.isAccessibilitySize {
                        stackedCounts
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 14) { counts }
                            stackedCounts
                        }
                    }
                }
                EvaluationTimeline(assessments: summary.assessments, totalPlies: summary.totalPlies,
                                   selectedPly: selectedPly, source: source,
                                   title: "White\u{00A0}+ / Black\u{00A0}−", endLabel: "Last move",
                                   accessibilitySelection: selectedMove.map { "Selected: \($0). Adjust to choose a move, then use Explore." },
                                   onAdjust: { selectedPly = $0 }) { selectedPly = $0; onSelect($0) }
                if let selectedMove {
                    Button("Explore \(selectedMove)") { onSelect(selectedPly) }
                        .font(.caption.weight(.semibold)).frame(minHeight: 44)
                        .accessibilityIdentifier("review.exploreSelected")
                } else {
                    Text("Tap the graph to explore a move").font(.caption).foregroundStyle(ChessMeStyle.muted)
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("review.visualSummary")
    }

    private var visibleGroups: Int { GameReviewSummary.Group.allCases.filter { summary.count($0) > 0 }.count }
    @ViewBuilder private var heading: some View {
        Text("Your moves").font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        if !typeSize.isAccessibilitySize { Spacer() }
        Text("\(summary.classifiedCount) assessed").font(.caption).foregroundStyle(ChessMeStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var selectedMove: String? {
        guard let assessment = summary.assessments.first(where: { $0.ply + 1 == selectedPly }),
              let position = try? ChessPosition(fen: assessment.positionFEN) else { return nil }
        return "move \(position.fullmoveNumber) · \(position.sideToMove.rawValue)"
    }
    private var counts: some View {
        ForEach(GameReviewSummary.Group.allCases, id: \.self) { group in
            VStack(alignment: .leading, spacing: 4) {
                Text("\(summary.count(group))").font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(color(group))
                Text(group.title).font(.caption).foregroundStyle(ChessMeStyle.muted).fixedSize()
            }.frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(group.title): \(summary.count(group))")
        }
    }
    private var stackedCounts: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(GameReviewSummary.Group.allCases, id: \.self) { group in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(group.title).font(.caption).foregroundStyle(ChessMeStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text("\(summary.count(group))").font(.title3.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(color(group)).fixedSize()
                }.accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(group.title): \(summary.count(group))")
                    .accessibilityIdentifier("review.count.\(group.rawValue)")
            }
        }
    }
    private func color(_ group: GameReviewSummary.Group) -> Color {
        switch group {
        case .sound: ChessMeStyle.green
        case .book: ChessMeStyle.muted
        case .inaccuracy: Color(red: 0.64, green: 0.42, blue: 0.10)
        case .mistake: Color(red: 0.76, green: 0.31, blue: 0.13)
        case .blunder: Color(red: 0.68, green: 0.19, blue: 0.20)
        }
    }
}

struct ReviewCompletionRing: View {
    let visited: Int
    let total: Int
    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(ChessMeStyle.green.opacity(0.12), lineWidth: 7)
                Circle().trim(from: 0, to: total > 0 ? min(1, CGFloat(visited) / CGFloat(total)) : 0)
                    .stroke(ChessMeStyle.green, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(visited)/\(total)").font(.system(size: 20, weight: .semibold)).monospacedDigit()
            }.frame(width: 74, height: 74).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(total > 0 && visited == total ? "Review complete" : "Your review so far").font(ChessMeStyle.title(25))
                Text(visited == total && total > 0 ? "\(total) \(total == 1 ? "moment" : "moments") viewed" : "\(visited) of \(total) moments viewed")
                    .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                    .accessibilityIdentifier("review.visitedCount")
            }
        }.padding(.vertical, 6)
    }
}
