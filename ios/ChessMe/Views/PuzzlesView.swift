import SwiftUI
import ChessMeCore

struct PuzzlesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var playingPuzzle: TrainingPuzzle?
    var body: some View {
        let puzzles = model.recommendedPuzzles
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                Text("Found \(puzzles.count) \(puzzles.count == 1 ? "puzzle" : "puzzles") related to positions in your games.")
                    .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                    .accessibilityIdentifier("puzzles.matchesSummary")
                if model.isDemo {
                    Label("Demo · sample puzzle", systemImage: "eye")
                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                }
                if let puzzle = model.nextRecommendedPuzzle {
                    PrimaryButton(title: "Play next puzzle", symbol: "play.fill") { playingPuzzle = puzzle }
                        .accessibilityIdentifier("puzzles.play")
                }
                HStack {
                    Spacer()
                    Button { Task { await model.refreshPuzzleMatches(force: true) } } label: {
                        Label("Refresh matches", systemImage: "arrow.clockwise")
                    }.font(.caption.weight(.semibold)).disabled(model.puzzlesLoading || model.isDemo)
                        .accessibilityIdentifier("puzzles.refresh")
                }
                if model.puzzlesLoading { ProgressView("Finding related puzzles…").font(.caption) }
                if !model.isDemo {
                    Text("\(model.puzzleMatchCoverage.checked)/\(model.puzzleMatchCoverage.total) reviewed games matched. Up to 3 puzzles per game.")
                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                }
                if let notice = model.puzzleNotice { Text(notice).font(.caption).foregroundStyle(ChessMeStyle.muted) }
                if model.recommendedPuzzles.isEmpty {
                    Text(model.library.games.isEmpty ? "Import completed games, then review them to get personal puzzle matches." : "Review your games to find teaching moments. Related puzzles appear here when matching completes.")
                        .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                    if model.library.games.isEmpty { PrimaryButton(title: "Import games", symbol: "arrow.down") { model.showConnection = true } }
                }
                ForEach(puzzles) { puzzle in
                    PuzzleRow(puzzle: puzzle)
                    Divider()
                }
                Link("Puzzles from Lichess · CC0", destination: URL(string: "https://database.lichess.org/#puzzles")!)
                    .font(.caption).foregroundStyle(ChessMeStyle.muted)
            }.padding(24)
        }.background(ChessMeStyle.paper).navigationTitle("Related puzzles").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .accessibilityIdentifier("puzzles.scroll")
            .navigationDestination(isPresented: Binding(get: { playingPuzzle != nil }, set: { if !$0 { playingPuzzle = nil } })) {
                if let playingPuzzle { PuzzleLessonView(puzzle: playingPuzzle) }
            }
            .task { if model.automaticPuzzleMatching { await model.refreshPuzzleMatches() } }
    }
}

struct PuzzleRow: View {
    let puzzle: TrainingPuzzle
    @EnvironmentObject private var model: AppModel
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NavigationLink { PuzzleLessonView(puzzle: puzzle) } label: {
                HStack(alignment: .top, spacing: 14) {
                    ChessBoardView(position: (try? ChessPosition(fen: puzzle.positionFEN)) ?? .initial)
                        .frame(width: 68, height: 68).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Level \(puzzle.rating) · Lichess").font(.subheadline.weight(.semibold))
                        if model.isDemo { Text("Sample puzzle").font(.caption).foregroundStyle(ChessMeStyle.muted) }
                        if let related = model.recommendation(for: puzzle) {
                            Text("Related to \(related.game.label)").font(.caption).lineLimit(2)
                            Text(related.themes.map(PuzzleTheme.title).joined(separator: " · ")).font(.caption).foregroundStyle(ChessMeStyle.green)
                        }
                        if let record = model.library.practice.first(where: { $0.findingID == "lichess-puzzle-\(puzzle.id)" }) {
                            Text(record.dueAt <= Date() ? "Ready for a retry" : "Next review \(record.dueAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2).foregroundStyle(ChessMeStyle.muted)
                        }
                    }
                }.foregroundStyle(ChessMeStyle.ink)
            }.accessibilityIdentifier("puzzle.open.\(puzzle.id)")
            Spacer(minLength: 0)
            FavoriteButton(selected: model.isFavorite(puzzle)) { model.toggleFavorite(puzzle) }
        }
    }
}

struct PuzzleLessonView: View {
    let puzzle: TrainingPuzzle
    var body: some View {
        ReviewPracticeView(finding: puzzle.reviewFinding, puzzle: puzzle)
    }
}
