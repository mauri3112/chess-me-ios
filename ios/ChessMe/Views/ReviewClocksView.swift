import SwiftUI
import ChessMeCore

struct ReviewClocksView: View {
    let game: ChessGame
    let timeline: GameClockTimeline?
    let history: MoveHistory
    let index: Int
    let isVariation: Bool
    let loading: Bool
    let error: String?
    let retry: () -> Void

    private var snapshot: GameClockSnapshot? {
        guard let timeline, timeline.snapshots.indices.contains(index) else { return nil }
        return timeline.snapshots[index]
    }
    private var timing: GameMoveTiming? {
        guard let timeline, index > 0, timeline.moves.indices.contains(index - 1) else { return nil }
        return timeline.moves[index - 1]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(isVariation ? "Clocks at variation start" : index == 0 ? "Starting clocks" : "Clocks after move")
                Spacer()
                if let control = game.clockData?.timeControl { Text(control) }
            }.font(.caption).foregroundStyle(ChessMeStyle.muted)
            HStack(spacing: 12) {
                clock(side: .white, name: game.white, remaining: snapshot?.white)
                clock(side: .black, name: game.black, remaining: snapshot?.black)
            }
            Group {
                if isVariation { Text("Exploring a variation · no recorded move times") }
                else if let timing {
                    let player = timing.side == .white ? "White" : "Black"
                    let available = timing.before.map { "\(GameClockData.clockLabel($0)) available" } ?? "clock unavailable"
                    let used = timing.firstMoveUntimed ? " · first move untimed" : timing.estimatedSpent.map { " · used ≈\(GameClockData.durationLabel($0))" } ?? ""
                    Text("\(history.notation(at: index)) · \(player) had \(available)\(used)")
                } else if timeline != nil { Text("Starting clocks · select a move to see its time") }
                else if loading { Text("Loading recorded clocks…") }
                else if error != nil {
                    HStack {
                        Text("Clocks could not be loaded.")
                        Button("Retry", action: retry).accessibilityIdentifier("game.clock.retry")
                    }
                } else { Text("No clock records are available for this game.") }
            }
            .font(.caption2).foregroundStyle(ChessMeStyle.muted)
            .frame(minHeight: 28, alignment: .topLeading)
            .accessibilityIdentifier("game.clock.moveTiming")
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("game.clocks")
    }

    private func clock(side: Side, name: String, remaining: Int?) -> some View {
        HStack(spacing: 7) {
            Circle().fill(side == .white ? Color.white : ChessMeStyle.ink)
                .overlay(Circle().stroke(ChessMeStyle.muted.opacity(0.4), lineWidth: 1)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(side == .white ? "White" : "Black").font(.caption2)
                Text(name).font(.caption2).lineLimit(1)
            }.foregroundStyle(ChessMeStyle.muted)
            Spacer(minLength: 2)
            Text(GameClockData.clockLabel(remaining)).font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(ChessMeStyle.ink).fixedSize()
        }
        .padding(9).frame(maxWidth: .infinity)
        .background(ChessMeStyle.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(side == .white ? "White" : "Black"), \(name), remaining clock")
        .accessibilityValue(remaining == nil ? "Unavailable" : GameClockData.clockLabel(remaining))
        .accessibilityIdentifier("game.clock.\(side.rawValue)")
    }
}
