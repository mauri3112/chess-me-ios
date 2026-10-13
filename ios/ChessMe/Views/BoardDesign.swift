import SwiftUI
import ChessMeCore

enum ChessBoardDesign: String, CaseIterable, Identifiable {
    case classic, slate, clay

    static let preferenceKey = "boardDesign"
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var description: String {
        switch self {
        case .classic: "Traditional pieces, ivory and sage"
        case .slate: "Geometric pieces, cloud and slate"
        case .clay: "Rounded pieces, linen and clay"
        }
    }

    var lightSquare: Color {
        switch self {
        case .classic: Self.color(0xE9E5DA)
        case .slate: Self.color(0xE5E9EF)
        case .clay: Self.color(0xF2E4D2)
        }
    }

    var darkSquare: Color {
        switch self {
        case .classic: Self.color(0x86A391)
        case .slate: Self.color(0x8196AE)
        case .clay: Self.color(0xBA9078)
        }
    }

    var ink: Color {
        switch self {
        case .classic: Self.color(0x25352E)
        case .slate: Self.color(0x263549)
        case .clay: Self.color(0x4D3931)
        }
    }

    func assetName(for piece: Piece) -> String {
        "piece-\(rawValue)-\(piece.side.rawValue)-\(piece.kind.rawValue)"
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}

private struct ChessBoardDesignKey: EnvironmentKey {
    static let defaultValue: ChessBoardDesign = .classic
}

extension EnvironmentValues {
    var chessBoardDesign: ChessBoardDesign {
        get { self[ChessBoardDesignKey.self] }
        set { self[ChessBoardDesignKey.self] = newValue }
    }
}

struct ChessPieceView: View {
    let piece: Piece
    var tint: Color?
    @Environment(\.chessBoardDesign) private var design

    private var artwork: some View {
        Image(design.assetName(for: piece))
            .renderingMode(.original)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
    var body: some View {
        Group {
            if let tint {
                if piece.side == .white { artwork.colorMultiply(tint) }
                else { artwork.overlay { Rectangle().fill(tint).blendMode(BlendMode.screen) }.mask(artwork).compositingGroup() }
            } else { artwork }
        }.accessibilityHidden(true)
    }
}
