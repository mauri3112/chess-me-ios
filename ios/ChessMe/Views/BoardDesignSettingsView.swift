import SwiftUI
import ChessMeCore

struct BoardDesignSettingsView: View {
    @AppStorage(ChessBoardDesign.preferenceKey) private var storedDesign = ChessBoardDesign.classic.rawValue

    private var selectedDesign: ChessBoardDesign {
        ChessBoardDesign(rawValue: storedDesign) ?? .classic
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Eyebrow(text: "Board and pieces")
                ChessBoardView(position: .initial)
                    .environment(\.chessBoardDesign, selectedDesign)
                    .padding(10)
                    .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))

                VStack(spacing: 12) {
                    ForEach(ChessBoardDesign.allCases) { design in
                        Button { storedDesign = design.rawValue } label: {
                            HStack(spacing: 14) {
                                HStack(spacing: 0) {
                                    ChessPieceView(piece: Piece(kind: .knight, side: .white))
                                        .background(design.lightSquare)
                                    ChessPieceView(piece: Piece(kind: .knight, side: .black))
                                        .background(design.darkSquare)
                                }
                                .environment(\.chessBoardDesign, design)
                                .frame(width: 88, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(design.title).font(.subheadline.weight(.semibold))
                                    Text(design.description).font(.caption).foregroundStyle(ChessMeStyle.muted)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: selectedDesign == design ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedDesign == design ? ChessMeStyle.green : ChessMeStyle.muted.opacity(0.5))
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(ChessMeStyle.ink)
                            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selectedDesign == design ? ChessMeStyle.green : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(design.title)
                        .accessibilityValue(selectedDesign == design ? "Selected" : "Not selected")
                        .accessibilityAddTraits(selectedDesign == design ? .isSelected : [])
                        .accessibilityIdentifier("design.option.\(design.rawValue)")
                    }
                }

                Text("Your choice applies to every board and is saved on this device.")
                    .font(.footnote).foregroundStyle(ChessMeStyle.muted)
            }
            .padding(20)
        }
        .background(ChessMeStyle.paper)
        .navigationTitle("Design")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("design.scroll")
    }
}
