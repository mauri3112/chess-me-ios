import SwiftUI
import ChessMeCore

struct GameAnalysisIndicator: View {
    let game: ChessGame
    @EnvironmentObject private var model: AppModel
    @Environment(\.chessReduceMotion) private var reduceMotion
    private var job: LocalAnalysisJob? { model.localAnalysisJob(for: game.id, includingOrdinary: true) }
    private var review: GameAnalysis? { model.gameAnalysis(for: game.id) }
    private var active: Bool { job?.isPending == true }
    private var running: Bool { active && job?.state == .running }
    private var progress: Double { min(1, max(0, max(job?.progress ?? 0, running ? model.progress : 0))) }
    private var sourceSymbol: String { review?.source == "cloud" ? "cloud.fill" : "iphone" }
    private var status: String {
        if running { return "Device analysis, \(Int(progress * 100)) percent" }
        if active { return job?.nightOnly == true ? "Night analysis queued on this device" : "Analysis queued on this device" }
        if review?.isComplete == true { return "\(review?.source == "cloud" ? "Cloud" : "Device") review ready" }
        if job?.state == .paused { return "Device analysis paused" }
        if job?.state == .failed { return "Device analysis needs attention" }
        if let cloud = model.cloudReview(for: game.id), cloud.isPending { return "Cloud analysis queued" }
        return "Not analyzed yet"
    }
    var body: some View {
        ZStack {
            Circle().fill(ChessMeStyle.green.opacity(0.06))
            if running {
                Circle().stroke(ChessMeStyle.green.opacity(0.12), lineWidth: 3)
                Circle().trim(from: 0, to: progress).stroke(ChessMeStyle.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90)).animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: progress)
                Text("\(Int(progress * 100))%").font(.system(size: 10, weight: .bold, design: .rounded))
            } else if active && job?.nightOnly != true {
                QueueSpinner(reduceMotion: reduceMotion)
                Image(systemName: "hourglass").font(.system(size: 14, weight: .medium))
            } else {
                Image(systemName: active ? "moon.fill" : review?.isComplete == true ? "checkmark" : job?.state == .paused ? "pause.fill" : job?.state == .failed ? "exclamationmark" : "circle.dashed")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(review?.isComplete == true || active ? ChessMeStyle.green : ChessMeStyle.muted)
            }
        }
        .frame(width: 42, height: 42).foregroundStyle(ChessMeStyle.green)
        .overlay(alignment: .bottomTrailing) {
            if review != nil {
                Image(systemName: sourceSymbol).font(.system(size: 10, weight: .semibold))
                    .padding(3).background(ChessMeStyle.paper, in: Circle()).foregroundStyle(ChessMeStyle.muted)
            } else if model.cloudReview(for: game.id)?.isPending == true {
                Image(systemName: "cloud.fill").font(.system(size: 12)).foregroundStyle(ChessMeStyle.muted)
            }
        }
        .overlay(alignment: .topTrailing) {
            if active && review?.isComplete == true {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(ChessMeStyle.green)
                    .background(ChessMeStyle.paper, in: Circle())
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(status)
        .accessibilityValue(active && review?.isComplete == true ? "Saved review ready; deeper review pending" : "")
        .accessibilityIdentifier("library.analysis.\(game.id)")
    }
}

private struct QueueSpinner: View {
    let reduceMotion: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { context in
            Circle().stroke(ChessMeStyle.green.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
                .rotationEffect(.degrees(reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 70))
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct GameOutcomeBadge: View {
    let outcome: PlayerGameOutcome
    var body: some View {
        Label(outcome.title, systemImage: outcome.symbol).font(.caption2.weight(.semibold))
            .foregroundStyle(outcome.color).padding(.horizontal, 7).padding(.vertical, 4)
            .background(outcome.color.opacity(0.09), in: Capsule())
            .accessibilityLabel("You \(outcome == .draw ? "drew" : outcome.rawValue)")
    }
}
