import SwiftUI
import ChessMeCore

struct LessonSessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if model.sessionFinished {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Session complete").font(ChessMeStyle.title(30))
                        Text("\(model.sessionOutcomes.count) of \(model.session.count) positions attempted").font(.subheadline)
                        ForEach(model.session) { finding in
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(finding.theme).font(.subheadline.weight(.medium))
                                    Text(finding.gameLabel).font(.caption).foregroundStyle(ChessMeStyle.muted)
                                }
                                Spacer()
                                Text(model.sessionOutcomes[finding.id] ?? "Skipped").font(.caption.weight(.semibold))
                            }
                        }
                        PrimaryButton(title: "Finish session", symbol: "checkmark") { model.endSession() }
                            .accessibilityIdentifier("session.finish")
                    }.padding(24)
                }.background(ChessMeStyle.paper)
            } else if let finding = model.activeLesson {
                LessonView(finding: finding).id("\(finding.id)-\(model.sessionIndex)")
            }
        }
        .navigationTitle("Practice").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { model.endSession() } } }
    }
}

struct LessonView: View {
    let finding: MoveFinding
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.chessReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var statusHeight: CGFloat = 62
    @State private var guidance = false
    @StateObject private var analyzer = PositionAnalysisController()
    @StateObject private var motion = TrainingBoardMotion()
    @State private var position: ChessPosition
    @State private var selected: Int?
    @State private var feedback: String?
    @State private var showHint = false
    @State private var solved = false
    @State private var revealed = false
    @State private var recorded = false
    @State private var assistanceUsed = false
    @State private var viewingOriginal = false
    @State private var exploring = false
    @State private var continuing = false
    @State private var explorationStart: ChessPosition?
    @State private var explorationBase: MoveHistory?
    @State private var explorationStartMoves: [ChessMove] = []
    @State private var explorationStartLastMove: ChessMove?
    @State private var explorationHistory: [ChessPosition] = []
    @State private var activeLine: [ChessMove] = []
    @State private var promotionMoves: [ChessMove] = []
    @State private var lastMove: ChessMove?
    @State private var attemptedQuality: MoveQuality?
    @State private var attemptTask: Task<Void, Never>?
    @State private var checkingMove = false
    @State private var gameHistory: MoveHistory?
    @State private var lessonMoves: [ChessMove] = []
    @State private var explorationMoves: [ChessMove] = []
    @State private var browsingPly: Int?
    @State private var hasAttempted = false
    @State private var hasPlayedIntro = false
    @State private var comparingMoves = false
    @State private var evaluatingChoices = false
    @State private var decisionEvaluation: PositionEvaluation?
    @State private var successText = ""
    @State private var solvedMove: ChessMove?

    init(finding: MoveFinding) {
        self.finding = finding
        _position = State(initialValue: (try? ChessPosition(fen: finding.positionFEN)) ?? .initial)
    }

    private var initial: ChessPosition { (try? ChessPosition(fen: finding.positionFEN)) ?? .initial }
    private var targets: Set<Int> {
        guard let selected else { return [] }
        return Set(shownPosition.legalMoves().filter { $0.from == selected }.map(\.to))
    }
    private var history: MoveHistory {
        let base = (exploring ? explorationBase : gameHistory) ?? MoveHistory(position: initial)
        return (try? base.appending(exploring ? explorationMoves : lessonMoves)) ?? base
    }
    private var shownPosition: ChessPosition {
        if let browsingPly, history.positions.indices.contains(browsingPly) { return history.positions[browsingPly] }
        if comparingMoves { return initial }
        return motion.position ?? position
    }
    private var analysisVisible: Bool { !motion.isAnimating && !evaluatingChoices && (guidance || solved || exploring || browsingPly != nil) }
    private var reviewingDecision: Bool {
        !exploring && !viewingOriginal && browsingPly == nil &&
        (comparingMoves || position == initial || (solved && lessonMoves.count == 1))
    }
    private var analysisPosition: ChessPosition { reviewingDecision ? initial : shownPosition }
    private var currentEvaluation: PositionEvaluation? {
        if reviewingDecision, let decisionEvaluation { return decisionEvaluation }
        return analyzer.evaluation(for: analysisPosition)
    }
    private var nextLineMove: ChessMove? {
        let index = browsingPly ?? history.moves.count
        let base = gameHistory ?? MoveHistory(position: initial)
        guard index >= base.moves.count,
              Array(history.moves.prefix(base.moves.count)) == base.moves else { return nil }
        let played = Array(history.moves.prefix(index).dropFirst(base.moves.count))
        guard played == Array(activeLine.prefix(played.count)), activeLine.indices.contains(played.count),
              shownPosition.legalMoves().contains(activeLine[played.count]) else { return nil }
        return activeLine[played.count]
    }
    private var liveChoices: [PracticeMoveSuggestion] {
        guard exploring || browsingPly != nil, !motion.isAnimating else { return [] }
        let suggestions = analyzer.evaluation(for: shownPosition)?.goodMoves(in: shownPosition) ?? []
        if !suggestions.isEmpty { return suggestions }
        if let nextLineMove { return [PracticeMoveSuggestion(move: nextLineMove, quality: .best)] }
        return []
    }
    private var nextExplorationMove: ChessMove? { liveChoices.first?.move ?? nextLineMove }
    private var choices: [PracticeMoveSuggestion] {
        guard hasAttempted else { return [] }
        if let decisionEvaluation {
            let suggestions = decisionEvaluation.goodMoves(in: initial)
            if !suggestions.isEmpty { return suggestions }
        }
        return ([finding.bestMove] + finding.acceptedMoves.filter { $0 != finding.bestMove }).prefix(3).compactMap { uci in
            guard let move = try? ChessMove(uci: uci), initial.legalMoves().contains(move) else { return nil }
            return PracticeMoveSuggestion(move: move, quality: uci == finding.bestMove ? .best : .good)
        }
    }
    private var boardChoices: [PracticeMoveSuggestion] {
        if exploring || browsingPly != nil { return liveChoices }
        guard browsingPly == nil, !exploring, !viewingOriginal, !motion.isAnimating,
              comparingMoves || position == initial || (solved && lessonMoves.count == 1) else { return [] }
        return choices
    }
    private var marker: BoardMoveMarker? {
        guard !motion.isAnimating, !hasAttempted, browsingPly == nil, !exploring, (position == initial || viewingOriginal),
              let move = try? ChessMove(uci: finding.playedMove) else { return nil }
        return BoardMoveMarker(square: move.to, quality: finding.estimatedQuality)
    }
    private var shownMove: ChessMove? {
        if let browsingPly { return browsingPly > 0 ? history.moves[browsingPly - 1] : nil }
        if comparingMoves { return nil }
        return motion.lastMove ?? lastMove
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            MoveQualityBadge(quality: finding.estimatedQuality).accessibilityIdentifier("lesson.originalQuality")
                            Text("\(shownPosition.sideToMove.title) to move · \(shownPosition.fullmoveNumber)\(model.isDemo ? " · sample" : "")")
                                .font(.caption).foregroundStyle(ChessMeStyle.muted)
                        }
                    }
                    Spacer(minLength: 0)
                    FavoriteButton(selected: model.isFavorite(finding)) { model.toggleFavorite(finding) }
                }
                AnalysisBoardView(position: shownPosition, perspective: initial.sideToMove, selectedSquare: selected,
                                  targets: !motion.isAnimating && !comparingMoves ? targets : [], highlightedSquares: shownMove.map { [$0.from, $0.to] } ?? [],
                                  moveMarker: marker, suggestions: boardChoices, rejectionCount: motion.rejectionCount,
                                  successCount: motion.successCount, successSquare: motion.successSquare,
                                  evaluation: analysisVisible ? currentEvaluation : nil, evaluationPosition: analysisPosition,
                                  topMoves: model.effectiveEngineConfiguration.topMoves,
                                  fallbackMove: analysisVisible && position == initial ? finding.bestMove : nil,
                                  showArrows: false, revealEvaluation: analysisVisible,
                                  onSquare: !motion.isAnimating && !comparingMoves && (exploring || browsingPly != nil || (!solved && !viewingOriginal)) ? chooseSquare : nil)
                MoveHistoryView(history: history, selectedIndex: browsingPly ?? history.moves.count, prefix: "lesson", title: nil) { index in
                    guard !motion.isAnimating else { return }
                    selected = nil
                    comparingMoves = false
                    if index != history.moves.count { assistanceUsed = true }
                    browsingPly = index == history.moves.count ? nil : index
                }
                lessonStatus
                if !solved && !exploring && browsingPly == nil && !viewingOriginal {
                    HStack {
                        Button { showHint = true; assistanceUsed = true } label: { Label("Hint", systemImage: "lightbulb") }
                            .accessibilityIdentifier("lesson.hint")
                        Spacer()
                        Button("Show solution") { reveal() }.accessibilityIdentifier("lesson.reveal")
                    }.font(.subheadline.weight(.medium)).disabled(checkingMove || motion.isAnimating)
                }
                if solved && browsingPly == nil && !exploring && !viewingOriginal && position.outcome() == .ongoing {
                    PrimaryButton(title: "Play the continuation", symbol: "play.fill") { startContinuation() }
                        .accessibilityIdentifier("lesson.continuation")
                }
                if continuing || exploring || browsingPly != nil {
                    PrimaryButton(title: "Play best move", symbol: "forward.frame") {
                        if let move = nextExplorationMove { play(move, automated: true) }
                    }.disabled(nextExplorationMove == nil || motion.isAnimating)
                        .accessibilityIdentifier("lesson.playBestMove")
                }
                if hasAttempted && !choices.isEmpty && !exploring && browsingPly == nil {
                    MoveChoiceLegend(suggestions: choices, comparing: $comparingMoves)
                } else if exploring && !liveChoices.isEmpty {
                    MoveChoiceLegend(suggestions: liveChoices, comparing: $comparingMoves, allowsComparison: false)
                }
                if !exploring && browsingPly == nil {
                    HStack {
                        if !solved {
                            Button { guidance.toggle() } label: {
                                Text(guidance ? "Hide analysis" : "Analyze position").frame(minHeight: 44)
                            }.accessibilityIdentifier("lesson.guidance")
                        }
                        Spacer()
                        Button("Explore moves") { enterExploration() }.frame(minHeight: 44)
                            .accessibilityIdentifier("lesson.explore")
                    }.font(.caption.weight(.semibold)).disabled(checkingMove || motion.isAnimating)
                }
                if analysisVisible {
                    if reviewingDecision {
                        Text("Evaluation of the lesson position").font(.caption2).foregroundStyle(ChessMeStyle.muted)
                    }
                    AnalysisPanel(position: analysisPosition, controller: analyzer, configuration: model.effectiveEngineConfiguration,
                                  referenceEvaluation: reviewingDecision ? decisionEvaluation : nil)
                }
                if exploring {
                    HStack {
                        Button("Undo move") {
                            if let previous = explorationHistory.popLast() {
                                position = previous; selected = nil; browsingPly = nil; explorationMoves.removeLast()
                                lastMove = explorationMoves.last ?? explorationStartLastMove
                            }
                        }.disabled(explorationHistory.isEmpty).accessibilityIdentifier("lesson.undo")
                        Spacer()
                        Button("Reset position") {
                            position = explorationStart ?? initial; explorationHistory = []; explorationMoves = explorationStartMoves
                            lastMove = explorationStartLastMove; selected = nil; browsingPly = nil
                        }.accessibilityIdentifier("lesson.reset")
                    }.font(.subheadline.weight(.medium))
                } else {
                    if let attemptedQuality { MoveQualityBadge(quality: attemptedQuality) }
                    if showHint && !solved { Label(finding.hint, systemImage: "lightbulb").font(.subheadline).foregroundStyle(ChessMeStyle.green) }
                    if solved {
                        DisclosureGroup("Explanation") {
                            Text(finding.explanation).font(.subheadline).foregroundStyle(ChessMeStyle.ink).lineSpacing(3)
                        }.font(.subheadline.weight(.medium)).accessibilityIdentifier("lesson.explanation")
                        Button(viewingOriginal ? "Show improvement" : "See your original move") { compareOriginal() }
                            .font(.subheadline.weight(.medium))
                    }
                }
                DisclosureGroup("Lesson details") {
                    Text("From \(finding.gameLabel). \(finding.source == "cloud" ? "Cloud" : "Device") review.")
                    Text("Move labels are estimates. Guided solves return sooner for an unaided retry.")
                }.font(.caption).foregroundStyle(ChessMeStyle.muted)
            }.padding(22)
        }
        .background(ChessMeStyle.paper)
        .accessibilityIdentifier("lesson.scroll")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { model.previousSessionPosition() } label: { Label("Previous", systemImage: "chevron.left") }
                    .disabled(model.sessionIndex == 0).accessibilityIdentifier("session.previous")
                Spacer()
                Text("\(model.sessionIndex + 1)/\(model.session.count)").font(.caption.monospacedDigit()).foregroundStyle(ChessMeStyle.muted)
                    .accessibilityIdentifier("session.position")
                Spacer()
                Button { model.advanceSession() } label: {
                    Label(model.sessionIndex + 1 < model.session.count ? "Next position" : "Finish session", systemImage: "chevron.right")
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .foregroundStyle(solved ? .white : ChessMeStyle.green)
                        .background(solved ? ChessMeStyle.green : .clear, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityIdentifier("session.next")
                    .accessibilityValue(solved ? "Ready to continue" : "")
                    .animation(.easeInOut(duration: 0.2), value: solved)
            }
            .font(.subheadline.weight(.semibold)).padding(.horizontal, 22).padding(.vertical, 8)
            .background(ChessMeStyle.paper).overlay(alignment: .top) { Divider() }
        }
        .onAppear {
            assistanceUsed = false
            recorded = model.sessionOutcomes[finding.id] != nil
            activeLine = finding.continuation.compactMap { try? ChessMove(uci: $0) }
            gameHistory = try? MoveHistory(game: model.library.games.first { $0.id == finding.gameID }, finding: finding)
            updateAnalysis()
        }
        .task {
            guard !hasPlayedIntro else { return }
            let leadIn = (try? MoveHistory(game: model.library.games.first { $0.id == finding.gameID }, finding: finding))?.leadIn()
            if let leadIn { await motion.replay(leadIn, reduceMotion: reduceMotion) }
            guard !Task.isCancelled else { return }
            hasPlayedIntro = true
            lastMove = leadIn?.moves.last
            updateAnalysis()
        }
        .onChange(of: position) { _, _ in updateAnalysis() }
        .onChange(of: browsingPly) { _, _ in updateAnalysis() }
        .onChange(of: model.engineConfiguration) { _, _ in decisionEvaluation = nil; updateAnalysis() }
        .onChange(of: guidance) { _, enabled in if enabled { assistanceUsed = true }; updateAnalysis() }
        .onChange(of: comparingMoves) { _, _ in selected = nil; updateAnalysis() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { updateAnalysis() }
            else { analyzer.stop(); attemptTask?.cancel(); motion.stop(); checkingMove = false; evaluatingChoices = false }
        }
        .onDisappear { analyzer.stop(); attemptTask?.cancel(); motion.stop(); evaluatingChoices = false; checkingMove = false }
        .confirmationDialog("Promote your pawn", isPresented: Binding(get: { !promotionMoves.isEmpty }, set: { if !$0 { promotionMoves = [] } })) {
            ForEach(promotionMoves, id: \.uci) { move in Button(move.promotion?.rawValue.capitalized ?? "Queen") { play(move); promotionMoves = [] } }
        }
    }

    private var lessonStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            if exploring || browsingPly != nil {
                Text(continuing ? "Play the continuation yourself." : "Try any legal move.").fontWeight(.semibold)
                Text("Best moves are dark green. Other good moves are lighter.").font(.caption).foregroundStyle(ChessMeStyle.muted)
            } else if solved {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                    Text(revealed ? "See the idea." : successText).accessibilityIdentifier("lesson.success")
                }.font(.subheadline.weight(.semibold)).foregroundStyle(ChessMeStyle.green)
                if let feedback {
                    Text(feedback).font(.caption).foregroundStyle(ChessMeStyle.muted).accessibilityIdentifier("lesson.feedback")
                }
            } else if checkingMove {
                ProgressView("Checking move…")
            } else if motion.isAnimating && !hasPlayedIntro {
                Text("Replaying the previous moves…").foregroundStyle(ChessMeStyle.muted)
            } else if let feedback {
                Text(feedback).foregroundStyle(ChessMeStyle.muted).accessibilityIdentifier("lesson.feedback")
            } else {
                Text("Choose a move on the board.").foregroundStyle(ChessMeStyle.muted)
            }
        }
        .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: statusHeight, alignment: .leading)
    }

    private func updateAnalysis() {
        guard analysisVisible, !evaluatingChoices else { analyzer.stop(); return }
        if reviewingDecision && decisionEvaluation != nil { analyzer.stop(); return }
        let past = Array(history.positions.prefix(browsingPly ?? history.moves.count)).map(\.repetitionKey)
        analyzer.start(position: analysisPosition, history: reviewingDecision ? Array((gameHistory?.positions ?? []).dropLast()).map(\.repetitionKey) : past,
                       configuration: model.effectiveEngineConfiguration)
    }
    private func chooseSquare(_ square: Int) {
        if selected == square { selected = nil; return }
        if let selected {
            let moves = shownPosition.legalMoves().filter { $0.from == selected && $0.to == square }
            if moves.count > 1 { promotionMoves = moves; return }
            if let move = moves.first { play(move); return }
        }
        selected = shownPosition.squares[square]?.side == shownPosition.sideToMove ? square : nil
    }
    private func play(_ move: ChessMove, automated: Bool = false) {
        if automated { assistanceUsed = true }
        if browsingPly != nil { enterExploration() }
        attemptTask?.cancel()
        motion.stop()
        evaluatingChoices = false
        checkingMove = false
        selected = nil
        guard let next = try? position.applying(move) else { return }
        if exploring {
            let before = position
            if !solved, before == initial, finding.acceptedMoves.contains(move.uci) || move.uci == finding.bestMove {
                hasAttempted = true
                finishAttempt(move, next: next, assessment: nil, celebrate: !automated)
            }
            explorationHistory.append(before); explorationMoves.append(move); position = next; lastMove = move
            return
        }
        hasAttempted = true
        decisionEvaluation = nil
        comparingMoves = false
        feedback = nil
        let board = position
        let configuration = model.effectiveEngineConfiguration
        let accepted = finding.acceptedMoves.contains(move.uci) || finding.bestMove == move.uci
        let knownMistake = move.uci == finding.playedMove && !accepted
        checkingMove = !accepted && !knownMistake
        evaluatingChoices = true
        analyzer.stop()
        if accepted { finishAttempt(move, next: next, assessment: nil) }
        else if knownMistake { finishAttempt(move, next: next, assessment: nil, shake: false) }
        attemptTask = Task {
            async let search = try? analyzer.evaluateAttempt(move: move, position: board, configuration: configuration)
            if !accepted { await motion.returnAttempt(move, in: board, rejected: knownMistake, reduceMotion: reduceMotion) }
            let result = await search
            guard !Task.isCancelled else { return }
            checkingMove = false
            evaluatingChoices = false
            decisionEvaluation = result
            if !accepted && !knownMistake {
                finishAttempt(move, next: next, assessment: result?.assessment(position: board, played: move, ply: 0))
            }
            if solved && move.uci != finding.bestMove, let candidate = result?.moves.first(where: { $0.move == move }) {
                activeLine = candidate.continuation
            }
            updateAnalysis()
        }
    }
    private func finishAttempt(_ move: ChessMove, next: ChessPosition, assessment: MoveAssessment?, shake: Bool = true, celebrate: Bool = true) {
        attemptedQuality = assessment?.quality
        let comparable = (assessment?.centipawnLoss ?? Int.max) <= 35 && (assessment?.completedDepth ?? 0) >= 2
        guard finding.acceptedMoves.contains(move.uci) || finding.bestMove == move.uci || comparable else {
            attemptedQuality = assessment?.quality ?? (move.uci == finding.playedMove ? finding.estimatedQuality : .unclassified)
            feedback = "Look for a stronger move. Try again."
            if shake { motion.shake() }
            if !recorded { model.recordPractice(finding, correct: false); recorded = true }
            return
        }
        if let candidate = decisionEvaluation?.moves.first(where: { $0.move == move }) { activeLine = candidate.continuation }
        position = next
        lastMove = move
        lessonMoves = [move]
        solved = true
        solvedMove = move
        successText = PracticeFeedback.success()
        if celebrate { motion.celebrate(at: move.to) }
        attemptedQuality = assessment?.quality ?? (move.uci == finding.bestMove ? .best : .excellent)
        feedback = nil
        if !recorded { model.recordPractice(finding, correct: true, assisted: assistanceUsed || showHint); recorded = true }
    }
    private func reveal() {
        attemptTask?.cancel(); motion.stop(); evaluatingChoices = false; checkingMove = false
        hasAttempted = true
        comparingMoves = false
        solved = true
        revealed = true
        selected = nil
        if let move = try? ChessMove(uci: finding.bestMove), let next = try? initial.applying(move) { solvedMove = move; position = next; lastMove = move; lessonMoves = [move] }
        if !recorded { model.recordPractice(finding, correct: false); recorded = true }
        feedback = "The suggested move is \((try? initial.san(ChessMove(uci: finding.bestMove))) ?? finding.bestMove)."
    }
    private func startContinuation() { enterExploration() }

    private func enterExploration() {
        let selectedHistory = history
        let index = browsingPly ?? selectedHistory.moves.count
        attemptTask?.cancel(); evaluatingChoices = false; checkingMove = false
        motion.stop(); analyzer.stop()
        assistanceUsed = true
        comparingMoves = false; viewingOriginal = false
        exploring = true; continuing = true; selected = nil
        explorationBase = selectedHistory.prefix(through: index)
        position = explorationBase?.positions.last ?? initial
        explorationStart = position; explorationStartMoves = []
        explorationStartLastMove = index > 0 ? selectedHistory.moves[index - 1] : nil
        explorationHistory = []; explorationMoves = []; lastMove = explorationStartLastMove
        browsingPly = nil
        updateAnalysis()
    }
    private func compareOriginal() {
        comparingMoves = false
        viewingOriginal.toggle()
        let uci = viewingOriginal ? finding.playedMove : (solvedMove?.uci ?? finding.bestMove)
        if let move = try? ChessMove(uci: uci), let next = try? initial.applying(move) { position = next; lastMove = move; lessonMoves = [move] }
    }
}
