import SwiftUI
import ChessMeCore

struct PuzzlesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var playingPuzzle: TrainingPuzzle?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                Text("Puzzles matched to the ideas in your games.")
                    .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                if model.isDemo {
                    Label("Demo · sample puzzle", systemImage: "eye")
                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                }
                if let puzzle = model.nextRecommendedPuzzle {
                    PrimaryButton(title: "Play next puzzle", symbol: "play.fill") { playingPuzzle = puzzle }
                        .accessibilityIdentifier("puzzles.play")
                }
                if !model.puzzleFocus.isEmpty {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your practice focus").font(.subheadline.weight(.semibold))
                            ForEach(Array(model.puzzleFocus.prefix(3)), id: \.theme) { item in
                                Text(PuzzleTheme.title(item.theme)).font(.subheadline).foregroundStyle(ChessMeStyle.green)
                            }
                            Text("Based on your reviews and practice.")
                                .font(.caption).foregroundStyle(ChessMeStyle.muted)
                        }
                    }
                }
                HStack {
                    Text("Level \(model.puzzleTargetRating)").font(.caption.monospacedDigit())
                    Spacer()
                    Button { Task { await model.refreshPuzzleMatches(force: true) } } label: {
                        Label("Refresh matches", systemImage: "arrow.clockwise")
                    }.font(.caption.weight(.semibold)).disabled(model.puzzlesLoading || model.isDemo)
                        .accessibilityIdentifier("puzzles.refresh")
                }
                if model.puzzlesLoading { ProgressView("Finding related puzzles…").font(.caption) }
                if !model.isDemo {
                    Text("\(model.puzzleMatchCoverage.checked)/\(model.puzzleMatchCoverage.total) reviewed games matched. Up to 3 puzzles per game.")
                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                }
                if let notice = model.puzzleNotice { Text(notice).font(.caption).foregroundStyle(ChessMeStyle.muted) }
                if model.recommendedPuzzles.isEmpty {
                    Text(model.library.games.isEmpty ? "Import completed games, then review them to get personal puzzle matches." : "Review your games to find teaching moments. Related puzzles appear here when matching completes.")
                        .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                    if model.library.games.isEmpty { PrimaryButton(title: "Import games", symbol: "arrow.down") { model.showConnection = true } }
                }
                ForEach(model.recommendedPuzzles) { puzzle in
                    PuzzleRow(puzzle: puzzle)
                    Divider()
                }
                Link("Puzzles from Lichess · CC0", destination: URL(string: "https://database.lichess.org/#puzzles")!)
                    .font(.caption).foregroundStyle(ChessMeStyle.muted)
            }.padding(24)
        }.background(ChessMeStyle.paper).navigationTitle("Related puzzles").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .accessibilityIdentifier("puzzles.scroll")
            .navigationDestination(isPresented: Binding(get: { playingPuzzle != nil }, set: { if !$0 { playingPuzzle = nil } })) {
                if let playingPuzzle { PuzzleLessonView(puzzle: playingPuzzle) }
            }
            .task { if model.automaticPuzzleMatching { await model.refreshPuzzleMatches() } }
    }
}

struct PuzzleRow: View {
    let puzzle: TrainingPuzzle
    @EnvironmentObject private var model: AppModel
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NavigationLink { PuzzleLessonView(puzzle: puzzle) } label: {
                HStack(alignment: .top, spacing: 14) {
                    ChessBoardView(position: (try? ChessPosition(fen: puzzle.positionFEN)) ?? .initial)
                        .frame(width: 68, height: 68).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Level \(puzzle.rating) · Lichess").font(.subheadline.weight(.semibold))
                        if model.isDemo { Text("Sample puzzle").font(.caption).foregroundStyle(ChessMeStyle.muted) }
                        if let related = model.recommendation(for: puzzle) {
                            Text("Related to \(related.game.label)").font(.caption).lineLimit(2)
                            Text(related.themes.map(PuzzleTheme.title).joined(separator: " · ")).font(.caption).foregroundStyle(ChessMeStyle.green)
                        }
                        if let record = model.library.practice.first(where: { $0.findingID == "lichess-puzzle-\(puzzle.id)" }) {
                            Text(record.dueAt <= Date() ? "Ready for a retry" : "Next review \(record.dueAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2).foregroundStyle(ChessMeStyle.muted)
                        }
                    }
                }.foregroundStyle(ChessMeStyle.ink)
            }.accessibilityIdentifier("puzzle.open.\(puzzle.id)")
            Spacer(minLength: 0)
            FavoriteButton(selected: model.isFavorite(puzzle)) { model.toggleFavorite(puzzle) }
        }
    }
}

struct PuzzleLessonView: View {
    let puzzle: TrainingPuzzle
    @EnvironmentObject private var model: AppModel
    @State private var current: TrainingPuzzle?
    var body: some View {
        let active = current ?? puzzle
        PuzzleExerciseView(puzzle: active, onNext: {
            let alternatives = model.recommendedPuzzles.filter { $0.id != active.id }
            current = alternatives.first(where: { item in
                !model.library.practice.contains(where: { $0.findingID == "lichess-puzzle-\(item.id)" && $0.dueAt > Date() })
            }) ?? alternatives.first
        }, hasNext: model.recommendedPuzzles.contains { $0.id != active.id }).id(active.id)
    }
}

private struct PuzzleExerciseView: View {
    let puzzle: TrainingPuzzle
    let onNext: () -> Void
    let hasNext: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .subheadline) private var statusHeight: CGFloat = 76
    @StateObject private var motion = TrainingBoardMotion()
    @StateObject private var analyzer = PositionAnalysisController()
    @State private var playthrough: PuzzlePlaythrough?
    @State private var selected: Int?
    @State private var promotions: [ChessMove] = []
    @State private var browsingPly: Int?
    @State private var feedback: String?
    @State private var assisted = false
    @State private var failed = false
    @State private var recorded = false
    @State private var showHint = false
    @State private var revealed = false
    @State private var error: String?
    @State private var hasPlayedIntro = false
    @State private var replying = false
    @State private var comparingMoves = false
    @State private var choicePosition: ChessPosition?
    @State private var suggestedMove: ChessMove?
    @State private var choiceEvaluation: PositionEvaluation?
    @State private var attemptTask: Task<Void, Never>?
    private var shownPosition: ChessPosition? {
        guard let playthrough else { return nil }
        if let browsingPly, playthrough.history.positions.indices.contains(browsingPly) { return playthrough.history.positions[browsingPly] }
        if comparingMoves, let choicePosition { return choicePosition }
        return motion.position ?? playthrough.position
    }
    private var targets: Set<Int> {
        guard browsingPly == nil, !motion.isAnimating, !comparingMoves, !replying, let board = shownPosition, let selected else { return [] }
        return Set(board.legalMoves().filter { $0.from == selected }.map(\.to))
    }
    private var choices: [PracticeMoveSuggestion] {
        guard let choicePosition else { return [] }
        if let choiceEvaluation {
            let moves = choiceEvaluation.goodMoves(in: choicePosition)
            if !moves.isEmpty { return moves }
        }
        return suggestedMove.map { [PracticeMoveSuggestion(move: $0, quality: .best)] } ?? []
    }
    private var boardChoices: [PracticeMoveSuggestion] {
        guard !motion.isAnimating, browsingPly == nil,
              comparingMoves || shownPosition == choicePosition || playthrough?.isComplete == true else { return [] }
        return choices
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Level \(puzzle.rating) · Lichess\(model.isDemo ? " · sample" : "")")
                        .font(.caption.weight(.semibold)).foregroundStyle(ChessMeStyle.muted)
                    Spacer()
                    FavoriteButton(selected: model.isFavorite(puzzle)) { model.toggleFavorite(puzzle) }
                }
                if let playthrough, let board = shownPosition {
                    Text("\(board.sideToMove.title) to move").font(.caption).foregroundStyle(ChessMeStyle.muted)
                    AnalysisBoardView(position: board, perspective: playthrough.positions[0].sideToMove, selectedSquare: selected,
                                      targets: targets, highlightedSquares: highlightedSquares,
                                      suggestions: boardChoices, rejectionCount: motion.rejectionCount,
                                      evaluation: choiceEvaluation, evaluationPosition: choicePosition,
                                      showArrows: false, revealEvaluation: playthrough.isComplete,
                                      onSquare: browsingPly == nil && !motion.isAnimating && !comparingMoves && !replying && !playthrough.isComplete ? choose : nil)
                    VStack(alignment: .leading, spacing: 5) {
                        if playthrough.isComplete {
                            Text(revealed ? "See the solution" : "You found the line").font(ChessMeStyle.title(22))
                        }
                        if let feedback {
                            Text(feedback).font(.subheadline)
                                .foregroundStyle(failed && !playthrough.isComplete ? ChessMeStyle.muted : ChessMeStyle.green)
                                .accessibilityIdentifier("puzzle.feedback")
                        } else {
                            Text("Choose a move on the board.").font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).frame(height: statusHeight, alignment: .leading)
                    if !playthrough.isComplete {
                        HStack {
                            Button { assisted = true; showHint = true; feedback = "The highlighted piece starts the next move." } label: { Label("Hint", systemImage: "lightbulb") }
                                .accessibilityIdentifier("puzzle.hint")
                            Spacer()
                            Button("Show solution") { reveal() }.accessibilityIdentifier("puzzle.reveal")
                        }.font(.subheadline.weight(.semibold)).disabled(browsingPly != nil || motion.isAnimating || replying)
                    }
                    if playthrough.isComplete, choicePosition != nil {
                        Text("Evaluation of the last puzzle decision").font(.caption2).foregroundStyle(ChessMeStyle.muted)
                    }
                    if !choices.isEmpty {
                        MoveChoiceLegend(suggestions: choices, comparing: $comparingMoves)
                            .disabled(motion.isAnimating || replying || browsingPly != nil)
                    }
                    MoveHistoryView(history: playthrough.history, selectedIndex: browsingPly ?? playthrough.history.moves.count, prefix: "puzzle", title: nil) { index in
                        guard !motion.isAnimating, !replying else { return }
                        selected = nil
                        comparingMoves = false
                        browsingPly = index == playthrough.history.moves.count ? nil : index
                    }
                    if browsingPly != nil {
                        Button("Return to puzzle") { browsingPly = nil }.accessibilityIdentifier("puzzle.return")
                    }
                    if !playthrough.isComplete {
                        Text("Play the whole line. The opponent's replies play automatically.").font(.caption).foregroundStyle(ChessMeStyle.muted)
                    } else {
                        DisclosureGroup("Explanation") {
                            Text(puzzle.themes.map(PuzzleTheme.title).joined(separator: " · ")).font(.subheadline).foregroundStyle(ChessMeStyle.green)
                            if let related = model.recommendation(for: puzzle) {
                                Text("This trains \(related.themes.map(PuzzleTheme.title).joined(separator: ", ")), an idea related to your game against \(related.game.playerSide == .white ? related.game.black : related.game.white).")
                                    .font(.subheadline)
                                NavigationLink { GameDetailView(game: related.game) } label: { Text("Return to the game") }
                            }
                        }.font(.subheadline.weight(.medium))
                    }
                }
                if let error { Text(error).font(.subheadline).foregroundStyle(ChessMeStyle.muted) }
                DisclosureGroup("Puzzle details") {
                    Text("Puzzle \(puzzle.id) · Level \(puzzle.rating) · Lichess · CC0")
                    Text(puzzle.themes.map(PuzzleTheme.title).joined(separator: " · "))
                    if !puzzle.openingTags.isEmpty { Text(puzzle.openingTags.joined(separator: " · ")) }
                    Text("Green highlights show estimated good moves from the previous decision. Follow the puzzle's full line to complete it.")
                    Link("View on Lichess", destination: puzzle.url)
                }.font(.caption).foregroundStyle(ChessMeStyle.muted).accessibilityIdentifier("puzzle.details")
            }.padding(22)
        }.background(ChessMeStyle.paper)
            .navigationTitle("Puzzle").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .accessibilityIdentifier("puzzle.scroll")
            .safeAreaInset(edge: .bottom) {
                if playthrough?.isComplete == true {
                    HStack {
                        if hasNext { PrimaryButton(title: "Next puzzle", symbol: "arrow.right", action: onNext).accessibilityIdentifier("puzzle.next") }
                        else { Text("All caught up").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity) }
                    }.padding(.horizontal, 22).padding(.vertical, 10).background(ChessMeStyle.paper)
                }
            }
            .task {
                if playthrough == nil {
                    do { playthrough = try PuzzlePlaythrough(puzzle: puzzle) } catch { self.error = error.localizedDescription }
                }
                if !hasPlayedIntro, let playthrough {
                    await motion.replay(playthrough.history.leadIn(plies: 1), reduceMotion: reduceMotion)
                    guard !Task.isCancelled else { return }
                    hasPlayedIntro = true
                }
                finishReply()
            }
            .onChange(of: comparingMoves) { _, _ in selected = nil }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { finishReply() }
                else { attemptTask?.cancel(); motion.stop(); replying = false }
            }
            .onDisappear { attemptTask?.cancel(); analyzer.stop(); motion.stop() }
            .confirmationDialog("Promote your pawn", isPresented: Binding(get: { !promotions.isEmpty }, set: { if !$0 { promotions = [] } })) {
                ForEach(promotions, id: \.uci) { move in Button(move.promotion?.rawValue.capitalized ?? "Queen") { play(move); promotions = [] } }
            }
    }
    private var highlightedSquares: Set<Int> {
        guard browsingPly == nil, !comparingMoves else { return [] }
        if let move = motion.lastMove { return [move.from, move.to] }
        if showHint, let playthrough, !playthrough.isComplete { return [playthrough.solution[playthrough.cursor].from] }
        if let move = playthrough?.moves.last ?? (try? ChessMove(uci: puzzle.setupMove)) { return [move.from, move.to] }
        return []
    }
    private func choose(_ square: Int) {
        guard let board = shownPosition else { return }
        if selected == square { selected = nil; return }
        let moves = board.legalMoves().filter { $0.from == selected && $0.to == square }
        if moves.count > 1 { promotions = moves; return }
        if let move = moves.first { play(move); return }
        selected = board.squares[square]?.side == board.sideToMove ? square : nil
    }
    private func play(_ move: ChessMove) {
        guard let board = playthrough?.position, let playthrough, !playthrough.isComplete else { return }
        attemptTask?.cancel(); motion.stop()
        comparingMoves = false
        choicePosition = board
        suggestedMove = playthrough.solution[playthrough.cursor]
        choiceEvaluation = nil
        selected = nil; showHint = false
        do {
            let accepted = try self.playthrough?.play(move, automaticallyReply: false) == true
            if !accepted {
                feedback = "Look for a stronger move. Try again."
                if !failed { model.recordPuzzle(puzzle, correct: false, assisted: false); failed = true; recorded = true }
            } else if self.playthrough?.isComplete == true {
                feedback = assisted || failed ? "Line complete. Try it unaided next time." : "Correct. You found the whole line."
                if !recorded { model.recordPuzzle(puzzle, correct: true, assisted: assisted); recorded = true }
            } else { feedback = "Correct. Find your next move." }
            replying = self.playthrough?.isAwaitingReply == true
            let configuration = model.effectiveEngineConfiguration
            attemptTask = Task {
                async let search = try? analyzer.evaluateAttempt(move: move, position: board, configuration: configuration)
                if !accepted { await motion.returnAttempt(move, in: board, rejected: true, reduceMotion: reduceMotion) }
                else if replying {
                    do { try await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 450)) } catch { return }
                    guard !Task.isCancelled else { return }
                    finishReply()
                }
                let result = await search
                guard !Task.isCancelled else { return }
                choiceEvaluation = result
            }
        } catch { self.error = error.localizedDescription }
    }
    private func finishReply() {
        do { try playthrough?.playReply() } catch { self.error = error.localizedDescription }
        replying = false
    }
    private func reveal() {
        attemptTask?.cancel(); motion.stop(); replying = false; comparingMoves = false
        assisted = true; revealed = true; browsingPly = nil; selected = nil
        do { try playthrough?.reveal() } catch { self.error = error.localizedDescription }
        if !recorded { model.recordPuzzle(puzzle, correct: false, assisted: true); recorded = true }
        feedback = "Replay the line, then return for an unaided attempt."
    }
}
