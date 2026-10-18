import SwiftUI
import ChessMeCore

struct GameSpeedIcon: View {
    let speed: GameSpeed
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 16

    var body: some View {
        Group {
            switch speed {
            case .bullet: BulletSpeedShape().fill()
            case .blitz: Image(systemName: "flame.fill").resizable().scaledToFit()
            case .rapid: Image(systemName: "hare.fill").resizable().scaledToFit()
            case .classical: Image(systemName: "tortoise.fill").resizable().scaledToFit()
            case .unknown: Image(systemName: "clock.badge.questionmark").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(speed.title)
        .help(speed.title)
    }
}

private struct BulletSpeedShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 8, y: 7))
        path.addLine(to: CGPoint(x: 15, y: 7))
        path.addQuadCurve(to: CGPoint(x: 23, y: 12), control: CGPoint(x: 20, y: 7))
        path.addQuadCurve(to: CGPoint(x: 15, y: 17), control: CGPoint(x: 20, y: 17))
        path.addLine(to: CGPoint(x: 8, y: 17))
        path.closeSubpath()
        path.addRoundedRect(in: CGRect(x: 5, y: 7, width: 2, height: 10), cornerSize: CGSize(width: 0.5, height: 0.5))
        path.addRoundedRect(in: CGRect(x: 0, y: 8, width: 4, height: 2), cornerSize: CGSize(width: 1, height: 1))
        path.addRoundedRect(in: CGRect(x: 1, y: 14, width: 3, height: 2), cornerSize: CGSize(width: 1, height: 1))
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

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
