import SwiftUI
import ChessMeCore

struct ReviewPracticeView: View {
    let finding: MoveFinding
    var puzzle: TrainingPuzzle? = nil
    var linkedTargetID: String? = nil
    var connectionText: String? = nil
    var resumeSessionResult = false
    var sessionID: String? = nil
    var resumeRunID: String? = nil
    var returnGameID: String? = nil
    var parentRunID: String? = nil
    var onContinue: (() -> Void)? = nil
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.chessReduceMotion) private var reduceMotion
    @StateObject private var analyzer = PositionAnalysisController()
    @StateObject private var motion = TrainingBoardMotion()
    @State private var run: AdaptiveReviewRun?
    @State private var generation: UUID?
    @State private var selected: Int?
    @State private var promotions: [ChessMove] = []
    @State private var checking = false
    @State private var error: String?
    @State private var pendingMove: ChessMove?
    @State private var work: Task<Void, Never>?
    @State private var ticket = UUID()
    @State private var showingDetails = false
    @State private var introPlaying = false
    @State private var hasPlayedIntro = false
    @State private var exploration: ChessGame?
    @State private var showingWhy = false
    @State private var showingHint = false
    @State private var solution: [String] = []
    @State private var solutionFEN: String?
    @State private var resumedRelated: AdaptiveReviewRun?
    private var sourceStatus: String {
        guard let run, run.attempt.kind == .game,
              let target = model.reviewState.targets.first(where: { $0.id == run.targetID }) else { return "" }
        return target.revision + String(target.invalidated)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let run {
                    HStack {
                        Text(puzzle == nil ? "From your game" : "Lichess puzzle · \(puzzle!.rating)")
                        Spacer()
                        if model.isDemo { Text("Sample") }
                    }.font(.caption).foregroundStyle(ChessMeStyle.muted)
                    Text(run.isFinished ? run.attempt.summary : run.practiceGoal.prompt)
                        .font(ChessMeStyle.title(22)).frame(minHeight: 54, alignment: .leading)
                        .accessibilityIdentifier("practice.prompt")
                    HStack(spacing: 8) {
                        if checking || introPlaying || run.pendingReply != nil {
                            ProgressView()
                            Text(checking ? "Checking your move…" : introPlaying ? "Replaying previous moves…" : "Opponent's reply…")
                                .accessibilityIdentifier("practice.checking")
                            Spacer()
                            if checking {
                                BoardIconButton(title: "Cancel check", symbol: "xmark") { cancelCheck() }
                                    .accessibilityIdentifier("practice.cancelCheck")
                            } else if introPlaying {
                                BoardIconButton(title: "Skip replay", symbol: "forward.end.fill") { motion.stop(); introPlaying = false }
                            }
                        } else {
                            Text(run.practiceGoal == .mate ? "Complete the mating continuation." : run.acceptedDecisions <= run.decisionLimit ?
                                 "\(run.acceptedDecisions) of \(run.decisionLimit) key decisions accepted." :
                                 "\(run.acceptedDecisions) decisions accepted; verify the goal.")
                                .accessibilityIdentifier("practice.decisions")
                            Spacer()
                        }
                    }.font(.caption).frame(minHeight: 44)
                    if run.attempt.outcome == .revealed {
                        ReviewLineView(fen: solutionFEN ?? run.currentFEN,
                                       moves: solution.isEmpty ? answerLine(for: run) : solution, perspective: run.solver)
                    } else {
                        ChessBoardView(position: motion.position ?? run.position, perspective: run.solver, selectedSquare: selected,
                                       targets: legalTargets(run), highlightedSquares: motion.lastMove.map { [$0.from, $0.to] } ?? [],
                                       rejectionCount: motion.rejectionCount, successCount: motion.successCount,
                                       successSquare: motion.successSquare, playsMoveSounds: true,
                                       onSquare: run.isFinished || checking || introPlaying || run.pendingReply != nil ? nil : choose)
                            .accessibilityIdentifier("practice.board")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        if let feedback = run.feedback { Text(feedback).accessibilityIdentifier("practice.feedback") }
                        else if !run.isFinished && !checking && !introPlaying { Text("\(run.solver.rawValue.capitalized) to move").foregroundStyle(ChessMeStyle.muted) }
                        if let error { Text(error).foregroundStyle(ChessMeStyle.muted) }
                    }.font(.subheadline).frame(minHeight: 40, alignment: .topLeading)
                    if let pendingMove, !run.isFinished, !checking, run.pendingReply == nil,
                       error != nil || run.attempt.decisions.last?.grade == .ungraded {
                        Button("Retry analysis") { check(pendingMove) }.buttonStyle(.bordered)
                            .accessibilityIdentifier("practice.retryAnalysis")
                    }
                    if run.isFinished { result(run) }
                    else { controls(run) }
                } else if let error {
                    Text(error).font(.subheadline)
                    Text("This exercise is unassessed. You can continue with the review.").font(.caption)
                    if generation == model.reviewGeneration { Button("Start a new attempt") {
                        model.retireUnfinishedReviewRun(finding: finding, puzzle: puzzle, linkedTargetID: linkedTargetID)
                        generation = nil; self.error = nil; prepare()
                    } }
                    Button("Continue", action: finish)
                } else { ProgressView("Restoring exercise…") }
                ReviewSaveNotice()
            }.padding(22)
        }.background(ChessMeStyle.paper).navigationTitle(puzzle == nil ? "Game practice" : "Optional puzzle")
            .navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .navigationBarBackButtonHidden(puzzle != nil)
            .toolbar { if puzzle != nil { ToolbarItem(placement: .topBarLeading) { Button("Back", action: finish) } } }
            .task {
                prepare()
                if !hasPlayedIntro, let run, let lead = model.practiceLeadIn(for: run) {
                    hasPlayedIntro = true; introPlaying = true
                    await motion.replay(lead, reduceMotion: reduceMotion)
                    introPlaying = false
                }
            }
            .task(id: run?.pendingReply) {
                guard run?.pendingReply != nil else { return }
                // The persisted reply is the transition token. Restarting the view
                // consumes that token once instead of generating another reply.
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, generation == model.reviewGeneration else { return }
                mutate { $0.playReply() }
            }
            .onDisappear { cancelCheck(); introPlaying = false }
            .safeAreaInset(edge: .bottom) {
                if run?.isFinished == true {
                    HStack(spacing: 12) {
                        BoardIconButton(title: "Explore continuation", symbol: "arrow.triangle.branch") { openExploration() }
                            .accessibilityIdentifier(puzzle == nil ? "practice.exploreLine" : "practice.explorePuzzle")
                        PrimaryButton(title: "Continue", symbol: "arrow.right", action: finish)
                            .accessibilityIdentifier("practice.continue")
                    }.padding(.horizontal, 22).padding(.vertical, 10).background(ChessMeStyle.paper)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Practice details", systemImage: "info.circle") { showingDetails = true }
                        Button(puzzle.map { model.isFavorite($0) } ?? model.isFavorite(finding) ? "Remove saved position" : "Save position", systemImage: "heart") {
                            if let puzzle { model.toggleFavorite(puzzle) } else { model.toggleFavorite(finding) }
                        }
                    } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                        .accessibilityLabel("Practice details")
                }
            }
            .sheet(isPresented: $showingDetails) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(finding.theme).font(ChessMeStyle.title(23))
                            Text(finding.gameLabel)
                            if let run {
                                if run.isFinished, let connectionText = model.puzzleConnectionExplanation(for: run) ?? connectionText {
                                    Text("Connection to your game").font(.headline)
                                    Text(connectionText).accessibilityIdentifier("practice.connection")
                                }
                                if run.attempt.knownSeenBefore { Text("Previously seen position") }
                                if run.attempt.topicCued { Text("The prompt provides a topic cue.") }
                                Text("Completion, later recall and new-position results have separate evidence.").font(.caption)
                                NavigationLink { ReviewAttemptView(attemptID: run.attempt.id) } label: { Label("Attempt history", systemImage: "clock") }
                            }
                            if let puzzle { Link("Puzzle \(puzzle.id) · Lichess · CC0", destination: puzzle.url) }
                        }.padding(22)
                    }.background(ChessMeStyle.paper).navigationTitle("Practice details")
                        .toolbar { Button("Done") { showingDetails = false } }
                }
            }
            .navigationDestination(isPresented: Binding(get: { exploration != nil }, set: { if !$0 { exploration = nil } })) {
                if let exploration, let run {
                    GameReplayExplorer(game: exploration, initialPly: exploration.moves.split(separator: " ").count,
                                       useStoredSnapshot: true, snapshotID: run.id)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { cancelCheck() }
            }
            .onChange(of: run?.isFinished) { _, finished in
                if finished == true, puzzle == nil, run?.relatedOffer == nil,
                   let offer = model.relatedConnection(for: finding) { mutate { $0.relatedOffer = offer } }
            }
            .navigationDestination(isPresented: Binding(get: { resumedRelated != nil }, set: { if !$0 { resumedRelated = nil } })) {
                if let resumedRelated, let snapshot = resumedRelated.puzzleSnapshot {
                    ReviewPracticeView(finding: resumedRelated.sourceFinding, puzzle: snapshot, linkedTargetID: resumedRelated.targetID,
                                       resumeSessionResult: true, sessionID: sessionID, resumeRunID: resumedRelated.id)
                }
            }
            .onChange(of: model.reviewGeneration) { _, _ in
                cancelCheck(recordInterruption: false); run = nil
                error = "The local context changed. Return to your games or start a retained lesson again."
            }
            .onChange(of: sourceStatus) { _, _ in
                guard let run, run.attempt.kind == .game,
                      let target = model.reviewState.targets.first(where: { $0.id == run.targetID }),
                      target.invalidated || target.revision != run.revision else { return }
                cancelCheck(recordInterruption: false); self.run = nil
                error = "The source lesson changed. This attempt remains in history; return to its updated review to continue."
            }
            .confirmationDialog("Promote pawn", isPresented: Binding(get: { !promotions.isEmpty }, set: { if !$0 { promotions = [] } })) {
                ForEach(promotions, id: \.uci) { move in
                    Button(move.promotion?.rawValue.capitalized ?? "Promote") { promotions = []; check(move) }
                }
            }
            .sheet(isPresented: $showingWhy) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("One supported response").font(ChessMeStyle.title(24))
                            Text("This line explains the feedback. Your accepted moves and current decision remain in place.").font(.subheadline)
                            if let run { ReviewLineView(fen: run.currentFEN, moves: run.counterline, perspective: run.solver) }
                        }.padding(22)
                    }.background(ChessMeStyle.paper).toolbar { Button("Done") { showingWhy = false } }
                }
            }
    }

    @ViewBuilder private func controls(_ run: AdaptiveReviewRun) -> some View {
        if !run.counterline.isEmpty {
            HStack {
                Button { mutate { $0.requestHelp(.counterline) }; showingWhy = true } label: { Label("Show why", systemImage: "questionmark.circle") }
                    .accessibilityIdentifier("practice.showWhy")
                Spacer()
                Button { selected = nil; showingHint = false; mutate { $0.feedback = nil; $0.counterline = [] } } label: {
                    Label("Try again", systemImage: "arrow.counterclockwise")
                }.accessibilityIdentifier("practice.tryAgain")
            }.buttonStyle(.bordered).font(.subheadline)
        }
        if showingHint { Text(hint(for: run)).font(.subheadline).accessibilityIdentifier("practice.hintText") }
        HStack(spacing: 12) {
            BoardIconButton(title: run.hintLevel == 0 ? "Hint" : "More help", symbol: "lightbulb") {
                mutate { $0.requestHelp(.hint) }; showingHint = true
            }.accessibilityIdentifier("practice.hint")
            Menu {
                Button("Show solution", systemImage: "eye") {
                    solutionFEN = run.currentFEN; solution = answerLine(for: run)
                    mutate { $0.reviewAnswer() }
                }.accessibilityIdentifier("practice.reveal")
                if model.practiceLeadIn(for: run) != nil {
                    Button("Replay previous moves", systemImage: "arrow.counterclockwise") {
                        Task {
                            guard let lead = model.practiceLeadIn(for: run) else { return }
                            introPlaying = true; await motion.replay(lead, reduceMotion: reduceMotion); introPlaying = false
                        }
                    }
                }
                Button("Explore position", systemImage: "arrow.triangle.branch") {
                    mutate { $0.requestHelp(.line) }; openExploration()
                }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).background(ChessMeStyle.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12)) }
                .accessibilityLabel("More practice actions").accessibilityIdentifier("practice.options")
            Spacer()
            Button { mutate { $0.skip() }; finish() } label: { Label("Skip", systemImage: "forward.end") }
                .accessibilityIdentifier("practice.skip")
        }.disabled(checking || introPlaying || run.pendingReply != nil)
    }

    @ViewBuilder private func result(_ run: AdaptiveReviewRun) -> some View {
        if run.attempt.outcome == .ungraded {
            Button("Try another continuation") { self.run = nil; generation = nil; error = nil; prepare(forceNewAttempt: true) }
                .buttonStyle(.bordered)
        }
        if puzzle == nil, let connection = run.relatedOffer {
            PaperCard {
                HStack(spacing: 14) {
                    ChessBoardView(position: (try? ChessPosition(fen: connection.puzzle.positionFEN)) ?? .initial)
                        .frame(width: 60, height: 60).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Same idea, new position").font(.subheadline.weight(.semibold))
                        Text("Optional puzzle · \(connection.puzzle.rating)").font(.caption).foregroundStyle(ChessMeStyle.muted)
                        NavigationLink {
                            ReviewPracticeView(finding: connection.puzzle.reviewFinding, puzzle: connection.puzzle,
                                               linkedTargetID: run.targetID, connectionText: connection.explanation,
                                               sessionID: sessionID, returnGameID: returnGameID, parentRunID: sessionID == nil ? run.id : nil)
                        } label: { Label("Try related puzzle", systemImage: "play.fill") }.accessibilityIdentifier("practice.related")
                    }
                }
            }
        }
    }

    private func openExploration() {
        guard let run else { return }
        do { exploration = try model.practiceExploration(for: run) }
        catch { self.error = error.localizedDescription }
    }

    private func prepare(forceNewAttempt: Bool = false) {
        guard run == nil, generation == nil else { return }
        generation = model.reviewGeneration
        do {
            run = try model.prepareReviewRun(finding: finding, puzzle: puzzle, linkedTargetID: linkedTargetID,
                                             resumeSessionResult: resumeSessionResult && !forceNewAttempt, sessionID: sessionID,
                                             resumeRunID: forceNewAttempt ? nil : resumeRunID, returnGameID: returnGameID, parentRunID: parentRunID)
            // Explicit contexts distinguish a set exercise, recap, and a
            // standalone review invitation when restoring navigation.
            if puzzle == nil, let run, run.isFinished, let active = model.reviewState.session?.activeRelatedRunID,
               let related = model.reviewState.runs.first(where: { $0.id == active && $0.targetID == run.targetID && $0.puzzleSnapshot != nil }) {
                resumedRelated = related
            }
        }
        catch { self.error = error.localizedDescription }
    }
    private func legalTargets(_ run: AdaptiveReviewRun) -> Set<Int> {
        guard let selected else { return [] }
        return Set(run.position.legalMoves().filter { $0.from == selected }.map(\.to))
    }
    private func choose(_ square: Int) {
        guard let run, !checking, !run.isFinished, run.pendingReply == nil else { return }
        let board = run.position
        if let selected {
            let moves = board.legalMoves().filter { $0.from == selected && $0.to == square }
            if moves.count > 1 { promotions = moves; return }
            if let move = moves.first { check(move); return }
        }
        selected = selected == square ? nil : (board.squares[square]?.side == run.solver ? square : nil)
    }
    private func check(_ move: ChessMove) {
        guard let run, let generation, generation == model.reviewGeneration, !checking, !run.isFinished else { return }
        let board = run.position, id = run.id, history = run.history, revision = run.revision
        guard board.legalMoves().contains(move) else { return }
        let nextTicket = UUID(); ticket = nextTicket; pendingMove = move; selected = nil
        error = nil; showingHint = false
        motion.previewAttempt(move, in: board)
        var reused = run
        if reused.submitStoredMove(move, verifiedDepth: model.storedDecisionDepth(for: run, move: move)) {
            mutate { $0 = reused }; motion.stop(); motion.celebrate(at: move.to)
            return
        }
        if (try? board.applying(move).outcome()) == .checkmate(winner: run.solver) {
            applyFeedback(move, evaluation: PositionEvaluation(moves: [], completedDepth: 0, nodes: 0))
            return
        }
        checking = true
        work?.cancel()
        work = Task {
            do {
                let evaluation = try await analyzer.evaluateAttempt(move: move, position: board, history: history,
                                                                    configuration: model.effectiveEngineConfiguration)
                guard !Task.isCancelled, ticket == nextTicket, generation == model.reviewGeneration,
                      self.run?.id == id, self.run?.revision == revision, self.run?.currentFEN == board.fen else { return }
                checking = false
                applyFeedback(move, evaluation: evaluation)
            } catch {
                guard !Task.isCancelled, ticket == nextTicket, generation == model.reviewGeneration else { return }
                checking = false
                motion.stop()
                self.error = "Your move is unassessed: \(error.localizedDescription)"
                mutate {
                    $0.attempt.decisions.append(ReviewDecision(positionFEN: board.fen, move: move.uci, grade: .ungraded))
                }
            }
        }
    }
    private func applyFeedback(_ move: ChessMove, evaluation: PositionEvaluation) {
        let previousCount = run?.attempt.decisions.count ?? 0
        mutate { $0.submit(move, evaluation: evaluation) }
        motion.stop()
        guard let run, run.attempt.decisions.count > previousCount, let decision = run.attempt.decisions.last else { return }
        if decision.grade == .accepted { motion.celebrate(at: move.to) }
        else if decision.grade == .mistake { motion.shake() }
    }
    private func cancelCheck(recordInterruption: Bool = true) {
        let wasChecking = checking
        ticket = UUID(); work?.cancel(); work = nil; checking = false; motion.stop()
        guard recordInterruption, wasChecking, let run, !run.isFinished, let pendingMove else { return }
        error = "Move checking stopped. Retry analysis when you are ready."
        mutate { $0.attempt.decisions.append(ReviewDecision(positionFEN: run.currentFEN, move: pendingMove.uci, grade: .ungraded)) }
    }
    private func mutate(_ change: (inout AdaptiveReviewRun) -> Void) {
        guard var value = run, let generation, generation == model.reviewGeneration else { return }
        if value.attempt.kind == .game, let target = model.reviewState.targets.first(where: { $0.id == value.targetID }),
           target.invalidated || target.revision != value.revision { return }
        change(&value); run = value
        _ = model.saveReviewRun(value, generation: generation)
    }
    private func answerLine(for run: AdaptiveReviewRun) -> [String] {
        run.practiceContinuation
    }
    private func hint(for run: AdaptiveReviewRun) -> String {
        guard run.hintLevel > 1, let token = answerLine(for: run).first,
              let move = try? ChessMove(uci: token), let piece = run.position.squares[move.from] else {
            return "Check the opponent's threats, then consider checks, captures, and useful improvements."
        }
        if run.hintLevel == 2 { return "Look for a useful move with your \(piece.kind.rawValue)." }
        return "Inspect the \(piece.kind.rawValue) on \(ReviewLineProof.square(move.from)). Show solution when you want the line."
    }
    private func finish() {
        if puzzle != nil, model.reviewState.session?.activeRelatedRunID == run?.id {
            model.changeReview { $0.session?.activeRelatedRunID = nil }
        }
        if puzzle != nil, model.reviewState.standalonePractice?.runID == run?.id {
            model.changeReview { $0.standalonePractice = nil }
        }
        if let onContinue { onContinue() } else { dismiss() }
    }
}

struct ReviewPracticeSetView: View {
    let findings: [MoveFinding]
    var originGameID: String? = nil
    let onFinish: () -> Void
    @EnvironmentObject private var model: AppModel
    @State private var items: [MoveFinding] = []
    @State private var index = 0
    @State private var recap = false
    @State private var started = false
    @State private var sessionID: String?
    @State private var resumedRelated: AdaptiveReviewRun?
    private var record: ReviewFollowUpSession? { model.reviewState.session.flatMap { $0.id == sessionID ? $0 : nil } }
    private var attempts: [ReviewPracticeAttempt] {
        guard let record else { return [] }
        return model.reviewState.attempts.filter { record.attemptIDs.contains($0.id) && $0.kind == .game }
    }
    var body: some View {
        Group {
            if recap || items.isEmpty { recapView }
            else if items.indices.contains(index) {
                ReviewPracticeView(finding: items[index], resumeSessionResult: true, sessionID: sessionID) { advance() }.id(items[index].id + (sessionID ?? ""))
                    .safeAreaInset(edge: .top) {
                        HStack {
                            Text("Position \(index + 1) of \(items.count)").font(.caption)
                            Spacer()
                            Button("Finish for now") { recap = true; persistCursor(finished: false) }.font(.caption)
                        }.padding(.horizontal, 22).padding(.vertical, 8).background(ChessMeStyle.paper)
                    }
            }
        }.task { initialize() }
            .navigationDestination(isPresented: Binding(get: { resumedRelated != nil }, set: { if !$0 { resumedRelated = nil } })) {
                if let resumedRelated, let puzzle = resumedRelated.puzzleSnapshot {
                    ReviewPracticeView(finding: resumedRelated.sourceFinding, puzzle: puzzle, linkedTargetID: resumedRelated.targetID,
                                       resumeSessionResult: true, sessionID: sessionID, resumeRunID: resumedRelated.id)
                }
            }
    }
    private var recapView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Practice recap").font(ChessMeStyle.title(28))
                Text("\(Set(attempts.filter { $0.outcome == .completed }.map(\.targetID)).count) of \(items.count) core positions completed.")
                    .accessibilityIdentifier("practice.recapCount")
                Text("Optional puzzles are separate. Skipped and unassessed positions do not count as failures.").font(.caption)
                ForEach(attempts) { attempt in
                    NavigationLink { ReviewAttemptView(attemptID: attempt.id) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(items.first { $0.id == attempt.targetID }?.theme ?? "Game position")
                            Text(attempt.summary).font(.caption)
                        }
                    }
                }
                let optional = model.reviewState.attempts.filter {
                    $0.kind == .relatedPuzzle && $0.startedAt >= (record?.startedAt ?? .distantFuture) &&
                    (record?.targetIDs.contains($0.targetID) ?? false)
                }
                if !optional.isEmpty {
                    Text("Optional related attempts").font(ChessMeStyle.title(21))
                    ForEach(optional) { attempt in
                        NavigationLink { ReviewAttemptView(attemptID: attempt.id) } label: { Text(attempt.summary) }
                    }
                }
                ReviewRelatedList(moments: items.compactMap { item in
                    guard let game = model.library.games.first(where: { $0.id == item.gameID }) else { return nil }
                    return model.reviewJourney(for: game).moments.first { $0.id == item.id }
                }, sessionID: sessionID)
                if index < items.count, record?.finished != true {
                    Button("Resume this set") { recap = false; persistCursor(finished: false) }.frame(minHeight: 44)
                }
                if !model.reviewState.suggestedSet(excluding: Set(items.map(\.id))).isEmpty {
                    Button("Keep going with another short set") { keepGoing() }.frame(minHeight: 44)
                        .accessibilityIdentifier("practice.keepGoing")
                }
                PrimaryButton(title: originGameID == nil ? "Done" : "Return to review", symbol: "checkmark", action: onFinish)
                ReviewSaveNotice()
            }.padding(22)
        }.background(ChessMeStyle.paper).navigationTitle("Practice recap").navigationBarTitleDisplayMode(.inline)
    }
    private func initialize() {
        guard !started else { return }; started = true
        items = findings
        if let saved = model.reviewState.session, saved.canResume, saved.targetIDs == findings.map(\.id), saved.originGameID == originGameID {
            sessionID = saved.id; index = min(saved.index, items.count); recap = saved.surface == .recap || index >= items.count
            if recap, let active = saved.activeRelatedRunID {
                resumedRelated = model.reviewState.runs.first { $0.id == active && $0.puzzleSnapshot != nil }
            }
        } else {
            let saved = ReviewFollowUpSession(targetIDs: items.map(\.id), originGameID: originGameID, findings: items)
            sessionID = saved.id; model.changeReview { $0.session = saved }
        }
    }
    private func advance() {
        index += 1; recap = index >= items.count; persistCursor(finished: recap)
    }
    private func persistCursor(finished: Bool) {
        model.changeReview { state in
            guard state.session?.id == sessionID else { return }
            state.session?.index = index; state.session?.finished = finished
            state.session?.surface = recap ? .recap : .exercise
        }
    }
    private func keepGoing() {
        let excluded = Set((record?.targetIDs ?? []) + model.reviewState.attempts.filter {
            $0.startedAt > Date().addingTimeInterval(-3_600)
        }.map(\.targetID))
        let next = model.reviewState.suggestedSet(excluding: excluded).map(\.finding)
        guard !next.isEmpty else { return }
        items = next; index = 0; recap = false
        let saved = ReviewFollowUpSession(targetIDs: next.map(\.id), originGameID: originGameID, findings: next)
        sessionID = saved.id; model.changeReview { $0.session = saved }
    }
}
