import SwiftUI
import ChessMeCore

struct PracticeView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                BrandHeader(title: "Practice", tab: .practice)
                SampleNotice()
                PaperCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("From your games").font(ChessMeStyle.title(24))
                        Text("\(model.allDuePuzzles.count) \(model.allDuePuzzles.count == 1 ? "position" : "positions") ready").font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                        if !model.allPuzzles.isEmpty {
                            PrimaryButton(title: "Start practice", symbol: "play.fill") { model.startSession(allSaved: true) }
                                .accessibilityIdentifier("practice.start")
                        } else {
                            Text("Review a game to find moves to practise.").font(.subheadline)
                            Button("View games") { model.selectedTab = AppTab.games.rawValue }.frame(minHeight: 44)
                        }
                    }
                }
                NavigationLink { PuzzlesView() } label: {
                    destination("Related puzzles", detail: "Lichess puzzles matched to your games", symbol: "puzzlepiece.extension")
                }.accessibilityIdentifier("practice.puzzles")
                NavigationLink { FavoritesView() } label: {
                    destination("Saved positions", detail: "Lessons and puzzles you've kept", symbol: "heart")
                }.accessibilityIdentifier("practice.saved")
                NavigationLink { OpeningCoachView() } label: {
                    destination("Opening practice", detail: "Learn from repeated early decisions", symbol: "flag.checkered")
                }.accessibilityIdentifier("openings.open")
                if !model.allPuzzles.isEmpty {
                    Text("Your positions").font(ChessMeStyle.title(22))
                    ForEach(model.allPuzzles) { finding in
                        Button { model.openLesson(finding) } label: {
                            HStack(alignment: .top, spacing: 14) {
                                ChessBoardView(position: (try? ChessPosition(fen: finding.positionFEN)) ?? .initial)
                                    .frame(width: 64, height: 64).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(finding.theme).font(.subheadline.weight(.semibold))
                                    Text("Move \(finding.moveNumber) · \(finding.gameLabel)").font(.caption).foregroundStyle(ChessMeStyle.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }.foregroundStyle(ChessMeStyle.ink)
                        }.buttonStyle(.plain).accessibilityIdentifier("practice.lesson.\(finding.id)")
                        Divider()
                    }
                }
            }.padding(24)
        }.background(ChessMeStyle.paper).toolbar(.hidden, for: .navigationBar)
            .accessibilityIdentifier("practice.scroll")
    }
    private func destination(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(ChessMeStyle.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption)
        }.foregroundStyle(ChessMeStyle.ink).padding(.vertical, 8).frame(minHeight: 56)
    }
}
