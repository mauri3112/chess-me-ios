import SwiftUI
import ChessMeCore

enum ReviewedGameFilter: String, CaseIterable {
    case all = "All", reviewed = "Reviewed", local = "Local reviewed", cloud = "Cloud reviewed"
    var key: String { switch self { case .all: "all"; case .reviewed: "reviewed"; case .local: "local"; case .cloud: "cloud" } }
    var source: String? { switch self { case .local: "device"; case .cloud: "cloud"; default: nil } }
    var symbol: String { switch self { case .all: "books.vertical"; case .reviewed: "checkmark.circle"; case .cloud: "cloud"; case .local: "iphone" } }
    func includes(game: ChessGame, reviews: [GameAnalysis]) -> Bool {
        self == .all || reviews.contains { $0.gameID == game.id && $0.isComplete && (source == nil || $0.source == source) }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var savedOnly = false
    @State private var reviewedFilter: ReviewedGameFilter = .all
    @State private var speedFilter: GameSpeedFilter = .all
    @State private var search = ""
    @State private var side: Side?
    @State private var result: PlayerGameOutcome?
    @State private var archiveEntries: [String: GameArchiveEntry] = [:]
    @State private var indexing = false
    @FocusState private var searchFocused: Bool
    @State private var schedule: DeviceAnalysisSchedule?
    @ScaledMetric(relativeTo: .subheadline) private var filterHeight: CGFloat = 44
    private var games: [ChessGame] {
        let candidates = savedOnly ? model.favoriteGames : model.windowGames
        let reviews = model.library.analyses + (model.library.analysisHistory ?? []) + (model.library.localAnalysisJobs ?? []).compactMap(\.checkpoint)
        return candidates.filter {
            guard speedFilter.includes($0), reviewedFilter.includes(game: $0, reviews: reviews) else { return false }
            guard !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || side != nil || result != nil else { return true }
            return archiveEntries[$0.id]?.matches(search, side: side, result: result) == true
        }
    }
    @Environment(\.chessReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                BrandHeader(title: "Games", tab: .games)
                SampleNotice()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { studyLinks }
                    VStack(alignment: .leading, spacing: 4) { studyLinks }
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(ChessMeStyle.muted)
                    TextField("Opponent, opening, or ECO", text: $search)
                        .autocorrectionDisabled().submitLabel(.search).focused($searchFocused)
                        .onSubmit { searchFocused = false }.accessibilityIdentifier("games.search")
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Clear search").frame(width: 44, height: 44)
                    }
                }.padding(.leading, 12).frame(minHeight: 44).background(.white, in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Menu {
                        Button("Queue for night analysis", systemImage: "moon.fill") { schedule = .night }
                            .accessibilityIdentifier("games.queueNight")
                        Button("Queue to analyze now", systemImage: "play.fill") { schedule = .now }
                            .accessibilityIdentifier("games.queueNow")
                    } label: { Label("Add for analysis", systemImage: "plus.circle.fill") }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        .disabled(model.isImporting || model.cloudIsRunning || games.isEmpty)
                        .accessibilityIdentifier("games.addAnalysis")
                    Spacer()
                    SyncGamesButton(iconOnly: true)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ReviewPeriodMenu(compact: true)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(width: savedOnly ? 0 : nil, height: filterHeight, alignment: .leading)
                            .clipped().opacity(savedOnly ? 0 : 1).disabled(savedOnly).accessibilityHidden(savedOnly)
                        reviewedMenu.padding(.leading, savedOnly ? 0 : 8)
                        Button { withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.08)) { savedOnly.toggle() } } label: {
                            Label("Saved", systemImage: "heart.fill")
                                .font(.subheadline).fixedSize().padding(.horizontal, 10).frame(height: filterHeight)
                                .foregroundStyle(savedOnly ? .white : ChessMeStyle.ink)
                                .background(savedOnly ? ChessMeStyle.green : ChessMeStyle.ink.opacity(0.05), in: Capsule())
                        }.buttonStyle(.plain).padding(.leading, 8).transition(.identity)
                            .accessibilityIdentifier("games.saved")
                            .accessibilityValue(savedOnly ? "Selected" : "Not selected")
                    }
                }.frame(height: filterHeight)
                GameSpeedMenu(selection: $speedFilter)
                HStack(spacing: 16) {
                    Menu {
                        Button("Both colors") { side = nil }
                        Button("White") { side = .white }
                        Button("Black") { side = .black }
                    } label: {
                        Label(side?.title ?? "Both colors", systemImage: "circle.lefthalf.filled")
                    }.accessibilityIdentifier("games.color")
                    Menu {
                        Button("All results") { result = nil }
                        Button("Won") { result = .won }
                        Button("Drawn") { result = .draw }
                        Button("Lost") { result = .lost }
                    } label: {
                        Label(result == .won ? "Won" : result == .draw ? "Drawn" : result == .lost ? "Lost" : "All results", systemImage: "flag")
                    }.accessibilityIdentifier("games.resultFilter")
                }.font(.subheadline).frame(minHeight: 44)
                if indexing && (!search.isEmpty || result != nil || side != nil) {
                    ProgressView("Reading saved game details…").font(.caption)
                }
                if games.isEmpty {
                    Text(hasFilters ? (savedOnly ? "No saved games match these filters." : "No games match these filters in this period.") : savedOnly ? "Save a game using the heart in its review." : "Your completed games will appear here after import.")
                        .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                    if hasFilters {
                        Button("Clear filters") { search = ""; result = nil; side = nil; reviewedFilter = .all; speedFilter = .all }
                            .frame(minHeight: 44).accessibilityIdentifier("games.clearFilters")
                    } else if !savedOnly {
                        PrimaryButton(title: "Import games", symbol: "arrow.down") { model.showConnection = true }
                    }
                }
                ForEach(games) { game in
                    NavigationLink { GameDetailView(game: game) } label: {
                        HStack(spacing: 15) {
                            ChessPieceView(piece: Piece(kind: .king, side: game.playerSide))
                                .frame(width: 38, height: 38).frame(width: 48, height: 56)
                                .background(model.outcome(for: game).map { $0.color.opacity(0.82) } ?? ChessMeStyle.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 6) {
                                GamePlayerNames(game: game, outcome: model.outcome(for: game))
                                    .accessibilityIdentifier("game.result.\(game.id)")
                                HStack(spacing: 6) {
                                    GameSpeedIcon(speed: game.timeControl)
                                        .accessibilityIdentifier("game.speed.\(game.id)")
                                    Text(game.playedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                }.font(.caption).foregroundStyle(ChessMeStyle.muted)
                                if let analysis = model.gameAnalysis(for: game.id) {
                                    Text("\(analysis.findings.count) key moments")
                                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                                }
                                if let opening = archiveEntries[game.id]?.opening {
                                    Text(opening).font(.caption).foregroundStyle(ChessMeStyle.muted).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            GameAnalysisIndicator(game: game)
                            Image(systemName: "chevron.right").font(.caption)
                        }.foregroundStyle(ChessMeStyle.ink)
                    }.accessibilityIdentifier("game.open.\(game.id)")
                    Divider()
                }
                ReviewProgressView(showsBulkReviewAction: false)
                if let notice = model.notice { Text(notice).font(.caption).foregroundStyle(ChessMeStyle.muted) }
                Button { model.showConnection = true } label: { Label("Manage connection & imports", systemImage: "link") }
                    .font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("games.connection")
                Button { model.showCloudSetup = true } label: { Label("Cloud reviews & queue", systemImage: "cloud") }
                    .font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("cloud.open")
            }.padding(24)
        }.background(ChessMeStyle.paper).toolbar(.hidden, for: .navigationBar)
            .accessibilityIdentifier("games.scroll")
            .sheet(item: $schedule) { mode in GameAnalysisSelectionView(schedule: mode, games: games) }
            .task(id: model.library.games) {
                indexing = true
                let savedGames = model.library.games
                let work = Task.detached(priority: .utility) { () -> [String: GameArchiveEntry] in
                    var entries: [String: GameArchiveEntry] = [:]
                    for game in savedGames {
                        if Task.isCancelled { break }
                        let opening = (try? GameReplay(game: game)).flatMap { OpeningBook.shared.line(in: $0).opening }
                        entries[game.id] = GameArchiveEntry(game: game, opening: opening)
                    }
                    return entries
                }
                let entries = await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
                guard !Task.isCancelled else { return }
                archiveEntries = entries; indexing = false
            }
    }

    private var hasFilters: Bool { reviewedFilter != .all || speedFilter != .all || !search.isEmpty || side != nil || result != nil }

    @ViewBuilder private var studyLinks: some View {
        NavigationLink { SavedReviewLinesView() } label: {
            Label("Saved lines", systemImage: "arrow.triangle.branch")
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        }.accessibilityIdentifier("games.savedLines")
        NavigationLink { InsightsView() } label: {
            Label("Insights", systemImage: "chart.bar")
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        }.accessibilityIdentifier("games.insights")
    }

    private var reviewedMenu: some View {
        Menu {
            ForEach(ReviewedGameFilter.allCases, id: \.self) { filter in
                Button { reviewedFilter = filter } label: {
                    Label(filter.rawValue, systemImage: reviewedFilter == filter ? "checkmark" : filter.symbol)
                }.accessibilityIdentifier("games.reviewed.\(filter.key)")
            }
            Divider()
            Button("Show all games", systemImage: "xmark.circle") { reviewedFilter = .all }
                .accessibilityIdentifier("games.reviewed.clear")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: reviewedFilter.symbol)
                Text(reviewedFilter.rawValue)
                Image(systemName: "chevron.down").font(.caption2)
            }.font(.subheadline).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10).frame(height: filterHeight)
                .foregroundStyle(reviewedFilter == .all ? ChessMeStyle.ink : .white)
                .background(reviewedFilter == .all ? ChessMeStyle.ink.opacity(0.05) : ChessMeStyle.green, in: Capsule())
        }.accessibilityIdentifier("games.reviewed")
            .accessibilityLabel("Review filter").accessibilityValue(reviewedFilter.rawValue)
    }
}
