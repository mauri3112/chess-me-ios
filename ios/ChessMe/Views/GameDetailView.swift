import SwiftUI
import ChessMeCore

struct GameDetailView: View {
    let game: ChessGame
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var analyzer = PositionAnalysisController()
    @State private var replay: GameReplay?
    @State private var clockTimeline: GameClockTimeline?
    @State private var clocksLoading = false
    @State private var clockError: String?
    @State private var selected: Int?
    @State private var replayError: String?
    @State private var showCloudSetup = false
    @State private var confirmCloud = false
    @State private var card: MoveFinding?
    @State private var promotionMoves: [ChessMove] = []
    @State private var variationAssessment: MoveAssessment?
    @State private var showEngineSettings = false
    @State private var exploring = false
    @State private var momentIndex = 0
    private var moments: [MoveFinding] {
        (analysis?.findings ?? []).sorted { $0.moveNumber < $1.moveNumber }
    }
    private var moment: MoveFinding? { moments.indices.contains(momentIndex) ? moments[momentIndex] : nil }
    private var analysis: GameAnalysis? { model.library.analyses.first { $0.gameID == game.id } }
    private var savedGame: ChessGame { model.library.games.first { $0.id == game.id } ?? game }
    @State private var showLocalSettings = false
    private var deviceReviewAlreadyActive: Bool {
        guard let job = model.localAnalysisJob(for: game.id) else { return false }
        return job.state == .running || (job.state == .queued && !job.nightOnly && model.isAnalyzing)
    }
    private var reviewOrigin: String {
        let origin = analysis?.source == "cloud" ? "Cloud" : "Device"
        return model.localAnalysisJob(for: game.id)?.isPending == true && analysis?.isComplete == true
            ? "Previous " + origin.lowercased() : origin
    }
    private var assessment: MoveAssessment? {
        guard let replay else { return nil }
        return replay.isVariation ? variationAssessment : analysis?.moveAssessments?.first { $0.ply == replay.index - 1 }
    }
    private var targets: Set<Int> {
        guard let selected, let replay else { return [] }
        return Set(replay.position.legalMoves().filter { $0.from == selected }.map(\.to))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Eyebrow(text: model.isDemo ? "Sample game" : "Completed game")
                    Spacer()
                    FavoriteButton(selected: model.isFavorite(game)) { model.toggleFavorite(game) }
                }
                Text(game.label).font(ChessMeStyle.title(26)).foregroundStyle(ChessMeStyle.ink)
                HStack {
                    Text(exploring ? "Explore the game" : moments.isEmpty ? "Game replay" : "Moment \(momentIndex + 1) of \(moments.count)")
                        .font(.subheadline.weight(.medium)).accessibilityIdentifier("game.moment")
                    Spacer()
                    Button(exploring ? (moments.isEmpty ? "Back to review" : "Back to moments") : "Explore") {
                        exploring.toggle()
                        if !exploring { selectMoment(momentIndex) }
                    }.font(.subheadline.weight(.semibold)).frame(minHeight: 44).accessibilityIdentifier("game.explore")
                }
                if !exploring, let moment {
                    HStack {
                        Text("Move \(moment.moveNumber) · \(moment.theme)").font(.subheadline).foregroundStyle(ChessMeStyle.green)
                        Spacer()
                        MoveQualityBadge(quality: moment.estimatedQuality)
                    }
                }
                if let replay {
                    if exploring {
                        ReviewClocksView(game: savedGame, timeline: clockTimeline, history: replay.moveHistory, index: replay.index,
                                         isVariation: replay.isVariation, loading: clocksLoading, error: clockError) { Task { await loadClocks() } }
                    }
                    LiveAnalysis(controller: analyzer, position: replay.position) { evaluation in
                    AnalysisBoardView(position: replay.position, perspective: game.playerSide, selectedSquare: selected,
                                      targets: targets, highlightedSquares: replay.previousMove.map { [$0.from, $0.to] } ?? [],
                                      moveMarker: assessment.flatMap { [.blunder, .mistake, .inaccuracy].contains($0.quality) ? BoardMoveMarker(square: replay.previousMove?.to ?? 0, quality: $0.quality) : nil },
                                      evaluation: evaluation, topMoves: model.effectiveEngineConfiguration.topMoves, onSquare: chooseSquare)
                    }
                    if !exploring, let moment {
                        HStack(spacing: 12) {
                            Button { selectMoment(momentIndex - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                                .disabled(momentIndex == 0).accessibilityLabel("Previous moment").accessibilityIdentifier("game.previousMoment")
                            if momentIndex + 1 < moments.count {
                                PrimaryButton(title: "Next moment", symbol: "arrow.right") { selectMoment(momentIndex + 1) }
                                    .accessibilityIdentifier("game.nextMoment")
                            } else {
                                PrimaryButton(title: moment.isPuzzle ? "Practice this moment" : "See this moment", symbol: "scope") {
                                    if moment.isPuzzle { model.openLesson(moment) } else { card = moment }
                                }.accessibilityIdentifier("game.practiceMoment")
                            }
                        }
                        DisclosureGroup("What happened here?") {
                            Text(moment.explanation).font(.subheadline).padding(.top, 8)
                            if momentIndex + 1 < moments.count {
                                Button("Practice this moment") { if moment.isPuzzle { model.openLesson(moment) } else { card = moment } }
                                    .font(.subheadline.weight(.semibold)).padding(.top, 8)
                            }
                        }.font(.subheadline)
                    }
                    if exploring || moments.isEmpty {
                        HStack {
                            Button { navigate(0) } label: { Image(systemName: "backward.end.fill").frame(width: 36, height: 42) }
                                .disabled(replay.index == 0 && !replay.isVariation).accessibilityLabel("First position")
                            Button {
                                self.replay?.previous(); selected = nil; variationAssessment = nil
                            } label: { Image(systemName: "chevron.left").frame(width: 36, height: 42) }
                                .disabled(replay.index == 0 && !replay.isVariation).accessibilityLabel(replay.isVariation ? "Undo variation move" : "Previous move")
                                .accessibilityIdentifier("game.previous")
                            Spacer()
                            Text(replay.isVariation ? "Variation · \(replay.variationMoves.count) \(replay.variationMoves.count == 1 ? "ply" : "plies")" : (replay.index == 0 ? "Starting position" : "Ply \(replay.index)/\(replay.moves.count)"))
                                .font(.caption.monospacedDigit()).accessibilityIdentifier("game.position")
                            Spacer()
                            Button { navigate(replay.index + 1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 42) }
                                .disabled(replay.index == replay.moves.count).accessibilityLabel("Next move")
                                .accessibilityIdentifier("game.next")
                            Button { navigate(replay.moves.count) } label: { Image(systemName: "forward.end.fill").frame(width: 36, height: 42) }
                                .disabled(replay.index == replay.moves.count).accessibilityLabel("Last position")
                        }
                    }
                    MoveHistoryView(history: replay.moveHistory, selectedIndex: replay.index, prefix: "game", title: "Imported moves") { index in exploring = true; navigate(index) }
                    if exploring || moments.isEmpty {
                        if replay.isVariation {
                            Text(replay.variationSAN).font(.subheadline.monospaced()).accessibilityIdentifier("game.variation")
                            Button("Return to game") { navigate(replay.index) }.font(.subheadline.weight(.semibold))
                                .accessibilityIdentifier("game.return")
                        } else {
                            Slider(value: Binding(get: { Double(self.replay?.index ?? 0) }, set: { navigate(Int($0)) }), in: 0...Double(max(1, replay.moves.count)), step: 1)
                                .accessibilityLabel("Game move").accessibilityIdentifier("game.timeline")
                        }
                        if let assessment { MoveQualityBadge(quality: assessment.quality).accessibilityIdentifier("game.moveQuality") }
                        if exploring { AnalysisPanel(position: replay.position, controller: analyzer, configuration: model.effectiveEngineConfiguration) }
                    }
                }
                if let replayError { Text(replayError).font(.footnote).foregroundStyle(.red) }
                if let job = model.localAnalysisJob(for: game.id) {
                    PaperCard {
                        LocalAnalysisStatusView(job: job, currentDepth: model.deviceAnalysisDepth)
                        if job.state == .running { Button("Pause") { model.pauseAnalysis() } }
                    }
                }
                HStack {
                    Text("On-device analysis").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Depth settings") { showLocalSettings = true }.font(.caption)
                        .accessibilityIdentifier("game.localSettings")
                }
                PrimaryButton(title: model.localAnalysisJob(for: game.id)?.state == .paused ? "Resume on this device" : "Analyze on this device", symbol: "cpu") {
                    analyzer.stop()
                    model.analyzeOnDevice(gameID: game.id)
                }
                .disabled(model.isImporting || model.cloudIsRunning || !DeviceAnalysisCoordinator.hardware.supportsOvernight || deviceReviewAlreadyActive)
                .accessibilityIdentifier("game.deepReview")
                if !DeviceAnalysisCoordinator.hardware.supportsOvernight {
                    Text("Deep analysis requires iPhone 15 or newer. You can still review this game with the ordinary device engine.").font(.caption)
                    Button("Run an ordinary device review") { analyzer.stop(); model.analyzePending(gameID: game.id) }
                        .disabled(model.isBusy)
                }
                if exploring {
                    Button { showEngineSettings = true } label: { Label("Analysis engines", systemImage: "slider.horizontal.3") }
                        .font(.subheadline).accessibilityIdentifier("game.engines")
                }
                if let analysis {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(reviewOrigin) review · \(analysis.analyzedPlies)/\(analysis.totalPlies) decisions\(analysis.isComplete ? "" : " · partial")")
                            .font(.caption).foregroundStyle(ChessMeStyle.muted)
                        if exploring, let assessments = analysis.moveAssessments, !assessments.isEmpty {
                            EvaluationTimeline(assessments: assessments, totalPlies: replay?.moves.count ?? 1, selectedPly: replay?.index ?? 0, onSelect: navigate)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(MoveQuality.allCases.filter { $0 != .unclassified }, id: \.self) { quality in
                                        let count = assessments.filter { $0.quality == quality }.count
                                        if count > 0 { Text("\(quality.title) \(count)").font(.caption).padding(8).background(ChessMeStyle.green.opacity(0.07), in: Capsule()) }
                                    }
                                }
                            }
                        }
                    }
                    if exploring {
                        ForEach(analysis.findings) { finding in
                            Button { if finding.isPuzzle { model.openLesson(finding) } else { card = finding } } label: {
                                PaperCard {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("Move \(finding.moveNumber) · \(finding.theme)").font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.caption)
                                        }
                                        MoveQualityBadge(quality: finding.estimatedQuality)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    if analysis.findings.isEmpty { Text("No clear teaching moments were found by this analysis.").font(.subheadline).foregroundStyle(ChessMeStyle.muted) }
                }
                if exploring && !model.isDemo && !game.id.hasPrefix("pgn-") {
                    if let review = model.cloudReview(for: game.id) {
                        Text(review.statusText).font(.subheadline).accessibilityIdentifier("cloud.review.status")
                        if review.isPending {
                            if let estimated = review.estimatedCompletionAt {
                                Text("Estimated completion: \(estimated.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                            }
                            Button("Refresh review status") { Task { await model.refreshCloudReviews() } }
                            if review.state == "queued" {
                                Button("Cancel queued review", role: .destructive) { Task { await model.cancelCloudReview(gameID: game.id) } }
                            }
                        }
                    }
                    PrimaryButton(title: model.cloudIsRunning ? "Submitting cloud review..." : "Queue a deeper cloud review", symbol: "cloud") { if model.cloudIsReady { confirmCloud = true } else { showCloudSetup = true } }
                        .disabled(model.isBusy || model.cloudReview(for: game.id)?.isPending == true)
                }
                if exploring, let url = game.url { Link("Open original game on Lichess", destination: url).font(.subheadline) }
                if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(ChessMeStyle.muted) }
            }.padding(22)
        }
        .background(ChessMeStyle.paper)
        .accessibilityIdentifier("game.scroll")
        .navigationTitle("Game review").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            do {
                let game = savedGame
                let work = Task.detached(priority: .userInitiated) { try GameReplay(game: game) }
                replay = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
                try Task.checkCancellation()
                selectMoment(0)
                rebuildClockTimeline()
                updateAnalysis()
                await loadClocks()
            }
            catch is CancellationError { }
            catch { replayError = error.localizedDescription }
        }
        .onChange(of: savedGame.clockData) { _, _ in rebuildClockTimeline() }
        .onChange(of: replay?.position) { _, _ in updateAnalysis() }
        .onChange(of: model.engineConfiguration) { _, _ in updateAnalysis() }
        .onChange(of: model.isAnalyzing) { _, busy in if busy { analyzer.stop() } else { updateAnalysis() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { updateAnalysis() } else { analyzer.stop() }
        }
        .onDisappear { analyzer.stop() }
        .sheet(isPresented: $showCloudSetup) { CloudSetupView() }
        .confirmationDialog("Promote your pawn", isPresented: Binding(get: { !promotionMoves.isEmpty }, set: { if !$0 { promotionMoves = [] } })) {
            ForEach(promotionMoves, id: \.uci) { move in Button(move.promotion?.rawValue.capitalized ?? "Queen") { play(move); promotionMoves = [] } }
        }
        .confirmationDialog("Analyze this game in the cloud?", isPresented: $confirmCloud, titleVisibility: .visible) {
            Button("Allow cloud review") { Task { await model.enhanceInCloud(game: game) } }
        } message: {
            Text("The service receives your Lichess read token and fetches this finished game. Queuing reserves one game from your monthly allowance. Reviews can wait up to 24 hours, and continue after you close the app. Cancelling before analysis starts or a failed review restores the allowance.")
        }
        .navigationDestination(isPresented: Binding(get: { card != nil }, set: { if !$0 { card = nil } })) {
            if let card { ReviewCardView(finding: card) }
        }
        .sheet(isPresented: $showLocalSettings) { NavigationStack { LocalAnalysisSettingsView().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showLocalSettings = false } } } } }
        .sheet(isPresented: $showEngineSettings) { NavigationStack { EngineSettingsView().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showEngineSettings = false } } } } }
    }

    private func selectMoment(_ index: Int) {
        guard !moments.isEmpty else { return }
        momentIndex = min(max(0, index), moments.count - 1)
        let finding = moments[momentIndex]
        // A finding describes the position before the player's decision.
        if let index = replay?.positions.firstIndex(where: { $0.fen == finding.positionFEN }) { navigate(index) }
    }
    private func navigate(_ index: Int) { replay?.navigate(to: index); selected = nil; variationAssessment = nil }
    private func rebuildClockTimeline() {
        guard let replay else { return }
        let data = savedGame.clockData ?? savedGame.pgn.flatMap { try? PGNDocument($0).clockData }
        clockTimeline = data.map { GameClockTimeline(data: $0, positions: replay.positions, status: game.status) }
    }
    private func loadClocks() async {
        guard !clocksLoading, savedGame.clockData == nil, savedGame.clockDataFetchedAt == nil, !model.isDemo, game.url != nil else { return }
        clocksLoading = true; clockError = nil
        defer { clocksLoading = false }
        do { try await model.loadGameClocks(gameID: game.id); rebuildClockTimeline() }
        catch is CancellationError { }
        catch { clockError = error.localizedDescription }
    }
    private func updateAnalysis() {
        guard let replay, !model.isAnalyzing, scenePhase == .active else { return }
        analyzer.start(position: replay.position, history: replay.repetitionHistory, configuration: model.effectiveEngineConfiguration)
    }
    private func chooseSquare(_ square: Int) {
        exploring = true
        guard let replay else { return }
        if selected == square { selected = nil; return }
        if let selected {
            let moves = replay.position.legalMoves().filter { $0.from == selected && $0.to == square }
            if moves.count > 1 { promotionMoves = moves; return }
            if let move = moves.first { play(move); return }
        }
        selected = replay.position.squares[square]?.side == replay.position.sideToMove ? square : nil
    }
    private func play(_ move: ChessMove) {
        guard let replay else { return }
        variationAssessment = analyzer.evaluation?.assessment(position: replay.position, played: move, ply: replay.index + replay.variationMoves.count)
        do { try self.replay?.play(move); selected = nil } catch { replayError = error.localizedDescription }
    }
}

struct ReviewCardView: View {
    let finding: MoveFinding
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var analyzer = PositionAnalysisController()
    @State private var position: ChessPosition
    @State private var history: [ChessPosition] = []
    @State private var selected: Int?
    @State private var promotions: [ChessMove] = []
    @State private var gameHistory: MoveHistory?
    @State private var moveHistoryCache: MoveHistory?
    @State private var playedMoves: [ChessMove] = []
    @State private var browsingPly: Int?
    private let initial: ChessPosition
    init(finding: MoveFinding) {
        self.finding = finding
        let initial = (try? ChessPosition(fen: finding.positionFEN)) ?? .initial
        self.initial = initial
        _position = State(initialValue: initial)
    }
    private var targets: Set<Int> { Set(position.legalMoves().filter { $0.from == selected }.map(\.to)) }
    private var moveHistory: MoveHistory {
        moveHistoryCache ?? MoveHistory(position: initial)
    }
    private var shownPosition: ChessPosition {
        if let browsingPly, moveHistory.positions.indices.contains(browsingPly) { return moveHistory.positions[browsingPly] }
        return position
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow(text: model.isDemo ? "Sample review card" : "\(finding.source.capitalized) finding")
                Text(finding.theme).font(ChessMeStyle.title(32))
                HStack {
                    Text("Your move: \((try? initial.san(ChessMove(uci: finding.playedMove))) ?? finding.playedMove)").font(.subheadline)
                    Spacer()
                    MoveQualityBadge(quality: finding.estimatedQuality)
                    FavoriteButton(selected: model.isFavorite(finding)) { model.toggleFavorite(finding) }
                }
                LiveAnalysis(controller: analyzer, position: shownPosition) { evaluation in
                AnalysisBoardView(position: shownPosition, perspective: initial.sideToMove, selectedSquare: selected, targets: browsingPly == nil ? targets : [],
                                  moveMarker: browsingPly == nil && position == initial ? (try? ChessMove(uci: finding.playedMove)).map { BoardMoveMarker(square: $0.to, quality: finding.estimatedQuality) } : nil,
                                  evaluation: evaluation, topMoves: model.effectiveEngineConfiguration.topMoves,
                                  fallbackMove: browsingPly == nil && position == initial ? finding.bestMove : nil, onSquare: browsingPly == nil ? choose : nil)
                }
                MoveHistoryView(history: moveHistory, selectedIndex: browsingPly ?? moveHistory.moves.count, prefix: "card") { index in
                    selected = nil; browsingPly = index == moveHistory.moves.count ? nil : index
                }
                if browsingPly != nil { Button("Return to review moment") { browsingPly = nil } }
                AnalysisPanel(position: shownPosition, controller: analyzer, configuration: model.effectiveEngineConfiguration)
                HStack {
                    Button("Undo") { if let previous = history.popLast() { position = previous; selected = nil; playedMoves.removeLast(); browsingPly = nil } }.disabled(history.isEmpty)
                    Spacer()
                    Button("Reset") { position = initial; history = []; playedMoves = []; selected = nil; browsingPly = nil }
                }
                Text(finding.explanation).font(.subheadline).lineSpacing(3)
                PrimaryButton(title: "Play saved suggestion", symbol: "arrow.right") {
                    position = initial; history = []; playedMoves = []; browsingPly = nil
                    if let move = try? ChessMove(uci: finding.bestMove) { play(move) }
                }
                Text("Explore the alternatives. This finding has insufficient evidence for a single-answer puzzle. Live lines use the device engine.")
                    .font(.caption).foregroundStyle(ChessMeStyle.muted)
            }.padding(22)
        }.background(ChessMeStyle.paper)
            .navigationTitle("Review moment").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task {
                let game = model.library.games.first { $0.id == finding.gameID }
                let finding = finding
                let work = Task.detached(priority: .userInitiated) { try MoveHistory(game: game, finding: finding) }
                gameHistory = try? await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
                guard !Task.isCancelled else { return }
                rebuildMoveHistory()
                updateAnalysis()
            }
            .onChange(of: playedMoves) { _, _ in rebuildMoveHistory() }
            .onChange(of: browsingPly) { _, _ in updateAnalysis() }
            .onChange(of: position) { _, _ in updateAnalysis() }
            .onChange(of: model.engineConfiguration) { _, _ in updateAnalysis() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { updateAnalysis() } else { analyzer.stop() } }
            .onDisappear { analyzer.stop() }
            .confirmationDialog("Promote your pawn", isPresented: Binding(get: { !promotions.isEmpty }, set: { if !$0 { promotions = [] } })) {
                ForEach(promotions, id: \.uci) { move in Button(move.promotion?.rawValue.capitalized ?? "Queen") { play(move); promotions = [] } }
            }
    }
    private func rebuildMoveHistory() {
        let base = gameHistory ?? MoveHistory(position: initial)
        moveHistoryCache = (try? base.appending(playedMoves)) ?? base
    }
    private func updateAnalysis() {
        let index = browsingPly ?? moveHistory.moves.count
        analyzer.start(position: shownPosition, history: moveHistory.positions.prefix(index).map(\.repetitionKey), configuration: model.effectiveEngineConfiguration)
    }
    private func choose(_ square: Int) {
        if selected == square { selected = nil; return }
        let moves = position.legalMoves().filter { $0.from == selected && $0.to == square }
        if moves.count > 1 { promotions = moves; return }
        if let move = moves.first { play(move); return }
        selected = position.squares[square]?.side == position.sideToMove ? square : nil
    }
    private func play(_ move: ChessMove) {
        guard let next = try? position.applying(move) else { return }
        history.append(position); playedMoves.append(move); position = next; selected = nil
    }
}
