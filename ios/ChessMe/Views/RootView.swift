import SwiftUI
import ChessMeCore

// Preserve the existing session identifiers while presenting the new tab order.
enum AppTab: Int { case today = 0, games = 2, practice = 1 }

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @EnvironmentObject private var authentication: LichessAuthentication
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ChessBoardDesign.preferenceKey) private var storedDesign = ChessBoardDesign.classic.rawValue
    @State private var launching = !ProcessInfo.processInfo.arguments.contains("--ui-testing") || ProcessInfo.processInfo.arguments.contains("--test-launch-animation")
    @State private var launchDocked = false

    var body: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack { ReviewView().modifier(LessonDestination(tab: AppTab.today.rawValue)) }
                .tabItem { Label("Today", systemImage: "sun.max") }.tag(AppTab.today.rawValue)
            NavigationStack { LibraryView().modifier(LessonDestination(tab: AppTab.games.rawValue)) }
                .tabItem { Label("Games", systemImage: "books.vertical") }.tag(AppTab.games.rawValue)
            NavigationStack { PracticeView().modifier(LessonDestination(tab: AppTab.practice.rawValue)) }
                .tabItem { Label("Practice", systemImage: "scope") }.tag(AppTab.practice.rawValue)
        }
        .tint(ChessMeStyle.green)
        .disclosureGroupStyle(FullRowDisclosureStyle())
        .toolbarBackground(ChessMeStyle.paper, for: .tabBar)
        .sheet(isPresented: $model.showConnection) { ConnectionView() }
        .sheet(isPresented: $model.showPaywall, onDismiss: { model.applyRequestedProWindow() }) { PaywallView() }
        .sheet(isPresented: $model.showCloudSetup) { CloudSetupView() }
        .onChange(of: subscriptions.isPro) { _, isPro in
            model.cloudAccessVerified = false
            if !isPro { model.selectedWindow = .day }
        }
        .onChange(of: model.isImporting) { _, importing in if !importing { model.applyRequestedProWindow() } }
        .onChange(of: model.isSyncing) { _, syncing in if !syncing { model.applyRequestedProWindow() } }
        .onChange(of: authentication.account) { _, account in
            model.resetCloudAccess()
            if let account { model.adoptPuzzleLevel(from: account) }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.flushNavigationSave() } }
        .overlayPreferenceValue(LogoFramePreference.self) { anchors in
            GeometryReader { geometry in
                if launching, let anchor = anchors[model.selectedTab] {
                    AppLaunchAnimation(target: geometry[anchor], size: geometry.size, docked: launchDocked)
                }
            }.allowsHitTesting(false)
        }
        .environment(\.chessBoardDesign, ChessBoardDesign(rawValue: storedDesign) ?? .classic)
        .environment(\.launchLogoHidden, launching)
        .environment(\.chessReduceMotion, reduceMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion"))
        .task {
            guard launching else { return }
            let quiet = reduceMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion")
            do {
                try await Task.sleep(for: .milliseconds(quiet ? 80 : 1_350))
                withAnimation(quiet ? .easeOut(duration: 0.18) : .smooth(duration: 0.95)) { launchDocked = true }
                try await Task.sleep(for: .milliseconds(quiet ? 200 : 980))
                launching = false
            } catch { launching = false }
        }
        .task(id: "\(model.cloudQueueRefreshID):\(scenePhase == .active)") {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await model.refreshCloudReviews(automatically: true)
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }
}

private struct LessonDestination: ViewModifier {
    let tab: Int
    @EnvironmentObject private var model: AppModel
    func body(content: Content) -> some View {
        content.navigationDestination(isPresented: Binding(get: { model.activeLesson != nil && model.sessionTab == tab }, set: { if !$0 && model.sessionTab == tab { model.endSession() } })) {
            LessonSessionView()
        }
    }
}

struct BrandHeader: View {
    let title: String
    let tab: AppTab
    @State private var settings = false
    @Environment(\.launchLogoHidden) private var hiddenLogo
    var body: some View {
        HStack {
            HStack(spacing: 7) {
                ChessPieceView(piece: Piece(kind: .rook, side: .black))
                    .environment(\.chessBoardDesign, .classic).frame(width: 32, height: 32)
                    .opacity(hiddenLogo ? 0 : 1)
                    .anchorPreference(key: LogoFramePreference.self, value: .bounds) { [tab.rawValue: $0] }
                    .accessibilityIdentifier("app.logo")
                Text(title).font(ChessMeStyle.title(30)).accessibilityIdentifier("app.title")
            }
            Spacer()
            Button { settings = true } label: {
                Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44)
            }.accessibilityLabel("Settings").accessibilityIdentifier("app.settings")
        }
        .foregroundStyle(ChessMeStyle.ink)
        .sheet(isPresented: $settings) { SettingsView() }
    }
}

struct SampleNotice: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if model.isDemo {
            HStack {
                Label("Sample games", systemImage: "eye").accessibilityIdentifier("demo.label")
                Spacer()
                Button("Exit sample") { model.exitDemo() }.disabled(model.isBusy)
            }.font(.caption).foregroundStyle(ChessMeStyle.muted)
        }
    }
}

struct ReviewProgressView: View {
    var showsBulkReviewAction = true
    var showsGameQueue = false
    var showsCoverage = true
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsGameQueue && !model.queuedAnalysisGames.isEmpty {
                TodayAnalysisQueueView(games: model.queuedAnalysisGames)
            }
            if model.isImporting || model.isSyncing || (model.isAnalyzing && !showsGameQueue) {
                HStack {
                    Text(model.progressMessage.isEmpty ? "Updating your games…" : model.progressMessage).font(.caption)
                    Spacer()
                    if model.isAnalyzing {
                        Button("Pause") { model.pauseAnalysis() }.font(.caption.weight(.semibold)).accessibilityIdentifier("review.pause")
                    }
                }
                if model.isAnalyzing { ProgressView(value: model.progress).tint(ChessMeStyle.green) }
                else { ProgressView() }
            } else if showsBulkReviewAction && !model.isAnalyzing && model.pendingGames > 0 && (!showsGameQueue || model.queuedAnalysisGames.isEmpty) {
                Button("Review \(model.pendingGames) remaining games") { model.analyzePending() }
                    .font(.subheadline.weight(.semibold)).accessibilityIdentifier("review.resume")
            }
            if let message = model.syncMessage {
                Text(message).font(.caption).foregroundStyle(ChessMeStyle.green).accessibilityIdentifier("review.syncStatus")
            }
            if showsCoverage, let coverage = model.library.coverageNote { Text(coverage).font(.caption).foregroundStyle(ChessMeStyle.muted) }
        }
    }
}

private struct TodayAnalysisQueueView: View {
    let games: [ChessGame]
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Analysis queue").font(.subheadline.weight(.semibold))
                Spacer()
                if model.isAnalyzing {
                    Button("Pause") { model.pauseAnalysis() }
                        .font(.caption.weight(.semibold)).accessibilityIdentifier("review.pause")
                }
            }
            ForEach(Array(games.prefix(3))) { game in queueRow(game) }
            if games.count > 3 {
                DisclosureGroup("\(games.count - 3) more queued games") {
                    VStack(spacing: 14) {
                        ForEach(Array(games.dropFirst(3))) { game in queueRow(game) }
                    }.padding(.top, 10)
                }.font(.subheadline).accessibilityIdentifier("today.analysisMore")
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("today.analysisQueue")
    }
    private func queueRow(_ game: ChessGame) -> some View {
        NavigationLink { GameDetailView(game: game) } label: {
            HStack(spacing: 12) {
                GameAnalysisIndicator(game: game)
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.reviewLabel).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(status(for: game)).font(.caption).foregroundStyle(ChessMeStyle.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(ChessMeStyle.muted)
            }.foregroundStyle(ChessMeStyle.ink).padding(.vertical, 3)
        }.accessibilityIdentifier("today.analysis.open.\(game.id)")
    }
    private func status(for game: ChessGame) -> String {
        if let job = model.localAnalysisJob(for: game.id, includingOrdinary: true), job.isPending,
           model.completeDeviceReview(for: game.id, covering: job.configuration) == nil {
            if job.state == .running { return "Analyzing on this device" }
            return job.nightOnly ? "Tonight on this device" : "Queued on this device"
        }
        return model.cloudReview(for: game.id)?.state == "running" ? "Analyzing in the cloud" : "Queued in the cloud"
    }
}

struct ReviewView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var authentication: LichessAuthentication
    @State private var readyGame: ChessGame?
    private var next: MoveFinding? { model.nextLesson() ?? model.allDuePuzzles.first ?? model.allPuzzles.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BrandHeader(title: "Today", tab: .today)
                SampleNotice()
                if model.library.games.isEmpty { welcome }
                else {
                    nextAction
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(model.library.games.count) games imported").font(.subheadline.weight(.medium))
                            Text("\(model.completedGames) reviewed · \(model.readyReviewTargets.count) lessons ready")
                                .font(.caption).foregroundStyle(ChessMeStyle.muted)
                        }
                        Spacer()
                        Button("View games") { model.selectedTab = AppTab.games.rawValue }.font(.subheadline.weight(.medium))
                    }.accessibilityIdentifier("home.summary")
                    ReviewProgressView(showsGameQueue: true, showsCoverage: false)
                    if model.currentCloudReviews.contains(where: \.isPending) {
                        Button { model.showCloudSetup = true } label: { Label("Cloud reviews in progress", systemImage: "cloud") }
                            .accessibilityIdentifier("cloud.open")
                    }
                }
                if !model.suggestedReviewTargets.isEmpty || model.hasResumableReview {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Back to practice").font(ChessMeStyle.title(22))
                            Button(model.hasResumableReview ? "Resume practice" : "Start short practice") {
                                if model.hasResumableReview { model.resumeReviewSession() }
                                else { model.startSession() }
                            }.frame(minHeight: 44).accessibilityIdentifier("today.followUp")
                            Button("Your lessons") { model.selectedTab = AppTab.practice.rawValue }
                        }
                    }
                }
                quickPractice
                if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(ChessMeStyle.muted) }
            }.padding(24)
        }
        .accessibilityIdentifier("main.scroll").background(ChessMeStyle.paper)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: Binding(get: { readyGame != nil }, set: { if !$0 { readyGame = nil } })) {
            if let readyGame { GameDetailView(game: readyGame) }
        }
    }

    private var quickPractice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Play and practise").font(ChessMeStyle.title(22))
            NavigationLink { PuzzlesView() } label: {
                Label("Play puzzles", systemImage: "puzzlepiece.extension").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.accessibilityIdentifier("today.puzzles")
            NavigationLink { OpeningCoachView() } label: {
                Label("Opening practice", systemImage: "flag.checkered").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.accessibilityIdentifier("today.openings")
        }.font(.subheadline.weight(.semibold)).foregroundStyle(ChessMeStyle.green)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Learn from your games").font(ChessMeStyle.title(28))
            Text("Review your finished games and practise the moves you missed.").font(.subheadline).foregroundStyle(ChessMeStyle.muted)
            PrimaryButton(title: authentication.account == nil ? "Connect Lichess" : "Import my games", symbol: "link") { model.showConnection = true }
                .accessibilityIdentifier("connect.start")
            Button("Try a sample review") { model.loadDemo() }.disabled(model.isBusy)
                .font(.subheadline.weight(.medium)).frame(minHeight: 44).accessibilityIdentifier("demo.start")
            ChessBoardView(position: (try? ChessPosition(fen: "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 4 4")) ?? .initial)
                .frame(maxWidth: 210).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var nextAction: some View {
        if model.activeLesson != nil {
            PrimaryButton(title: "Continue practice", symbol: "play.fill") { model.selectedTab = model.sessionTab ?? AppTab.practice.rawValue }
                .accessibilityIdentifier("lesson.continue")
        } else if let game = model.nextReadyReview {
            PaperCard {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Review ready", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold))
                        .foregroundStyle(ChessMeStyle.green)
                    GamePlayerNames(game: game, outcome: model.outcome(for: game), prominent: true)
                    if let review = model.gameAnalysis(for: game.id) {
                        Text(review.source == "cloud" ? "Cloud review" : "Device review")
                            .font(.caption).foregroundStyle(ChessMeStyle.muted)
                    }
                    Button { readyGame = game } label: {
                        HStack {
                            Text("See game summary").fontWeight(.semibold)
                            Spacer(); Image(systemName: "arrow.right")
                        }.padding(18).foregroundStyle(.white)
                            .background(ChessMeStyle.green, in: RoundedRectangle(cornerRadius: 16))
                    }.accessibilityIdentifier("today.reviewReady")
                }
            }
        } else if let next {
            PaperCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Your next lesson").font(ChessMeStyle.title(24))
                        Spacer()
                        if next.source == "cloud" { Text("Cloud").font(.caption).foregroundStyle(ChessMeStyle.muted) }
                    }
                    HStack(spacing: 16) {
                        ChessBoardView(position: (try? ChessPosition(fen: next.positionFEN)) ?? .initial)
                            .frame(width: 110, height: 110).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(next.theme).font(.subheadline.weight(.medium))
                            Text(next.gameLabel).font(.caption).foregroundStyle(ChessMeStyle.muted)
                        }
                    }
                    PrimaryButton(title: "Practice this position", symbol: "play.fill") { model.openLesson(next) }
                        .accessibilityIdentifier("lesson.start")
                }
            }
        } else if model.pendingGames > 0 {
            PaperCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.isAnalyzing ? "Finding your next lesson" : "Learn from your latest game").font(ChessMeStyle.title(24))
                    Text(model.isAnalyzing ? "You can browse your games while reviews finish." : "Open a game to review its key moments.")
                        .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                    PrimaryButton(title: "View games", symbol: "books.vertical") { model.selectedTab = AppTab.games.rawValue }
                }
            }
        } else {
            PaperCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ready for more practice?").font(ChessMeStyle.title(24))
                    PrimaryButton(title: "Browse practice", symbol: "scope") { model.selectedTab = AppTab.practice.rawValue }
                }
            }
        }
    }
}

struct SyncGamesButton: View {
    @EnvironmentObject private var model: AppModel
    var iconOnly = false
    private var updating: Bool { model.isSyncing || model.isImporting || model.isAnalyzing }
    var body: some View {
        Button { Task { await model.syncCompletedGames() } } label: {
            HStack(spacing: 10) {
                if !iconOnly { Text(updating ? "Updating your games…" : "Sync completed games").font(.subheadline.weight(.semibold)); Spacer() }
                if updating { ProgressView().tint(ChessMeStyle.green) }
                else { Image(systemName: "arrow.clockwise").font(iconOnly ? .title2 : .subheadline) }
            }.frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain).foregroundStyle(ChessMeStyle.green)
        .disabled(model.isBusy || model.isSyncing)
        .accessibilityLabel(updating ? "Updating your games" : "Sync completed games")
        .accessibilityValue(updating ? "In progress" : "Ready")
        .accessibilityIdentifier(iconOnly ? "practice.sync" : "review.sync")
    }
}

struct ReviewPeriodMenu: View {
    var compact = false
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @State private var showPlans = false
    var body: some View {
        Menu {
            ForEach(ReviewWindow.allCases, id: \.self) { window in
                Button {
                    if !window.isFree && !subscriptions.isPro {
                        model.select(window, presentPaywall: false)
                        showPlans = true
                    } else { model.select(window) }
                } label: {
                    Label(window.shortLabel, systemImage: !window.isFree && !subscriptions.isPro ? "lock" : model.selectedWindow == window ? "checkmark" : "calendar")
                }.disabled((model.isImporting || model.isSyncing) && (window.isFree || subscriptions.isPro))
                    .accessibilityIdentifier("window.\(window.accessibilityKey)")
            }
        } label: {
            Group {
                if compact {
                    HStack(spacing: 6) {
                        Text(model.selectedWindow.shortTitle).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        Image(systemName: "chevron.down").font(.caption2)
                    }.padding(.horizontal, 10)
                } else {
                    Label(model.selectedWindow.title, systemImage: "calendar").padding(.horizontal, 14)
                }
            }.font(.subheadline).frame(minHeight: 44)
                .background(ChessMeStyle.ink.opacity(0.05), in: Capsule())
        }.accessibilityIdentifier("games.period")
            .accessibilityLabel(model.selectedWindow.title)
            .sheet(isPresented: $showPlans, onDismiss: { model.applyRequestedProWindow() }) { PaywallView() }
    }
}
