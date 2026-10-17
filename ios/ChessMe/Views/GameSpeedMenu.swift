import SwiftUI
import ChessMeCore

struct GameSpeedMenu: View {
    @Binding var selection: GameSpeedFilter
    var identifier = "games.speed"
    var body: some View {
        Menu {
            ForEach(GameSpeedFilter.allCases) { filter in
                Button { selection = filter } label: {
                    Label(filter.title, systemImage: selection == filter ? "checkmark" : "clock")
                }.accessibilityIdentifier("\(identifier).\(filter.rawValue)")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(selection.title)
                Image(systemName: "chevron.down").font(.caption2)
            }.font(.subheadline).fixedSize().padding(.horizontal, 10).frame(minHeight: 44)
                .foregroundStyle(selection == .all ? ChessMeStyle.ink : .white)
                .background(selection == .all ? ChessMeStyle.ink.opacity(0.05) : ChessMeStyle.green, in: Capsule())
        }.accessibilityLabel("Time control").accessibilityValue(selection.title).accessibilityIdentifier(identifier)
    }
}
