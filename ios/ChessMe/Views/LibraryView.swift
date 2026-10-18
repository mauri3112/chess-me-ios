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
    @State private var schedule: DeviceAnalysisSchedule?
    @ScaledMetric(relativeTo: .subheadline) private var filterHeight: CGFloat = 44
    private var games: [ChessGame] {
        let candidates = savedOnly ? model.favoriteGames : model.windowGames
        let reviews = model.library.analyses + (model.library.analysisHistory ?? []) + (model.library.localAnalysisJobs ?? []).compactMap(\.checkpoint)
        return candidates.filter { speedFilter.includes($0) && reviewedFilter.includes(game: $0, reviews: reviews) }
    }
    @Environment(\.chessReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                BrandHeader(title: "Games", tab: .games)
                SampleNotice()
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
                if games.isEmpty {
                    Text(reviewedFilter != .all || speedFilter != .all ? (savedOnly ? "No saved games match these filters." : "No games match these filters in this period.") : savedOnly ? "Save a game using the heart in its review." : "Your completed games will appear here after import.")
                        .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                    if !savedOnly && reviewedFilter == .all && speedFilter == .all {
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
