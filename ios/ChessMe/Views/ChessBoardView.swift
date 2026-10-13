import SwiftUI
import ChessMeCore

struct BoardArrow: Equatable {
    let move: ChessMove
    var rank = 0
}

struct BoardMoveMarker: Equatable {
    let square: Int
    let quality: MoveQuality
    var color: Color { quality == .blunder || quality == .mistake ? .red : .orange }
    var symbol: String { quality == .blunder ? "??" : "?" }
}

private struct AnimatedBoardPiece: Identifiable {
    let id: UUID
    let piece: Piece
    var square: Int
}

struct ChessBoardView: View {
    let position: ChessPosition
    var perspective: Side = .white
    var selectedSquare: Int?
    var targets: Set<Int> = []
    var highlightedSquares: Set<Int> = []
    var arrows: [BoardArrow] = []
    var moveMarker: BoardMoveMarker?
    var suggestions: [PracticeMoveSuggestion] = []
    var rejectionCount = 0
    var onSquare: ((Int) -> Void)?
    @Environment(\.chessBoardDesign) private var design
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pieces: [AnimatedBoardPiece] = []

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width / 8
            ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { column in
                            let file = perspective == .white ? column : 7 - column
                            let rank = perspective == .white ? 7 - row : row
                            let square = rank * 8 + file
                            let name = "\(String(UnicodeScalar(97 + file)!))\(rank + 1)"
                            let piece = position.squares[square]
                            let destination = suggestions.first { $0.move.to == square }
                            let origin = suggestions.first { $0.move.from == square }
                            let cell = ZStack {
                                ((rank + file) % 2 == 0 ? design.darkSquare : design.lightSquare)
                                if selectedSquare == square || highlightedSquares.contains(square) { ChessMeStyle.gold.opacity(0.55) }
                                if moveMarker?.square == square { moveMarker!.color.opacity(0.24) }
                                if let destination { destination.color.opacity(destination.quality == .best ? 0.65 : 0.38) }
                                if let origin {
                                    Circle().strokeBorder(origin.color, lineWidth: max(2, size * 0.06))
                                        .padding(size * 0.06)
                                }
                                if targets.contains(square) {
                                    Circle().fill(design.ink.opacity(0.28)).frame(width: size * 0.23, height: size * 0.23)
                                }
                                if size >= 28 {
                                    VStack {
                                        if column == 0 {
                                            HStack { Text("\(rank + 1)"); Spacer() }
                                        }
                                        Spacer(minLength: 0)
                                        if row == 7 {
                                            HStack { Spacer(); Text(String(UnicodeScalar(97 + file)!)) }
                                        }
                                    }
                                    .font(.system(size: max(8, size * 0.16), weight: .semibold))
                                    .foregroundStyle(design.ink.opacity(0.7)).padding(2)
                                }
                            }
                            .frame(width: size, height: size)

                            Group {
                                if let onSquare {
                                    Button { onSquare(square) } label: { cell }
                                        .buttonStyle(.plain)
                                } else {
                                    cell.accessibilityElement(children: .ignore)
                                }
                            }
                            .accessibilityIdentifier("board.square.\(name)")
                            .accessibilityLabel("\(name), \(piece.map { "\($0.side.rawValue) \($0.kind.rawValue)" } ?? "empty")")
                            .accessibilityValue(squareAccessibilityValue(square, destination: destination, origin: origin))
                            .accessibilityHint(targets.contains(square) ? "Legal destination" : "")
                        }
                    }
                }
            }
            ForEach(pieces) { item in
                ChessPieceView(piece: item.piece).frame(width: size, height: size)
                    .position(center(item.square, size: size))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            ForEach(suggestions, id: \.move.uci) { suggestion in
                Text(suggestion.mark).font(.system(size: max(10, size * 0.25), weight: .black))
                    .foregroundStyle(.white).frame(width: size * 0.36, height: size * 0.36)
                    .background(suggestion.color, in: RoundedRectangle(cornerRadius: 5))
                    .position(x: center(suggestion.move.to, size: size).x + size * 0.28,
                              y: center(suggestion.move.to, size: size).y - size * 0.28)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            if let marker = moveMarker {
                Text(marker.symbol).font(.system(size: max(10, size * 0.25), weight: .black))
                    .foregroundStyle(.white).frame(width: size * 0.4, height: size * 0.4)
                    .background(marker.color, in: Circle())
                    .position(x: center(marker.square, size: size).x + size * 0.28,
                              y: center(marker.square, size: size).y - size * 0.28)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            Canvas { context, _ in
                for arrow in arrows.reversed() {
                    let start = center(arrow.move.from, size: size), end = center(arrow.move.to, size: size)
                    let angle = atan2(end.y - start.y, end.x - start.x)
                    let tip = CGPoint(x: end.x - cos(angle) * size * 0.1, y: end.y - sin(angle) * size * 0.1)
                    var line = Path()
                    line.move(to: start)
                    line.addLine(to: CGPoint(x: tip.x - cos(angle) * size * 0.15, y: tip.y - sin(angle) * size * 0.15))
                    let color = (arrow.rank == 0 ? ChessMeStyle.green : ChessMeStyle.gold).opacity(arrow.rank == 0 ? 0.85 : 0.65)
                    context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                    var head = Path()
                    head.move(to: tip)
                    head.addLine(to: CGPoint(x: tip.x - cos(angle - .pi / 6) * size * 0.37, y: tip.y - sin(angle - .pi / 6) * size * 0.37))
                    head.addLine(to: CGPoint(x: tip.x - cos(angle + .pi / 6) * size * 0.37, y: tip.y - sin(angle + .pi / 6) * size * 0.37))
                    head.closeSubpath()
                    context.fill(head, with: .color(color))
                }
            }.allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .modifier(BoardShake(count: reduceMotion ? 0 : CGFloat(rejectionCount)))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: rejectionCount)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(design.title) chessboard")
        .accessibilityValue(suggestions.isEmpty ? (arrows.isEmpty ? "No engine suggestions" : "\(arrows.count) engine suggestions") : "\(suggestions.count) good move highlights")
        .accessibilityIdentifier("board.design.\(design.rawValue)")
        .onAppear { reconcile(animate: false) }
        .onChange(of: position) { _, _ in reconcile(animate: true) }
    }

    private func squareAccessibilityValue(_ square: Int, destination: PracticeMoveSuggestion?, origin: PracticeMoveSuggestion?) -> String {
        if selectedSquare == square { return "Selected" }
        if targets.contains(square) { return "Legal destination" }
        if let destination { return "\(destination.quality.title) destination" }
        if let origin { return "\(origin.quality.title) piece" }
        if let marker = moveMarker, marker.square == square {
            return "Original \(marker.quality.title.lowercased()) destination"
        }
        return ""
    }

    private func center(_ square: Int, size: CGFloat) -> CGPoint {
        let column = perspective == .white ? square % 8 : 7 - square % 8
        let row = perspective == .white ? 7 - square / 8 : square / 8
        return CGPoint(x: (CGFloat(column) + 0.5) * size, y: (CGFloat(row) + 0.5) * size)
    }

    private func reconcile(animate: Bool) {
        var available = pieces
        var next: [AnimatedBoardPiece] = []
        var unmatched: [(Int, Piece)] = []
        for (square, optional) in position.squares.enumerated() {
            guard let piece = optional else { continue }
            if let index = available.firstIndex(where: { $0.square == square && $0.piece == piece }) {
                next.append(available.remove(at: index))
            } else { unmatched.append((square, piece)) }
        }
        for (square, piece) in unmatched {
            if let index = available.indices.filter({ available[$0].piece == piece }).min(by: {
                abs(available[$0].square % 8 - square % 8) + abs(available[$0].square / 8 - square / 8) <
                abs(available[$1].square % 8 - square % 8) + abs(available[$1].square / 8 - square / 8)
            }) {
                var existing = available.remove(at: index)
                existing.square = square
                next.append(existing)
            } else { next.append(AnimatedBoardPiece(id: UUID(), piece: piece, square: square)) }
        }
        withAnimation(animate && !reduceMotion ? .easeInOut(duration: 0.22) : nil) { pieces = next }
    }
}
