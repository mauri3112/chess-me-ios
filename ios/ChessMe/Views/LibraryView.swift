import SwiftUI
import ChessMeCore

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var savedOnly = false
    private var games: [ChessGame] { savedOnly ? model.favoriteGames : model.windowGames }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                BrandHeader()
                SampleNotice()
                HStack {
                    Text("Games").font(ChessMeStyle.title(32)).foregroundStyle(ChessMeStyle.ink)
                    Spacer()
                    SyncGamesButton(iconOnly: true)
                }
                HStack {
                    if !savedOnly { ReviewPeriodMenu() }
                    Button { savedOnly.toggle() } label: {
                        Label("Saved", systemImage: savedOnly ? "heart.fill" : "heart")
                            .font(.subheadline).padding(.horizontal, 14).frame(minHeight: 44)
                            .foregroundStyle(savedOnly ? .white : ChessMeStyle.ink)
                            .background(savedOnly ? ChessMeStyle.green : ChessMeStyle.ink.opacity(0.05), in: Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("games.saved")
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
                                .background(ChessMeStyle.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(game.playerSide == .white ? game.black : game.white).font(.subheadline.weight(.semibold))
                                Text(game.playedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption).foregroundStyle(ChessMeStyle.muted)
                                if let job = model.library.localAnalysisJobs?.last(where: { $0.gameID == game.id && $0.isPending }) {
                                    Label(job.state == .running ? "Analyzing on device" : (job.nightOnly ? "Queued for tonight" : "Queued on device"), systemImage: job.state == .running ? "cpu" : "clock")
                                        .font(.caption2).foregroundStyle(ChessMeStyle.green)
                                        .symbolEffect(.pulse, isActive: job.state == .running && !reduceMotion)
                                        .accessibilityIdentifier("library.analysis.\(game.id)")
                                }
                                if let analysis = model.library.analyses.first(where: { $0.gameID == game.id }) {
                                    Text("\(analysis.findings.count) key moments · \(analysis.source == "cloud" ? "cloud" : "on device")\(analysis.isComplete ? "" : " · incomplete")")
                                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                                } else { Text("Ready to review").font(.caption).foregroundStyle(ChessMeStyle.muted) }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }.foregroundStyle(ChessMeStyle.ink)
                    }.accessibilityIdentifier("game.open.\(game.id)")
                    Divider()
                }
                ReviewProgressView()
                if let notice = model.notice { Text(notice).font(.caption).foregroundStyle(ChessMeStyle.muted) }
                Button { model.showConnection = true } label: { Label("Manage connection & imports", systemImage: "link") }
                    .font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("games.connection")
                Button { model.showCloudSetup = true } label: { Label("Cloud reviews & queue", systemImage: "cloud") }
                    .font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("cloud.open")
            }.padding(24)
        }.background(ChessMeStyle.paper).toolbar(.hidden, for: .navigationBar)
            .accessibilityIdentifier("games.scroll")
    }
}
