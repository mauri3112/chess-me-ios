import SwiftUI
import ChessMeCore

/// Pin an exercise to the library generation and storage mode in which it opened.
struct FundamentalsProgressContext: Hashable {
    let generation: UUID
    let isSample: Bool
    func acceptsCompletion(in current: Self) -> Bool { self == current }
}

/// Sample and UI-test sessions keep their curriculum progress in memory.
struct FundamentalsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(FundamentalsProgress.preferenceKey) private var completedIDs = ""
    @State private var sampleIDs: Set<String> = []
    private var isSample: Bool {
        model.isDemo || ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }
    private var solvedIDs: Set<String> {
        isSample ? sampleIDs : Set(completedIDs.split(separator: ",").map(String.init))
    }
    private var progressContext: FundamentalsProgressContext {
        FundamentalsProgressContext(generation: model.reviewGeneration, isSample: isSample)
    }
    var body: some View {
        let context = progressContext
        List {
            Section {
                if isSample {
                    Text("Sample progress · kept only for this visit").font(.caption).foregroundStyle(ChessMeStyle.muted)
                }
                Text("Six original exercises in checkmate and promotion. Each goal is checked with legal chess moves. Hints and revealed answers count as guided rehearsal.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(FundamentalsLesson.all) { lesson in
                NavigationLink {
                    FundamentalsTaskView(lesson: lesson) { id in
                        guard context.acceptsCompletion(in: progressContext) else { return }
                        if context.isSample { sampleIDs.insert(id) }
                        else {
                            var ids = solvedIDs
                            ids.insert(id); completedIDs = ids.sorted().joined(separator: ",")
                        }
                    }
                    .id(context)
                } label: {
                    HStack {
                        Text(lesson.title)
                        Spacer()
                        if solvedIDs.contains(lesson.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                .accessibilityLabel("Solved independently")
                                .accessibilityIdentifier("fundamentals.completed.\(lesson.id)")
                        }
                    }
                }.accessibilityIdentifier("fundamentals.lesson.\(lesson.id)")
            }
        }
        .accessibilityIdentifier("fundamentals.list")
        .scrollContentBackground(.hidden)
        .background(ChessMeStyle.paper)
        .tint(ChessMeStyle.green)
        .navigationTitle("Fundamentals")
        .toolbar(.visible, for: .navigationBar)
        .onChange(of: progressContext) { _, _ in sampleIDs.removeAll() }
    }
}

private struct FundamentalsTaskView: View {
    let lesson: FundamentalsLesson
    let onIndependentSolve: (String) -> Void
    @State private var attempt: FundamentalsAttempt
    @State private var started = false
    @State private var selected: Int?
    @State private var promotionMoves: [ChessMove] = []
    @Environment(\.dynamicTypeSize) private var typeSize
    init(lesson: FundamentalsLesson, onIndependentSolve: @escaping (String) -> Void) {
        self.lesson = lesson; self.onIndependentSolve = onIndependentSolve
        _attempt = State(initialValue: FundamentalsAttempt(lesson: lesson))
    }
    private var legalMoves: [ChessMove] { attempt.position.legalMoves() }
    private var actionLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(lesson.introduction).foregroundStyle(.secondary)
                Text(lesson.task).font(ChessMeStyle.title(22))
                if !started {
                    Button("Start exercise") { started = true }.buttonStyle(.borderedProminent).accessibilityIdentifier("fundamentals.start")
                } else {
                    Text(attempt.completed ? "Exercise complete" : "\(attempt.position.sideToMove.title) to move").font(.subheadline.bold())
                    ChessBoardView(position: attempt.position, perspective: lesson.position.sideToMove,
                                   selectedSquare: selected,
                                   targets: Set(legalMoves.filter { $0.from == selected }.map(\.to)),
                                   onSquare: tap)
                        .aspectRatio(1, contentMode: .fit)
                    Text(attempt.feedback).accessibilityIdentifier("fundamentals.feedback")
                    if !promotionMoves.isEmpty {
                        Text("Promote to").font(.headline)
                        actionLayout {
                            ForEach(promotionMoves, id: \.uci) { move in
                                Button(move.promotion!.rawValue.capitalized) { play(move) }
                                    .buttonStyle(.bordered)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("fundamentals.promote.\(move.promotion!.rawValue)")
                            }
                        }
                    }
                    actionLayout {
                        Button("Hint") { attempt.hint() }.disabled(attempt.completed).accessibilityIdentifier("fundamentals.hint")
                        Button("Reveal") { attempt.reveal() }.disabled(attempt.completed).accessibilityIdentifier("fundamentals.reveal")
                        if !typeSize.isAccessibilitySize { Spacer() }
                        Button("Retry") {
                            attempt = FundamentalsAttempt(lesson: lesson); selected = nil; promotionMoves = []
                        }.accessibilityIdentifier("fundamentals.retry")
                    }.buttonStyle(.bordered)
                }
            }.padding().frame(maxWidth: 600)
        }
        .background(ChessMeStyle.paper)
        .tint(ChessMeStyle.green)
        .navigationTitle(lesson.title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
    private func tap(_ square: Int) {
        guard !attempt.completed else { return }
        if let selected {
            let moves = legalMoves.filter { $0.from == selected && $0.to == square }
            if moves.count > 1 { promotionMoves = moves; return }
            if let move = moves.first { play(move); return }
            if attempt.position.squares[square]?.side != attempt.position.sideToMove {
                play(ChessMove(from: selected, to: square)); return
            }
        }
        selected = attempt.position.squares[square]?.side == attempt.position.sideToMove ? square : nil
        promotionMoves = []
    }
    private func play(_ move: ChessMove) {
        attempt.play(move); selected = nil; promotionMoves = []
        if attempt.completed && !attempt.guided { onIndependentSolve(lesson.id) }
    }
}
