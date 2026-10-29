import SwiftUI
import ChessMeCore

struct PersonalOpeningExplorerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var explorer: PersonalOpeningExplorer?
    @State private var account = ""
    @State private var color = "all"
    @State private var speed: GameSpeedFilter = .all
    @State private var flipped = false
    @State private var loading = false
    @State private var archiveRevision = UUID()
    @State private var error: String?
    private var accounts: [String] { PersonalOpeningExplorer.accounts(in: model.windowGames) }
    private var request: String { "\(account)|\(color)|\(speed.rawValue)|\(model.selectedWindow.rawValue)|\(archiveRevision)" }
    private var controlLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Your opening explorer").font(ChessMeStyle.title(28))
                Text("Saved games in \(model.selectedWindow.title.lowercased()). Counts describe these games, not master play or recommended moves.")
                    .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                if let note = model.library.coverageNote { Text(note).font(.caption).foregroundStyle(ChessMeStyle.muted) }
                Picker("Source account", selection: $account) {
                    Text("Choose account").tag("")
                    ForEach(accounts, id: \.self) { Text($0).tag($0) }
                }.accessibilityIdentifier("openingExplorer.account")
                Picker("Your color", selection: $color) {
                    Text("Both colors").tag("all")
                    Text("White").tag("white")
                    Text("Black").tag("black")
                }.pickerStyle(.segmented).accessibilityIdentifier("openingExplorer.color")
                GameSpeedMenu(selection: $speed, allowsMultilineLabel: true)
                if loading { ProgressView("Indexing saved openings…") }
                if let error { Text(error).font(.caption) }
                if let explorer, !loading {
                    if let opening = explorer.opening { Text("\(opening.eco) · \(opening.name)").font(.headline) }
                    ChessBoardView(position: explorer.position, perspective: flipped ? .black : .white)
                        .accessibilityIdentifier("openingExplorer.board")
                    controlLayout {
                        Button("Back", systemImage: "chevron.left") { self.explorer?.back() }.disabled(explorer.path.isEmpty)
                            .accessibilityIdentifier("openingExplorer.back")
                        if !typeSize.isAccessibilitySize { Spacer() }
                        Button("Reset", systemImage: "arrow.counterclockwise") { self.explorer?.reset() }.disabled(explorer.path.isEmpty)
                            .accessibilityIdentifier("openingExplorer.reset")
                        if !typeSize.isAccessibilitySize { Spacer() }
                        Button("Flip", systemImage: "arrow.up.arrow.down") { flipped.toggle() }
                            .accessibilityIdentifier("openingExplorer.flip")
                    }.buttonStyle(.bordered)
                    Text(summary(explorer.results)).font(.subheadline).accessibilityIdentifier("openingExplorer.results")
                    Text("Results are from the selected account's perspective. Known results: \(explorer.results.known) of \(explorer.results.count). Unknown outcomes are not draws.")
                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                    ForEach(explorer.branches) { branch in
                        Button { try? self.explorer?.advance(branch.move) } label: {
                            HStack {
                                Text(branch.san).font(.headline)
                                Spacer()
                                Text(summary(branch.results)).font(.caption)
                                Image(systemName: "chevron.right")
                            }.padding(.vertical, 8)
                        }.accessibilityLabel("\(branch.san), \(summary(branch.results))")
                            .accessibilityIdentifier("openingExplorer.move.\(branch.move.uci)")
                    }
                    if explorer.branches.isEmpty {
                        Text(explorer.path.count >= explorer.maximumPly ? "Opening browsing stops after \(explorer.maximumPly) plies. Open a matching game to continue." : "No saved continuation at this move order.")
                            .font(.caption).foregroundStyle(ChessMeStyle.muted)
                    }
                    Text("\(explorer.excludedSetup) setup-position games excluded · \(explorer.excludedInvalid) unfinished or unreadable · \(explorer.excludedDemo) demonstrations excluded · \(explorer.duplicateCount) duplicates · \(explorer.deferred) beyond index limit")
                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                    Text("Matching games").font(.headline)
                    ForEach(matchingGames(explorer)) { game in
                        NavigationLink { GameDetailView(game: game) } label: {
                            VStack(alignment: .leading) {
                                Text(game.label)
                                Text(game.playedAt, style: .date).font(.caption)
                            }.padding(.vertical, 6)
                        }
                    }
                    if explorer.gameIDs.count > 30 { Text("Showing the first 30 matching games.").font(.caption) }
                }
                if accounts.isEmpty { Text("Import completed games to explore your opening moves. Demonstration games do not count toward your personal results.") }
            }.padding(24)
        }.background(ChessMeStyle.paper)
            .navigationTitle("Opening explorer").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).accessibilityIdentifier("openingExplorer.scroll")
            .task(id: request) { await rebuild() }
            .onChange(of: model.library.games) { _, _ in archiveRevision = UUID() }
    }
    private func summary(_ value: PersonalOpeningExplorer.Results) -> String {
        "\(value.count) games · \(value.wins) W / \(value.draws) D / \(value.losses) L / \(value.unknown) ?"
    }
    private func matchingGames(_ index: PersonalOpeningExplorer) -> [ChessGame] {
        var games: [String: ChessGame] = [:]
        for game in model.windowGames where games[game.id] == nil { games[game.id] = game }
        return index.gameIDs.prefix(30).compactMap { games[$0] }
    }
    @MainActor private func rebuild() async {
        if account.isEmpty, let first = accounts.first { account = first; return }
        guard !account.isEmpty else { explorer = nil; return }
        loading = true; error = nil
        let games = model.windowGames, selected = account, side = Side(rawValue: color), speed = speed
        let worker = Task.detached(priority: .utility) {
            try PersonalOpeningExplorer(games: games, account: selected, side: side, speed: speed)
        }
        do {
            let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            explorer = result; loading = false
            flipped = side == .black
        } catch is CancellationError { }
        catch { self.error = "Could not index these saved games."; loading = false }
    }
}
