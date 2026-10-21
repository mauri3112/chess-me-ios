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
    @StateObject private var analyzer = PositionAnalysisController()
    @State private var run: AdaptiveReviewRun?
    @State private var generation: UUID?
    @State private var selected: Int?
    @State private var promotions: [ChessMove] = []
    @State private var checking = false
    @State private var error: String?
    @State private var pendingMove: ChessMove?
    @State private var work: Task<Void, Never>?
    @State private var ticket = UUID()
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
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(puzzle == nil ? "From your game" : "Separate catalogue position").font(.caption.weight(.semibold))
                        .foregroundStyle(ChessMeStyle.muted)
                    Spacer()
                    if let puzzle { FavoriteButton(selected: model.isFavorite(puzzle)) { model.toggleFavorite(puzzle) } }
                    else { FavoriteButton(selected: model.isFavorite(finding)) { model.toggleFavorite(finding) } }
                }
                if model.isDemo { Text("Sample practice · kept separate from your library").font(.caption) }
                if let run {
                    if run.attempt.knownSeenBefore {
                        Text(puzzle == nil ? "Previously reviewed position" : "Previously seen puzzle").font(.caption)
                    }
                    if run.attempt.topicCued {
                        Text(puzzle == nil ? "The stated goal provides a topic cue." : "The related-position invitation gives a topic cue.").font(.caption)
                    }
                    Text(run.isFinished ? run.attempt.summary : run.goal.prompt)
                        .font(ChessMeStyle.title(26)).accessibilityIdentifier("practice.prompt")
                    Text(run.requiresMate ? "Complete the mating continuation." : run.acceptedDecisions <= run.requiredDecisions ?
                         "\(run.acceptedDecisions) of \(run.requiredDecisions) key decisions accepted." :
                         "\(run.acceptedDecisions) decisions accepted; the stated goal still needs verification.")
                        .font(.subheadline).accessibilityIdentifier("practice.decisions")
                    ChessBoardView(position: run.position, perspective: run.solver, selectedSquare: selected,
                                   targets: legalTargets(run), onSquare: run.isFinished || checking || run.pendingReply != nil ? nil : choose)
                        .accessibilityIdentifier("practice.board")
                    if checking { ProgressView("Checking your move…").accessibilityIdentifier("practice.checking") }
                    else if run.pendingReply != nil { ProgressView("Opponent's reply…") }
                    if let feedback = run.feedback {
                        Text(feedback).font(.subheadline).accessibilityIdentifier("practice.feedback")
                    }
                    if let error {
                        Text(error).font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                        if let pendingMove, !run.isFinished { Button("Retry analysis") { check(pendingMove) } }
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
            .task { prepare() }
            .task(id: run?.pendingReply) {
                guard run?.pendingReply != nil else { return }
                // The persisted reply is the transition token. Restarting the view
                // consumes that token once instead of generating another reply.
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, generation == model.reviewGeneration else { return }
                mutate { $0.playReply() }
            }
            .onDisappear { ticket = UUID(); work?.cancel(); checking = false }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { ticket = UUID(); work?.cancel(); checking = false }
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
                ticket = UUID(); work?.cancel(); run = nil; checking = false
                error = "The local context changed. Return to your games or start a retained lesson again."
            }
            .onChange(of: sourceStatus) { _, _ in
                guard let run, run.attempt.kind == .game,
                      let target = model.reviewState.targets.first(where: { $0.id == run.targetID }),
                      target.invalidated || target.revision != run.revision else { return }
                ticket = UUID(); work?.cancel(); self.run = nil; checking = false
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
                Button("Show why") { mutate { $0.requestHelp(.counterline) }; showingWhy = true }
                    .accessibilityIdentifier("practice.showWhy")
                Spacer()
                Button("Try again") {
                    selected = nil; showingHint = false
                    mutate { $0.feedback = nil; $0.counterline = [] }
                }.accessibilityIdentifier("practice.tryAgain")
            }.frame(minHeight: 44)
        }
        if showingHint { Text(hint(for: run)).font(.subheadline).accessibilityIdentifier("practice.hintText") }
        HStack {
            Button(run.hintLevel == 0 ? "Hint" : "More help") {
                mutate { $0.requestHelp(.hint) }; showingHint = true
            }.accessibilityIdentifier("practice.hint")
            Spacer()
            Button("Show solution") {
                solutionFEN = run.currentFEN; solution = answerLine(for: run)
                mutate { $0.reviewAnswer() }
            }.accessibilityIdentifier("practice.reveal")
        }.frame(minHeight: 44).disabled(checking || run.pendingReply != nil)
        Button("Skip and continue") { mutate { $0.skip() }; finish() }.frame(minHeight: 44)
            .accessibilityIdentifier("practice.skip")
        if let game = model.library.games.first(where: { $0.id == finding.gameID }) {
            NavigationLink {
                GameReplayExplorer(game: game, initialPly: max(0, (finding.moveNumber - 1) * 2 + (game.playerSide == .black ? 1 : 0)))
            } label: { Text("Explore this game") }
                .simultaneousGesture(TapGesture().onEnded { mutate { $0.requestHelp(.line) } })
        }
    }

    @ViewBuilder private func result(_ run: AdaptiveReviewRun) -> some View {
        Text("Completion records this attempt. Later recall and new-position results have their own evidence.")
            .font(.caption).foregroundStyle(ChessMeStyle.muted)
        if run.attempt.outcome == .ungraded {
            Button("Try another continuation") {
                self.run = nil; generation = nil; error = nil
                prepare(forceNewAttempt: true)
            }.frame(minHeight: 44)
        }
        if run.attempt.outcome == .revealed {
            ReviewLineView(fen: solutionFEN ?? run.currentFEN,
                           moves: solution.isEmpty ? answerLine(for: run) : solution, perspective: run.solver,
                           label: "Requested solution · illustrative continuation")
        }
        if let connectionText { Text(connectionText).font(.subheadline) }
        if puzzle == nil, let connection = run.relatedOffer {
            PaperCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Try this idea in another position?").font(ChessMeStyle.title(21))
                    Text("Practise this lesson's idea in a different position.").font(.subheadline)
                    Text("Optional · Lichess catalogue · estimated \(connection.puzzle.rating)").font(.caption)
                    if model.hasSeenReviewPuzzle(connection.puzzle) { Text("Previously seen puzzle").font(.caption) }
                    NavigationLink {
                        ReviewPracticeView(finding: connection.puzzle.reviewFinding, puzzle: connection.puzzle,
                                           linkedTargetID: run.targetID, connectionText: connection.explanation,
                                           sessionID: sessionID, returnGameID: returnGameID, parentRunID: sessionID == nil ? run.id : nil)
                    } label: { Text("Try related puzzle") }.accessibilityIdentifier("practice.related")
                }
            }
        }
        if let puzzle {
            Link("Puzzle \(puzzle.id) · Lichess · CC0", destination: puzzle.url).font(.caption)
            let snapshot = ChessGame(id: "pgn-catalogue-" + puzzle.id, username: "Puzzle", white: "Catalogue position",
                black: "Lichess puzzle " + puzzle.id, playedAt: run.attempt.startedAt, playerSide: run.solver,
                moves: ([puzzle.setupMove] + run.acceptedMoves).joined(separator: " "), initialFEN: puzzle.setupFEN, status: "resign")
            NavigationLink {
                GameReplayExplorer(game: snapshot, initialPly: 1 + run.acceptedMoves.count, useStoredSnapshot: true, snapshotID: run.id)
            } label: { Text("Explore this catalogue position") }.accessibilityIdentifier("practice.explorePuzzle")
        }
        PrimaryButton(title: "Continue", symbol: "arrow.right", action: finish).accessibilityIdentifier("practice.continue")
        NavigationLink { ReviewAttemptView(attemptID: run.attempt.id) } label: { Text("View attempt details") }
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
        if (try? board.applying(move).outcome()) == .checkmate(winner: run.solver) {
            selected = nil
            mutate { $0.submit(move, evaluation: PositionEvaluation(moves: [], completedDepth: 0, nodes: 0)) }
            return
        }
        let nextTicket = UUID(); ticket = nextTicket; pendingMove = move; selected = nil
        checking = true; error = nil; showingHint = false
        work?.cancel()
        work = Task {
            do {
                let evaluation = try await analyzer.evaluateAttempt(move: move, position: board, history: history,
                                                                    configuration: model.effectiveEngineConfiguration)
                guard !Task.isCancelled, ticket == nextTicket, generation == model.reviewGeneration,
                      self.run?.id == id, self.run?.revision == revision, self.run?.currentFEN == board.fen else { return }
                checking = false
                mutate { $0.submit(move, evaluation: evaluation) }
            } catch {
                guard !Task.isCancelled, ticket == nextTicket, generation == model.reviewGeneration else { return }
                checking = false
                self.error = "Your move is unassessed: \(error.localizedDescription)"
                mutate {
                    $0.attempt.decisions.append(ReviewDecision(positionFEN: board.fen, move: move.uci, grade: .ungraded))
                }
            }
        }
    }
    private func mutate(_ change: (inout AdaptiveReviewRun) -> Void) {
        guard var value = run, let generation, generation == model.reviewGeneration else { return }
        if value.attempt.kind == .game, let target = model.reviewState.targets.first(where: { $0.id == value.targetID }),
           target.invalidated || target.revision != value.revision { return }
        change(&value); run = value
        _ = model.saveReviewRun(value, generation: generation)
    }
    private func answerLine(for run: AdaptiveReviewRun) -> [String] {
        run.acceptedMoves.isEmpty ? finding.continuation : run.remainingLine
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
