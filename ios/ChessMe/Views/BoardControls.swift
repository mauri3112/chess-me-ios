import SwiftUI

struct BoardIconButton: View {
    let title: String
    let symbol: String
    var action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(ChessMeStyle.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).foregroundStyle(ChessMeStyle.green).opacity(enabled ? 1 : 0.35)
            .accessibilityLabel(title)
    }
}
