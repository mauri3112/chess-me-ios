import SwiftUI
import ChessMeCore

struct FavoritesView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if model.favoriteFindings.isEmpty && model.favoritePuzzles.isEmpty {
                    Text("Tap the heart on a lesson or puzzle to save it here. Saved games are in Games.").font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                }
                if !model.favoriteFindings.isEmpty { Text("Lessons and review moments").font(ChessMeStyle.title(22)) }
                ForEach(model.favoriteFindings) { finding in
                    HStack {
                        if finding.isPuzzle {
                            Button { model.openLesson(finding) } label: { findingLabel(finding) }
                        } else {
                            NavigationLink { ReviewCardView(finding: finding) } label: { findingLabel(finding) }
                        }
                        Spacer()
                        FavoriteButton(selected: true) { model.toggleFavorite(finding) }
                    }
                    Divider()
                }
                if !model.favoritePuzzles.isEmpty { Text("Lichess puzzles").font(ChessMeStyle.title(22)) }
                ForEach(model.favoritePuzzles) { puzzle in PuzzleRow(puzzle: puzzle); Divider() }
            }.padding(24)
        }.background(ChessMeStyle.paper).navigationTitle("Saved positions").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .accessibilityIdentifier("favorites.scroll")
    }
    private func findingLabel(_ finding: MoveFinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(finding.theme).font(.subheadline.weight(.semibold))
            Text("Move \(finding.moveNumber) · \(finding.gameLabel)").font(.caption).foregroundStyle(ChessMeStyle.muted)
            Text("\(finding.source.capitalized) review\(model.isDemo ? " · sample" : "")").font(.caption2).foregroundStyle(ChessMeStyle.muted)
        }.foregroundStyle(ChessMeStyle.ink)
    }
}
