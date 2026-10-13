import SwiftUI
import ChessMeCore

struct LogoFramePreference: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
private struct LaunchLogoHiddenKey: EnvironmentKey { static let defaultValue = false }
private struct ChessReduceMotionKey: EnvironmentKey { static let defaultValue: Bool? = nil }
extension EnvironmentValues {
    var chessReduceMotion: Bool {
        get { self[ChessReduceMotionKey.self] ?? accessibilityReduceMotion }
        set { self[ChessReduceMotionKey.self] = newValue }
    }
    var launchLogoHidden: Bool {
        get { self[LaunchLogoHiddenKey.self] }
        set { self[LaunchLogoHiddenKey.self] = newValue }
    }
}

struct AppLaunchAnimation: View {
    let target: CGRect
    let size: CGSize
    let docked: Bool
    @Environment(\.chessReduceMotion) private var reduceMotion
    private var moving: Bool { docked && !reduceMotion }
    private var center: CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.40) }
    var body: some View {
        ZStack(alignment: .topLeading) {
            ChessMeStyle.paper.ignoresSafeArea().opacity(docked ? 0 : 1)
                .animation(reduceMotion ? .easeOut(duration: 0.18) : .easeOut(duration: 0.35).delay(0.5), value: docked)
            Text("chess-me").font(ChessMeStyle.title(38)).foregroundStyle(ChessMeStyle.ink)
                .position(x: center.x, y: center.y - 145).opacity(docked ? 0 : 1)
                .animation(.easeOut(duration: reduceMotion ? 0.18 : 0.25), value: docked)
            ZStack {
                launchBoard.frame(width: 210, height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .opacity(docked ? 0 : 1)
                    .animation(.easeOut(duration: reduceMotion ? 0.18 : 0.6), value: docked)
                ChessPieceView(piece: Piece(kind: .rook, side: .black))
                    .environment(\.chessBoardDesign, .classic).frame(width: 125, height: 125)
                    .opacity(reduceMotion && docked ? 0 : 1)
            }
            .frame(width: 210, height: 210)
            .scaleEffect(moving ? target.width / 125 : 1)
            .position(moving ? CGPoint(x: target.midX, y: target.midY) : center)
        }
        .allowsHitTesting(false).accessibilityHidden(true).accessibilityIdentifier("app.launchAnimation")
    }
    private var launchBoard: some View {
        GeometryReader { geometry in
            Canvas { context, _ in
                let cell = geometry.size.width / 8
                for rank in 0..<8 {
                    for file in 0..<8 {
                        let rect = CGRect(x: CGFloat(file) * cell, y: CGFloat(rank) * cell, width: cell, height: cell)
                        context.fill(Path(rect), with: .color((rank + file).isMultiple(of: 2) ? ChessBoardDesign.classic.lightSquare : ChessBoardDesign.classic.darkSquare))
                    }
                }
            }
        }
    }
}
