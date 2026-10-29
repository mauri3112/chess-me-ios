import SwiftUI
import ChessMeCore

struct SavedReviewLinesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var side: Side?
    @State private var renaming: SavedReviewLine?
    @State private var newTitle = ""
    private var lines: [SavedReviewLine] {
        model.reviewState.savedLines.filter { $0.matches(search: search, side: side) }
            .sorted { $0.savedAt > $1.savedAt }
    }
    private var groups: [String] { Set(lines.map(\.openingFamily)).sorted { $0.localizedCompare($1) == .orderedAscending } }
    var body: some View {
        List {
            Section {
                if model.isDemo { Text("Sample collection · cleared when you leave sample games").font(.caption) }
                Picker("Source player side", selection: $side) {
                    Text("White and Black").tag(Side?.none)
                    Text("White").tag(Side?.some(.white))
                    Text("Black").tag(Side?.some(.black))
                }.accessibilityIdentifier("lines.side")
                Text("White and Black refer to your side in the source game.").font(.caption)
                ReviewSaveNotice()
            }
            if lines.isEmpty {
                ContentUnavailableView(model.reviewState.savedLines.isEmpty ? "No saved lines yet" : "No matching lines",
                                       systemImage: "arrow.triangle.branch",
                                       description: Text(model.reviewState.savedLines.isEmpty ?
                                                         "In Explore, play a variation and choose Save line." :
                                                         "Clear the search or side filter to see more lines."))
                if !model.reviewState.savedLines.isEmpty { Button("Clear filters") { search = ""; side = nil } }
            }
            ForEach(groups, id: \.self) { group in
                Section(group) {
                    ForEach(lines.filter { $0.openingFamily == group }) { line in
                        NavigationLink {
                            SavedReviewLineView(lineID: line.id)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                if let position = try? ChessPosition(fen: line.positionFEN) {
                                    ChessBoardView(position: position, perspective: line.playerSide)
                                        .frame(width: 66, height: 66).accessibilityHidden(true)
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(line.title).font(.subheadline.weight(.semibold))
                                    if let opening = line.opening { Text(opening).font(.caption) }
                                    Text("\(line.playerSide.title) · \(line.gameLabel)").font(.caption).foregroundStyle(.secondary)
                                    Text(line.savedAt, style: .date).font(.caption2)
                                }
                            }
                        }.accessibilityIdentifier("lines.open.\(line.id)")
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    model.changeReview { $0.savedLines.removeAll { $0.id == line.id } }
                                }
                                Button("Rename") { renaming = line; newTitle = line.title }.tint(ChessMeStyle.green)
                            }
                            .contextMenu {
                                Button("Rename") { renaming = line; newTitle = line.title }
                                Button("Delete line", role: .destructive) {
                                    model.changeReview { $0.savedLines.removeAll { $0.id == line.id } }
                                }
                            }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Opening, variation, or title").accessibilityIdentifier("lines.collection")
        .navigationTitle("Saved lines").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .alert("Rename line", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Save") {
                guard let id = renaming?.id, !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                model.changeReview { state in
                    if let index = state.savedLines.firstIndex(where: { $0.id == id }) { state.savedLines[index].title = newTitle }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }
}

struct SavedReviewLineView: View {
    let lineID: String
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if let line = model.reviewState.savedLines.first(where: { $0.id == lineID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(line.title).font(ChessMeStyle.title(26))
                    Text("Your saved variation · \(line.savedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                    NavigationLink {
                        SavedLineRehearsalView(lineID: line.id)
                    } label: { Label("Rehearse this saved line", systemImage: "brain.head.profile") }
                    .accessibilityIdentifier("lines.rehearse")
                    NavigationLink { NotationExportView(game: line.replayGame(), savedLine: line) } label: {
                        Label("Export saved line PGN", systemImage: "square.and.arrow.up")
                    }.accessibilityIdentifier("lines.export")
                    ReviewLineView(fen: line.positionFEN, moves: line.moves, perspective: line.playerSide,
                                   label: "Saved moves · not automatically a verified recommendation")
                    NavigationLink {
                        GameReplayExplorer(game: line.replayGame(), initialPly: line.prefix.count, useStoredSnapshot: true, snapshotID: line.id)
                    } label: { Label("Explore this saved position", systemImage: "arrow.triangle.branch") }
                    .accessibilityIdentifier("lines.explore")
                    if let game = model.library.games.first(where: { $0.id == line.gameID }) {
                        NavigationLink("Open source game") { GameDetailView(game: game) }
                    } else { Text("The source game is unavailable. The stored position and line remain usable.").font(.caption) }
                    ReviewSaveNotice()
                }.padding(22)
            }.background(ChessMeStyle.paper).navigationTitle("Saved line").navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Line unavailable", systemImage: "arrow.triangle.branch",
                                   description: Text("This saved line may have been removed."))
        }
    }
}
