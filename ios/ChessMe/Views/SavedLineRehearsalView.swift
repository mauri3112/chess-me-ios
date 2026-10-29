import SwiftUI
import ChessMeCore

/// Transient recall state is valid only while its saved source remains in the current library.
struct SavedLineRehearsalSession {
    struct ReplyToken: Equatable {
        let generation: UUID
        let index: Int
    }
    private(set) var source: SavedReviewLine?
    private(set) var context: UUID?
    private(set) var generation = UUID()
    private(set) var run: SavedLineRehearsal?
    var selected: Int?
    var promotions: [ChessMove] = []
    private(set) var feedback = "Recall your moves from this saved variation."

    func matches(line: SavedReviewLine?, context: UUID) -> Bool {
        line != nil && source == line && self.context == context
    }
    mutating func synchronize(line: SavedReviewLine?, context: UUID) {
        guard source != line || self.context != context else { return }
        generation = UUID(); source = line; self.context = context
        run = line.flatMap { try? SavedLineRehearsal(line: $0) }
        selected = nil; promotions = []
        feedback = "Recall your moves from this saved variation."
    }
    mutating func leave() { generation = UUID(); selected = nil; promotions = [] }
    mutating func restart() {
        generation = UUID(); run?.restart(); selected = nil; promotions = []
        feedback = "Recall your moves from this saved variation."
    }
    mutating func hint() { run?.hint(); feedback = "The highlighted piece moves next." }
    mutating func reveal() {
        if let move = run?.reveal() {
            selected = nil; promotions = []
            feedback = "Shown: \(move.uci). Continue recalling the saved line."
        }
    }
    mutating func submit(_ move: ChessMove) {
        let result = run?.submit(move); selected = nil; promotions = []
        switch result {
        case .accepted: feedback = "Saved move recalled. Continue the line."
        case .wrongMove: feedback = "That move is legal, but is not the saved move. Try again."
        case .illegalMove: feedback = "That move is not legal here. Try again."
        default: break
        }
    }
    var replyToken: ReplyToken? {
        guard let run, run.awaitingReply else { return nil }
        return ReplyToken(generation: generation, index: run.index)
    }
    @discardableResult
    mutating func playReply(_ token: ReplyToken, line: SavedReviewLine?, context: UUID) -> Bool {
        guard matches(line: line, context: context), replyToken == token else { return false }
        selected = nil
        return run?.playReply() == true
    }
}

struct SavedLineRehearsalView: View {
    let lineID: String
    @EnvironmentObject private var model: AppModel
    @State private var session = SavedLineRehearsalSession()
    @State private var isVisible = false
    @Environment(\.scenePhase) private var scenePhase
    private var line: SavedReviewLine? { model.reviewState.savedLines.first { $0.id == lineID } }
    private var currentSource: Bool { session.matches(line: line, context: model.reviewGeneration) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let line, currentSource, let run = session.run {
                    Text(line.title).font(ChessMeStyle.title(26))
                    Text("Rehearse as \(line.playerSide.title)").font(.headline)
                    Text("This is your chosen saved line. Its moves are not verified best moves or engine recommendations.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(run.completedPlayerMoves) of \(run.totalPlayerMoves) moves recalled")
                        .font(.subheadline.monospacedDigit()).accessibilityIdentifier("rehearsal.progress")
                    ChessBoardView(position: run.position, perspective: run.playerSide, selectedSquare: session.selected,
                                   targets: targets(run), highlightedSquares: Set(run.hintSquare.map { [$0] } ?? []),
                                   playsMoveSounds: true, onSquare: tap)
                        .aspectRatio(1, contentMode: .fit).accessibilityIdentifier("rehearsal.board")
                    if run.isComplete {
                        Text(run.cleanCompletion ? "Completed without help or retries" : "Completed with help or retries")
                            .font(.headline).accessibilityIdentifier("rehearsal.result")
                        Text("This run records recall of a saved line only. It does not measure chess strength or count toward scheduled review results.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(run.awaitingReply ? "Showing the other side's saved reply…" : session.feedback)
                            .accessibilityIdentifier("rehearsal.feedback")
                        if run.assisted { Text("This run includes help or retries.").font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Button("Hint") { if currentSource { session.hint() } }
                                .accessibilityIdentifier("rehearsal.hint")
                            Button("Show saved move") { if currentSource { session.reveal() } }
                                .accessibilityIdentifier("rehearsal.reveal")
                        }.buttonStyle(.bordered).disabled(!run.isPlayerTurn)
                    }
                    Button("Restart rehearsal") { if currentSource { session.restart() } }
                        .accessibilityIdentifier("rehearsal.restart")
                } else {
                    ContentUnavailableView("Cannot rehearse this line", systemImage: "arrow.triangle.branch",
                                           description: Text("The saved moves are missing, invalid, or do not match the stored position."))
                        .accessibilityIdentifier("rehearsal.unavailable")
                }
            }.padding(22)
        }
        .background(ChessMeStyle.paper).navigationTitle("Rehearse saved line").navigationBarTitleDisplayMode(.inline)
        .onAppear { isVisible = true; synchronize() }
        .onChange(of: line) { _, _ in synchronize() }
        .onChange(of: model.reviewGeneration) { _, _ in synchronize() }
        .onDisappear { isVisible = false; session.leave() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.leave() }
        }
        .task(id: replyTaskID) {
            guard isVisible, scenePhase == .active, currentSource, let token = session.replyToken else { return }
            do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
            guard !Task.isCancelled, isVisible, scenePhase == .active else { return }
            session.playReply(token, line: line, context: model.reviewGeneration)
        }
        .confirmationDialog("Choose promotion", isPresented: Binding(
            get: { currentSource && !session.promotions.isEmpty },
            set: { if !$0 { session.promotions = [] } }
        ), titleVisibility: .visible) {
            ForEach(session.promotions, id: \.uci) { move in
                let generation = session.generation
                Button(move.promotion?.rawValue.capitalized ?? "Promote") {
                    guard generation == session.generation else { return }
                    submit(move)
                }
            }
            Button("Cancel", role: .cancel) { session.promotions = [] }
        }
    }
    private var replyTaskID: String {
        "\(session.generation)-\(session.run?.index ?? -1)-\(model.reviewGeneration)-\(scenePhase)-\(isVisible)-\(currentSource)"
    }
    private func synchronize() { session.synchronize(line: line, context: model.reviewGeneration) }
    private func targets(_ run: SavedLineRehearsal) -> Set<Int> {
        guard currentSource, run.isPlayerTurn, let selected = session.selected else { return [] }
        return Set(run.position.legalMoves().filter { $0.from == selected }.map(\.to))
    }
    private func tap(_ square: Int) {
        guard currentSource, let run = session.run, run.isPlayerTurn else { return }
        if let selected = session.selected {
            let candidates = run.position.legalMoves().filter { $0.from == selected && $0.to == square }
            if candidates.count > 1 { session.promotions = candidates; return }
            if let move = candidates.first { submit(move); return }
            if run.position.squares[square]?.side != run.playerSide {
                submit(ChessMove(from: selected, to: square)); return
            }
        }
        session.selected = run.position.squares[square]?.side == run.playerSide ? square : nil
    }
    private func submit(_ move: ChessMove) {
        guard currentSource else { return }
        session.submit(move)
    }
}
