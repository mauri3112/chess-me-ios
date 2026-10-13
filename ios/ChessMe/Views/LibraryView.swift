import SwiftUI
import ChessMeCore

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var savedOnly = false
    @State private var showAnalysisChoices = false
    @State private var schedule: DeviceAnalysisSchedule?
    @ScaledMetric(relativeTo: .subheadline) private var periodWidth: CGFloat = 148
    private var games: [ChessGame] { savedOnly ? model.favoriteGames : model.windowGames }
    @Environment(\.chessReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                BrandHeader(title: "Games", tab: .games)
                SampleNotice()
                HStack {
                    Button { showAnalysisChoices = true } label: { Label("Add for analysis", systemImage: "plus.circle.fill") }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        .disabled(model.isImporting || model.cloudIsRunning || games.isEmpty)
                        .accessibilityIdentifier("games.addAnalysis")
                    Spacer()
                    SyncGamesButton(iconOnly: true)
                }
                HStack(spacing: 0) {
                    ReviewPeriodMenu().frame(width: savedOnly ? 0 : periodWidth, alignment: .leading)
                        .clipped().opacity(savedOnly ? 0 : 1).disabled(savedOnly).accessibilityHidden(savedOnly)
                    Button { withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.08)) { savedOnly.toggle() } } label: {
                        Label("Saved", systemImage: "heart.fill")
                            .font(.subheadline).padding(.horizontal, 14).frame(minHeight: 44)
                            .foregroundStyle(savedOnly ? .white : ChessMeStyle.ink)
                            .background(savedOnly ? ChessMeStyle.green : ChessMeStyle.ink.opacity(0.05), in: Capsule())
                    }.buttonStyle(.plain).padding(.leading, savedOnly ? 0 : 12).transition(.identity)
                        .accessibilityIdentifier("games.saved")
                        .accessibilityValue(savedOnly ? "Selected" : "Not selected")
                    Spacer()
                }
                if games.isEmpty {
                    Text(savedOnly ? "Save a game using the heart in its review." : "Your completed games will appear here after import.")
                        .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                    if !savedOnly {
                        PrimaryButton(title: "Import games", symbol: "arrow.down") { model.showConnection = true }
                    }
                }
                ForEach(games) { game in
                    NavigationLink { GameDetailView(game: game) } label: {
                        HStack(spacing: 15) {
                            ChessPieceView(piece: Piece(kind: .king, side: game.playerSide))
                                .frame(width: 38, height: 38).frame(width: 48, height: 56)
                                .background((model.outcome(for: game)?.color ?? ChessMeStyle.green).opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(game.opponent).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    if let outcome = model.outcome(for: game) { GameOutcomeBadge(outcome: outcome).accessibilityIdentifier("game.result.\(game.id)") }
                                }
                                Text(game.playedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption).foregroundStyle(ChessMeStyle.muted)
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
            .confirmationDialog("Add for analysis", isPresented: $showAnalysisChoices, titleVisibility: .visible) {
                Button("Queue for night analysis") { schedule = .night }.accessibilityIdentifier("games.queueNight")
                Button("Queue to analyze now") { schedule = .now }.accessibilityIdentifier("games.queueNow")
            }
            .sheet(item: $schedule) { mode in GameAnalysisSelectionView(schedule: mode, games: games) }
    }
}
