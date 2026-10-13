import SwiftUI
import ChessMeCore

struct MoveHistoryView: View {
    let history: MoveHistory
    let selectedIndex: Int
    var prefix = "history"
    var title: String? = "Move history"
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let title { Text(title).font(.caption.weight(.semibold)).foregroundStyle(ChessMeStyle.muted) }
                Spacer()
                Button { onSelect(max(0, selectedIndex - 1)) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 36) }
                    .disabled(selectedIndex <= 0).accessibilityLabel("Previous move").accessibilityIdentifier("\(prefix).previousMove")
                Button { onSelect(min(history.moves.count, selectedIndex + 1)) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 36) }
                    .disabled(selectedIndex >= history.moves.count).accessibilityLabel("Next move").accessibilityIdentifier("\(prefix).nextMove")
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(spacing: 6) {
                        ForEach(history.positions.indices, id: \.self) { index in
                            Button { onSelect(index) } label: {
                                Text(history.notation(at: index)).font(.caption.monospacedDigit())
                                    .padding(.horizontal, 10).padding(.vertical, 9)
                                    .background(selectedIndex == index ? ChessMeStyle.gold.opacity(0.3) : ChessMeStyle.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .id(index).accessibilityIdentifier("\(prefix).move.\(index)")
                            .accessibilityValue(selectedIndex == index ? "Current position" : "")
                        }
                    }
                }
                .onAppear { proxy.scrollTo(selectedIndex, anchor: .trailing) }
                .onChange(of: selectedIndex) { _, value in proxy.scrollTo(value, anchor: .trailing) }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("\(prefix).moveHistory")
    }
}

struct FavoriteButton: View {
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: selected ? "heart.fill" : "heart").frame(width: 44, height: 40)
        }.foregroundStyle(selected ? .red : ChessMeStyle.green)
            .accessibilityLabel(selected ? "Remove from favorites" : "Add to favorites")
            .accessibilityIdentifier("favorite.toggle")
    }
}
