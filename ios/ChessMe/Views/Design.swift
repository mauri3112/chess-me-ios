import SwiftUI
import ChessMeCore

enum ChessMeStyle {
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.92)
    static let ink = Color(red: 0.12, green: 0.21, blue: 0.17)
    static let green = Color(red: 0.18, green: 0.37, blue: 0.28)
    static let muted = Color(red: 0.40, green: 0.45, blue: 0.41)
    static let gold = Color(red: 0.76, green: 0.53, blue: 0.18)
    static func title(_ size: CGFloat) -> Font { .custom("Georgia", size: size, relativeTo: .largeTitle) }
}

struct PrimaryButton: View {
    let title: String
    var symbol: String = "arrow.right"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer()
                Image(systemName: symbol)
            }
            .padding(.horizontal, 20).padding(.vertical, 17)
            .foregroundStyle(.white)
            .background(ChessMeStyle.green, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.semibold)).tracking(2).foregroundStyle(ChessMeStyle.muted)
    }
}

struct PaperCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(ChessMeStyle.ink.opacity(0.08), lineWidth: 1))
    }
}

extension ReviewWindow {
    var shortLabel: String {
        switch self { case .day: "24h"; case .week: "7 days"; case .month: "30 days"; case .year: "365 days" }
    }
    var accessibilityKey: String {
        switch self { case .day: "24h"; case .week: "7d"; case .month: "30d"; case .year: "365d" }
    }
}

/// Make the label and chevron one target, including when nested in a Form.
struct FullRowDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { configuration.isExpanded.toggle() } } label: {
                HStack {
                    configuration.label
                    Spacer()
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right").font(.caption.weight(.semibold))
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded { configuration.content }
        }.accessibilityElement(children: .contain)
    }
}
