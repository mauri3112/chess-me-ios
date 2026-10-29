import SwiftUI
import ChessMeCore

struct PuzzleTrainingView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var catalog = PuzzleTrainingCatalog()
    @State private var theme = "mate"
    @State private var rating = 1200
    @State private var selection: Collection = .discover
    @State private var choseInitialCollection = false
    @State private var requestTask: Task<Void, Never>?

    private enum Collection: String, CaseIterable {
        case discover = "Discover", related = "Related", saved = "Saved", failed = "Retry"
    }
    private var puzzles: [TrainingPuzzle] {
        switch selection {
        case .discover: return catalog.puzzles
        case .related: return model.recommendedPuzzles
        case .saved: return PuzzleTrainingCatalog.unique(model.favoritePuzzles)
        case .failed:
            let attempted = model.reviewState.runs.compactMap(\.puzzleSnapshot)
            return PuzzleTrainingCatalog.failed(in: model.favoritePuzzles + model.recommendedPuzzles + attempted + catalog.puzzles,
                                                records: model.library.practice, attempts: model.reviewState.attempts)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Puzzle collection", selection: $selection) {
                    ForEach(Collection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                    .accessibilityIdentifier("training.collection")
                if selection == .discover {
                    Text("Choose a motif and practice without importing a game.")
                        .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                    Picker("Motif", selection: $theme) {
                        ForEach(PuzzleTrainingCatalog.themes, id: \.self) { Text(PuzzleTheme.title($0)).tag($0) }
                    }.accessibilityIdentifier("training.motif")
                    Stepper("Target difficulty \(rating)", value: $rating, in: 400...3000, step: 100)
                        .accessibilityIdentifier("training.difficulty")
                    Text("This target selects catalogue puzzles. It is not a measured player rating. Each puzzle shows its Lichess rating.")
                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                    PrimaryButton(title: "Find puzzles", symbol: "magnifyingglass") {
                        requestTask?.cancel()
                        requestTask = Task { await catalog.load(theme: theme, rating: rating) }
                    }.disabled(catalog.isLoading || !model.puzzleService.isConfigured)
                        .accessibilityIdentifier("training.find")
                    if !model.puzzleService.isConfigured {
                        Text("Online puzzle discovery is not configured. Open Saved for offline practice.")
                            .font(.caption).foregroundStyle(ChessMeStyle.muted)
                    }
                    if catalog.isLoading { ProgressView("Finding puzzles…") }
                    if let notice = catalog.notice { Text(notice).font(.caption) }
                    Text(model.isDemo ? "Sample library · online results are Lichess catalogue previews. Use the heart to save a puzzle for offline practice." : "Online Lichess catalogue preview · up to 3 puzzles. Use the heart to save a puzzle for offline practice.")
                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                } else if selection == .related {
                    Text(model.isDemo ? "Sample puzzles related to the demonstration games." : "Puzzles matched to positions in your reviewed games.")
                        .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                    if puzzles.isEmpty { Text("Review a game to find related puzzles, or choose Discover to practise now.").font(.subheadline) }
                } else if selection == .saved {
                    Text("Saved on this device for offline practice.").font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                    if puzzles.isEmpty { Text("Use the heart to keep puzzles here.").font(.subheadline) }
                } else {
                    Text("Puzzles with a recorded failed attempt, including later successes. Attempted puzzles are retained in your practice history.")
                        .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                    if puzzles.isEmpty { Text("No failed puzzles are available in these collections.").font(.subheadline) }
                }
                ForEach(puzzles) { puzzle in
                    PuzzleRow(puzzle: puzzle, isCataloguePreview: selection == .discover)
                    Divider()
                }
                NavigationLink { PuzzlesView() } label: {
                    Label("Related to your games", systemImage: "arrow.triangle.branch")
                }
                Link("Lichess puzzles · CC0", destination: URL(string: "https://database.lichess.org/#puzzles")!)
                    .font(.caption).foregroundStyle(ChessMeStyle.muted)
            }.padding(24)
        }.background(ChessMeStyle.paper)
            .navigationTitle("Puzzle practice")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("training.scroll")
            .onAppear {
                guard !choseInitialCollection else { return }
                choseInitialCollection = true
                if !model.recommendedPuzzles.isEmpty { selection = .related }
            }
            .onChange(of: theme) { _, _ in resetPreview() }
            .onChange(of: rating) { _, _ in resetPreview() }
            .onDisappear { requestTask?.cancel() }
    }

    private func resetPreview() {
        requestTask?.cancel()
        catalog.cancel()
    }
}
