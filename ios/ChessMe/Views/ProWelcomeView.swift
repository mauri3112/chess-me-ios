import SwiftUI
import ChessMeCore

struct ProWelcomeView: View {
    var restored = false
    var continueTitle = "Continue"
    let onContinue: () -> Void
    @Environment(\.chessReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    Circle().stroke(ChessMeStyle.gold.opacity(0.22), lineWidth: 1)
                        .frame(width: 164, height: 164)
                        .scaleEffect(appeared ? 1.05 : 0.7)
                    Circle().fill(ChessMeStyle.green).frame(width: 130, height: 130)
                    ChessPieceView(piece: Piece(kind: .rook, side: .white))
                        .frame(width: 90, height: 90)
                        .scaleEffect(appeared ? 1 : 0.65)
                    ForEach(0..<6, id: \.self) { index in
                        let angle = Double(index) * .pi / 3 - .pi / 2
                        Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "circle.fill")
                            .font(.system(size: index.isMultiple(of: 2) ? 17 : 6, weight: .medium))
                            .foregroundStyle(ChessMeStyle.gold)
                            .offset(x: cos(angle) * (appeared ? 94 : 50), y: sin(angle) * (appeared ? 86 : 45))
                            .opacity(appeared ? 1 : 0)
                    }
                }.frame(height: 190).accessibilityHidden(true)
                VStack(spacing: 10) {
                    Text(restored ? "Welcome back to Pro" : "Welcome to Pro")
                        .font(ChessMeStyle.title(34)).multilineTextAlignment(.center)
                        .accessibilityIdentifier("proWelcome.title")
                    Text(restored ? "Your subscription is restored. Your Pro benefits are ready." :
                         "Congratulations, and thank you for supporting ChessMe.")
                        .font(.subheadline).foregroundStyle(ChessMeStyle.muted).multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 22) {
                    benefit("A year of game history", detail: "Choose 7, 30 or 365 days of your games.", symbol: "calendar")
                    benefit("More games to learn from", detail: "Build personal practice from your expanded history.", symbol: "scope")
                    benefit("30 cloud reviews a month", detail: "Deeper reviews of games you choose. Resets each UTC month.", symbol: "cloud")
                    benefit("Your reviews, ready offline", detail: "Keep downloaded reviews and return to them anytime.", symbol: "arrow.down.circle")
                }.padding(22).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
            }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 24)
                .opacity(appeared ? 1 : 0)
        }
        .background(ChessMeStyle.paper)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: continueTitle, symbol: "arrow.right", action: onContinue)
                .accessibilityIdentifier("proWelcome.continue")
                .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 12)
                .background(ChessMeStyle.paper)
        }
        .task {
            if reduceMotion { appeared = true }
            else { withAnimation(.spring(response: 0.65, dampingFraction: 0.76)) { appeared = true } }
        }
        .sensoryFeedback(.success, trigger: appeared)
    }

    private func benefit(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 21)).foregroundStyle(ChessMeStyle.green)
                .frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(ChessMeStyle.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
