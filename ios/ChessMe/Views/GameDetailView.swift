import SwiftUI
import ChessMeCore

struct GameReplayExplorer: View {
    let game: ChessGame
    var initialPly = 0
    var useStoredSnapshot = false
    var snapshotID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var parkedVariation: GameReplay?
    @State private var lineSaveMessage: String?
    @State private var moveExplanation: String?
    @State private var explainingMove = false
    @State private var explanationTask: Task<Void, Never>?
    @State private var explanationRequest = UUID()
    @State private var engineReplies = false
    @State private var replyTask: Task<Void, Never>?
    @State private var contextGeneration: UUID?
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
    @State private var exploring = true
    @State private var momentIndex = 0
    @State private var highlightedQuality: MoveQuality?
    private var moments: [MoveFinding] {
        (analysis?.findings ?? []).sorted { $0.moveNumber < $1.moveNumber }
    }
    private var moment: MoveFinding? { moments.indices.contains(momentIndex) ? moments[momentIndex] : nil }
    private var analysis: GameAnalysis? { useStoredSnapshot ? nil : model.gameAnalysis(for: game.id) }
    private var savedGame: ChessGame { useStoredSnapshot ? game : (model.library.games.first { $0.id == game.id } ?? game) }
    private var openingLine: OpeningLine? { model.openingLine(for: savedGame) }
    private var bookPlies: Set<Int> {
        let nonBook = Set((analysis?.moveAssessments ?? []).filter { $0.quality != .book }.map(\.ply))
        return Set(openingLine?.moves.keys.map { $0 } ?? []).subtracting(nonBook)
    }
    private var displayedQuality: MoveQuality? {
        if let assessment { return assessment.quality }
        guard let replay else { return nil }
        if replay.isVariation {
            return OpeningBook.shared.line(in: replay, includingVariation: true).moves[replay.index + replay.variationMoves.count - 1] != nil ? .book : nil
        }
        guard bookPlies.contains(replay.index - 1) else { return nil }
        return .book
    }
    private var currentOpening: OpeningVariation? {
        guard let replay else { return nil }
        if replay.isVariation { return OpeningBook.shared.line(in: replay, includingVariation: true).opening }
        return assessment?.opening ?? openingLine?.opening(at: replay.index)
    }
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
                if model.isDemo { Eyebrow(text: "Sample game") }
                HStack(alignment: .center, spacing: 12) {
                    Group {
                    if useStoredSnapshot {
                        Text("Explore continuation").font(ChessMeStyle.title(22))
                    } else {
                        GamePlayerNames(game: savedGame, outcome: model.outcome(for: savedGame), prominent: true)
                    }
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("game.match")
                }
                if let opening = openingLine?.opening {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(opening.name, systemImage: "book.closed.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(ChessMeStyle.ink)
                            .accessibilityIdentifier("game.openingName")
                        Text("\(opening.eco) · \(bookPlies.count) book moves")
                            .font(.caption).foregroundStyle(ChessMeStyle.muted)
                            .accessibilityIdentifier("game.bookSummary")
                    }
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
                        ReviewClocksView(game: savedGame, timeline: clockTimeline, index: replay.index,
                                         isVariation: replay.isVariation, loading: clocksLoading, error: clockError) { Task { await loadClocks() } }
                    }
                    LiveAnalysis(controller: analyzer, position: replay.position) { evaluation in
                    AnalysisBoardView(position: replay.position, perspective: game.playerSide, selectedSquare: selected,
                                      targets: targets, highlightedSquares: replay.previousMove.map { [$0.from, $0.to] } ?? [],
                                      moveMarker: assessment.flatMap { [.blunder, .mistake, .inaccuracy].contains($0.quality) ? BoardMoveMarker(square: replay.previousMove?.to ?? 0, quality: $0.quality) : nil },
                                      suggestions: evaluation?.goodMoves(in: replay.position) ?? [],
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
                            LiveAnalysis(controller: analyzer, position: replay.position) { evaluation in
                                BoardIconButton(title: "Play best move", symbol: "play.fill") {
                                    if let move = evaluation?.best?.move { play(move) }
                                }.disabled(evaluation?.best == nil)
                                    .accessibilityIdentifier("game.bestMove")
                            }
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
                    if let analysis {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(reviewOrigin) review \(analysis.isComplete ? "ready" : "in progress") · \(analysis.analyzedPlies)/\(analysis.totalPlies) decisions")
                                .font(.caption).foregroundStyle(ChessMeStyle.muted).accessibilityIdentifier("game.reviewStatus")
                            if let assessments = analysis.moveAssessments, !assessments.isEmpty {
                                EvaluationTimeline(assessments: assessments, totalPlies: replay.moves.count, selectedPly: replay.index,
                                                   source: analysis.source, highlightedQuality: highlightedQuality) { index in exploring = true; navigate(index) }
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                        ForEach([MoveQuality.excellent, .inaccuracy, .mistake, .blunder], id: \.self) { quality in
                                            let count = assessments.filter { $0.quality == quality }.count
                                            Button { highlightedQuality = highlightedQuality == quality ? nil : quality } label: {
                                                Text("\(quality.title) \(count)").font(.caption.weight(.semibold))
                                                    .frame(maxWidth: .infinity, minHeight: 44)
                                                    .foregroundStyle(highlightedQuality == quality ? .white : ChessMeStyle.ink)
                                                    .background(highlightedQuality == quality ? ChessMeStyle.green : ChessMeStyle.green.opacity(0.08), in: Capsule())
                                            }.buttonStyle(.plain).disabled(count == 0)
                                                .accessibilityIdentifier("game.quality.\(quality.rawValue)")
                                                .accessibilityValue(highlightedQuality == quality ? "Highlighted on graph" : "")
                                                .accessibilityAddTraits(highlightedQuality == quality ? .isSelected : [])
                                        }
                                }
                            }
                        }
                    }
                    if exploring || moments.isEmpty {
                        MoveHistoryView(history: replay.moveHistory, selectedIndex: replay.index, prefix: "game", title: nil, showsNavigation: false, bookPlies: bookPlies) { index in exploring = true; navigate(index) }
                        if !replay.isVariation {
                            let rootFinding = analysis?.findings.first { $0.positionFEN == replay.position.fen }
                            if let rootFinding {
                                VStack(alignment: .leading, spacing: 10) {
                                    Menu {
                                    Button("Play the game's choice") {
                                        if let move = try? ChessMove(uci: rootFinding.playedMove) { play(move) }
                                    }.accessibilityIdentifier("game.comparePlayed")
                                    Button("Play the saved suggestion") {
                                        if let move = try? ChessMove(uci: rootFinding.bestMove) { play(move) }
                                    }.accessibilityIdentifier("game.compareSuggested")
                                    } label: { Label("Compare moves", systemImage: "arrow.left.arrow.right") }
                                        .buttonStyle(.bordered).accessibilityIdentifier("game.compareOptions")
                                }
                            }
                        }
                        if replay.isVariation {
                            Text(replay.variationSAN).font(.subheadline.monospaced()).accessibilityIdentifier("game.variation")
                            HStack {
                                Button("Save line") {
                                    lineSaveMessage = model.saveReviewLine(game: savedGame, replay: replay,
                                        expectedGeneration: contextGeneration, snapshotID: snapshotID) ?
                                        (model.isDemo ? "Saved in sample collection" : "Saved on this device") : nil
                                }.accessibilityIdentifier("game.saveLine")
                                Spacer()
                                BoardIconButton(title: "Explain this move", symbol: "questionmark.circle") { explainSelectedMove(replay) }
                                    .disabled(explainingMove).accessibilityIdentifier("game.explainMove")
                                BoardIconButton(title: "Return to game", symbol: "arrow.uturn.backward") { parkedVariation = replay; navigate(replay.index) }
                                    .accessibilityIdentifier("game.return")
                            }.frame(minHeight: 44)
                            if let lineSaveMessage { Text(lineSaveMessage).font(.caption).accessibilityIdentifier("game.lineSaved") }
                            if explainingMove { ProgressView("Checking this move") }
                            if let moveExplanation { Text(moveExplanation).font(.subheadline).accessibilityIdentifier("game.moveExplanation") }
                            ReviewSaveNotice()
                        } else {
                            if let parkedVariation {
                                Button("Back to my line") { self.replay = parkedVariation }
                                    .accessibilityIdentifier("game.restoreLine")
                            }
                            Slider(value: Binding(get: { Double(self.replay?.index ?? 0) }, set: { navigate(Int($0)) }), in: 0...Double(max(1, replay.moves.count)), step: 1)
                                .accessibilityLabel("Game move").accessibilityIdentifier("game.timeline")
                        }
                        if let displayedQuality {
                            HStack(alignment: .top, spacing: 10) {
                                MoveQualityBadge(quality: displayedQuality).accessibilityIdentifier("game.moveQuality")
                                if displayedQuality == .book, let opening = currentOpening {
                                    Text(opening.name).font(.caption).foregroundStyle(ChessMeStyle.muted).padding(.top, 6)
                                        .accessibilityIdentifier("game.currentOpening")
                                }
                            }
                        }
                        if exploring {
                            AnalysisPanel(position: replay.position, controller: analyzer, configuration: model.effectiveEngineConfiguration)
                        }
                    }
                }
                if let replayError { Text(replayError).font(.footnote).foregroundStyle(.red) }
                if !useStoredSnapshot {
                if let job = model.localAnalysisJob(for: game.id) {
                    PaperCard {
                        if analysis?.isComplete == true, job.isPending {
                            Text("Your saved review is ready. A deeper review is \(job.state == .running ? "running" : "queued").")
                                .font(.caption).accessibilityIdentifier("game.deeperReviewStatus")
                        }
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
                if let action = model.deviceReviewAction(for: game.id) {
                    PrimaryButton(title: action, symbol: "cpu") {
                        analyzer.stop()
                        model.analyzeOnDevice(gameID: game.id)
                    }
                    .disabled(model.isImporting || model.cloudIsRunning || !DeviceAnalysisCoordinator.hardware.supportsOvernight || deviceReviewAlreadyActive)
                    .accessibilityIdentifier("game.deepReview")
                }
                if !DeviceAnalysisCoordinator.hardware.supportsOvernight {
                    Text(LocalAnalysisLevel.balanced.requirement).font(.caption)
                    Button("Run an ordinary device review") { analyzer.stop(); model.analyzePending(gameID: game.id) }
                        .disabled(model.isBusy)
                }
                if let analysis {
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
                }
                if exploring, !useStoredSnapshot, let url = game.url { Link("Open original game on Lichess", destination: url).font(.subheadline) }
                if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(ChessMeStyle.muted) }
            }.padding(22)
        }
        .background(ChessMeStyle.paper)
        .accessibilityIdentifier("game.scroll")
        .navigationTitle("Explore").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BoardIconButton(title: "Return to review", symbol: "chevron.left") { dismiss() }.accessibilityIdentifier("game.explore")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Engine replies", isOn: $engineReplies).accessibilityIdentifier("game.engineReplies")
                    Button("Reset variation", systemImage: "arrow.counterclockwise") {
                        if let replay { navigate(replay.index) }; parkedVariation = nil
                    }.disabled(replay?.isVariation != true && parkedVariation == nil).accessibilityIdentifier("game.resetVariation")
                    Button("Discard temporary line") { parkedVariation = nil }
                        .disabled(parkedVariation == nil)
                    Button("Analysis settings", systemImage: "slider.horizontal.3") { showEngineSettings = true }
                        .accessibilityIdentifier("game.engines")
                    Button(model.isFavorite(game) ? "Remove from saved games" : "Save game", systemImage: "heart") { model.toggleFavorite(game) }
                } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel("Explore options").accessibilityIdentifier("game.options")
            }
        }
        .task {
            contextGeneration = model.reviewGeneration
            do {
                let game = savedGame
                let work = Task.detached(priority: .userInitiated) { try GameReplay(game: game) }
                replay = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
                try Task.checkCancellation()
                navigate(initialPly)
                rebuildClockTimeline()
                updateAnalysis()
                await loadClocks()
            }
            catch is CancellationError { }
            catch { replayError = error.localizedDescription }
        }
        .onChange(of: savedGame.clockData) { _, _ in rebuildClockTimeline() }
        .onChange(of: model.reviewGeneration) { _, _ in
            analyzer.stop(); explanationTask?.cancel(); replyTask?.cancel(); replay = nil; dismiss()
        }
        .onChange(of: analysis) { previous, current in
            if !exploring, !moments.isEmpty {
                let earlier = (previous?.findings ?? []).sorted { $0.moveNumber < $1.moveNumber }
                let selectedID = earlier.indices.contains(momentIndex) ? earlier[momentIndex].id : nil
                let nextIndex = selectedID.flatMap { id in moments.firstIndex { $0.id == id } } ?? min(momentIndex, moments.count - 1)
                selectMoment(nextIndex)
            }
            if let highlightedQuality, current?.moveAssessments?.contains(where: { $0.quality == highlightedQuality }) != true {
                self.highlightedQuality = nil
            }
        }
        .onChange(of: replay?.position) { _, _ in
            replyTask?.cancel(); replyTask = nil
            explanationRequest = UUID(); explanationTask?.cancel(); moveExplanation = nil; explainingMove = false
            updateAnalysis()
        }
        .onChange(of: model.engineConfiguration) { _, _ in updateAnalysis() }
        .onChange(of: engineReplies) { _, enabled in if enabled { scheduleReply() } else { replyTask?.cancel(); replyTask = nil } }
        .onReceive(analyzer.$isCalculating) { calculating in if !calculating { scheduleReply() } }
        .onChange(of: model.isAnalyzing) { _, busy in if busy { analyzer.stop() } else { updateAnalysis() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { updateAnalysis() } else { analyzer.stop() }
        }
        .onDisappear { analyzer.stop(); explanationTask?.cancel(); replyTask?.cancel(); replyTask = nil }
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

    private func explainSelectedMove(_ replay: GameReplay) {
        guard let move = replay.variationMoves.last else { return }
        let before = replay.variationPositions.dropLast().last ?? replay.positions[replay.index]
        let history = Array(replay.repetitionHistory.dropLast())
        let ticket = UUID(); explanationRequest = ticket; explainingMove = true
        explanationTask?.cancel()
        explanationTask = Task {
            do {
                let evaluation = try await analyzer.evaluateAttempt(move: move, position: before, history: history,
                                                                   configuration: model.effectiveEngineConfiguration)
                guard !Task.isCancelled, explanationRequest == ticket else { return }
                moveExplanation = ReviewMoveAcceptance.explanation(move: move, position: before, evaluation: evaluation)
            } catch {
                guard !Task.isCancelled, explanationRequest == ticket else { return }
                moveExplanation = "This move could not be verified. Your line remains available. " + error.localizedDescription
            }
            if explanationRequest == ticket { explainingMove = false }
        }
    }

    private func selectMoment(_ index: Int) {
        guard !moments.isEmpty else { return }
        momentIndex = min(max(0, index), moments.count - 1)
        let finding = moments[momentIndex]
        // A finding describes the position before the player's decision.
        if let index = replay?.positions.firstIndex(where: { $0.fen == finding.positionFEN }) { navigate(index) }
    }
    private func scheduleReply() {
        guard engineReplies, replyTask == nil, !analyzer.isCalculating, let replay,
              replay.position.sideToMove != game.playerSide,
              replay.position.outcome() == .ongoing,
              let reply = analyzer.evaluation(for: replay.position)?.best?.move else { return }
        let fen = replay.position.fen
        replyTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, engineReplies, self.replay?.position.fen == fen else { return }
            play(reply); replyTask = nil
        }
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
        variationAssessment = analyzer.evaluation(for: replay.position)?.assessment(position: replay.position, played: move, ply: replay.index + replay.variationMoves.count)
        do {
            try self.replay?.play(move)
            if let trial = self.replay, let assessment = variationAssessment {
                let sample = GameAnalysis(gameID: game.id, findings: [], analyzedPlies: 1, totalPlies: 1, moveAssessments: [assessment])
                variationAssessment = OpeningBook.shared.line(in: trial, includingVariation: true).annotating(sample).moveAssessments?.first
            }
            selected = nil
        } catch { replayError = error.localizedDescription }
    }
}

struct ReviewCardView: View {
    let finding: MoveFinding
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if let game = model.library.games.first(where: { $0.id == finding.gameID }) {
            GameDetailView(game: game, initialMomentID: finding.id)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(finding.theme).font(ChessMeStyle.title(26))
                    Text(finding.explanation).font(.subheadline)
                    ReviewLineView(fen: finding.positionFEN, moves: finding.continuation)
                    Text("Retained position. The source game is unavailable on this device.").font(.caption)
                }.padding(22)
            }.background(ChessMeStyle.paper).navigationTitle("Saved position")
        }
    }
}
