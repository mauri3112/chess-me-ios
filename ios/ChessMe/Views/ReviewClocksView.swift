import SwiftUI
import ChessMeCore

struct ReviewClocksView: View {
    let game: ChessGame
    let timeline: GameClockTimeline?
    let index: Int
    let isVariation: Bool
    let loading: Bool
    let error: String?
    let retry: () -> Void

    private var snapshot: GameClockSnapshot? {
        guard let timeline, timeline.snapshots.indices.contains(index) else { return nil }
        return timeline.snapshots[index]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let control = game.clockData?.timeControl {
                Text(control).font(.caption).foregroundStyle(ChessMeStyle.muted)
            }
            HStack(spacing: 12) {
                clock(side: .white, name: game.white, remaining: snapshot?.white)
                clock(side: .black, name: game.black, remaining: snapshot?.black)
            }
            Group {
                if isVariation { Text("Exploring a variation · no recorded move times") }
                else if loading { Text("Loading recorded clocks…") }
                else if error != nil {
                    HStack {
                        Text("Clocks could not be loaded.")
                        Button("Retry", action: retry).accessibilityIdentifier("game.clock.retry")
                    }
                } else if timeline == nil { Text("No clock records are available for this game.") }
            }
            .font(.caption2).foregroundStyle(ChessMeStyle.muted)
            .accessibilityIdentifier("game.clock.moveTiming")
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("game.clocks")
    }

    private func clock(side: Side, name: String, remaining: Int?) -> some View {
        let label = side == game.playerSide ? "You" : name
        let foreground: Color = side == .white ? .white : .black
        return VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
            Text(GameClockData.clockLabel(remaining)).font(.system(.title3, design: .monospaced).weight(.semibold)).fixedSize()
            Text(lastMoveLabel(for: side)).font(.caption2)
                .accessibilityIdentifier("game.clock.lastMove.\(side.rawValue)")
        }
        .foregroundStyle(foreground).padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .background(side == .white ? ChessMeStyle.ink : .white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ChessMeStyle.ink.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label), \(side.rawValue), remaining clock")
        .accessibilityValue(remaining == nil ? "Unavailable" : GameClockData.clockLabel(remaining))
        .accessibilityIdentifier("game.clock.\(side.rawValue)")
    }

    private func lastMoveLabel(for side: Side) -> String {
        guard let timing = timeline?.lastMove(for: side, at: index) else {
            return index == 0 ? "No move yet" : "Last move unavailable"
        }
        if timing.firstMoveUntimed { return "First move untimed" }
        guard let spent = timing.estimatedSpent else { return "Last move time unavailable" }
        return "Last move ≈\(GameClockData.durationLabel(spent))"
    }
}
