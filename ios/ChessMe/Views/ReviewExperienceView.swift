import SwiftUI
import ChessMeCore

private struct ReviewPracticeEntry: Identifiable {
    let id = UUID()
    let findings: [MoveFinding]
}

struct ReviewLineView: View {
    let fen: String
    let moves: [String]
    var perspective: Side = .white
    var label = ""
    var cachedProof: ReviewLineProof? = nil
    var initialCursor = 0
    @StateObject private var playback = ReviewLinePlayback()
    @Environment(\.chessReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var proof: ReviewLineProof? {
        guard let proof = playback.proof, proof.rootFEN == fen, proof.moves == moves else { return nil }
        return proof
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !label.isEmpty { Text(label).font(.caption).foregroundStyle(ChessMeStyle.muted) }
            if let root = try? ChessPosition(fen: fen) {
                let index = min(playback.cursor, proof?.moves.count ?? 0)
                let previous = index > 0 ? proof.flatMap { try? ChessMove(uci: $0.moves[index - 1]) } : nil
                ChessBoardView(position: proof?.positions[index] ?? root, perspective: perspective,
                               highlightedSquares: previous.map { [$0.from, $0.to] } ?? [], playsMoveSounds: true)
                    .accessibilityIdentifier("review.line.board")
                HStack(spacing: 6) {
                    BoardIconButton(title: "Restart line", symbol: "backward.end.fill") { playback.seek(0) }
                        .disabled(index == 0).accessibilityIdentifier("review.line.first")
                    BoardIconButton(title: "Previous position", symbol: "chevron.left") { playback.seek(index - 1) }
                        .disabled(index == 0).accessibilityIdentifier("review.line.previous")
                    Spacer(minLength: 0)
                    BoardIconButton(title: playback.isPlaying ? "Pause line" : "Play line",
                                    symbol: playback.isPlaying ? "pause.fill" : "play.fill") { playback.play(reduceMotion: reduceMotion) }
                        .disabled(proof == nil).accessibilityIdentifier("review.line.play")
                    Spacer(minLength: 0)
                    BoardIconButton(title: "Next position", symbol: "chevron.right") { playback.seek(index + 1) }
                        .disabled(index >= (proof?.moves.count ?? 0)).accessibilityIdentifier("review.line.next")
                    BoardIconButton(title: "Last position", symbol: "forward.end.fill") { playback.seek(proof?.moves.count ?? 0) }
                        .disabled(index >= (proof?.moves.count ?? 0)).accessibilityIdentifier("review.line.last")
                }
                if let proof {
                    HStack {
                        Text(proof.notation.joined(separator: " ")).font(.caption.monospaced()).lineLimit(1)
                            .accessibilityIdentifier("review.keyLine")
                        Spacer()
                        Text("\(index)/\(proof.moves.count)").font(.caption.monospacedDigit())
                            .accessibilityIdentifier("review.line.position")
                    }.foregroundStyle(ChessMeStyle.muted)
                }
            }
        }
        .task(id: fen + moves.joined()) { await playback.load(fen: fen, moves: moves, cached: cachedProof, at: initialCursor) }
        .onChange(of: initialCursor) { _, index in playback.seek(index) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playback.stop() } }
        .onDisappear { playback.stop() }
    }
}

struct ReviewSaveNotice: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if let error = model.reviewSaveError {
            VStack(alignment: .leading, spacing: 8) {
                Text(error).font(.caption).foregroundStyle(.red)
                Button("Retry saving") { _ = model.changeReview { _ in } }
            }.accessibilityIdentifier("review.saveError")
        }
    }
}

struct GameDetailView: View {
    let game: ChessGame
    var initialMomentID: String? = nil
    var initialStep = 0
    var resumeSavedPlace = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var journey: ReviewJourney?
    @State private var place: ReviewBookmark.Place = .overview
    @State private var momentID: String?
    @State private var step = 0
    @State private var visited: [String] = []
    @State private var savedResume: ReviewBookmark?
    @State private var updateNotice: String?
    @State private var practice: ReviewPracticeEntry?
    @State private var showingDetails = false
    private var analysis: GameAnalysis? { model.gameAnalysis(for: game.id) }
    private var moment: ReviewMoment? { journey?.moments.first { $0.id == momentID } }
    private var momentIndex: Int { journey?.moments.firstIndex { $0.id == momentID } ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if place != .moment {
                    GamePlayerNames(game: game, outcome: model.outcome(for: game), prominent: true)
                        .accessibilityIdentifier("game.match")
                    if model.isDemo { Eyebrow(text: "Sample game") }
                    status
                }
                if let updateNotice { Text(updateNotice).font(.caption).foregroundStyle(ChessMeStyle.muted) }
                switch place {
                case .overview: overview
                case .moment:
                    if let moment { momentView(moment) }
                    else { Text("This moment changed. Return to the overview."); Button("Overview", action: showOverview) }
                case .recap: recap
                }
                ReviewSaveNotice()
            }.padding(22)
        }
        .background(ChessMeStyle.paper).accessibilityIdentifier("game.scroll")
        .navigationTitle("Game review").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Overview", systemImage: "square.grid.2x2", action: showOverview)
                    if let moment, moment.finding.isPuzzle {
                        Button("Keep for practice", systemImage: "bookmark") { model.updateTarget(moment.id, action: .keep) }
                    }
                    Button("Review details", systemImage: "info.circle") { showingDetails = true }
                    Button(model.isFavorite(game) ? "Remove from saved games" : "Save game", systemImage: "heart") { model.toggleFavorite(game) }
                } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel("Review options").accessibilityIdentifier("review.options")
            }
        }
        .task {
            guard journey == nil else { return }
            journey = model.reviewJourney(for: game)
            savedResume = model.reviewState.bookmarks.first { $0.gameID == game.id && (!$0.finished || resumeSavedPlace) }
            visited = savedResume?.visited ?? []
            model.reconcileReview(game: game, journey: journey!)
            if let initialMomentID { open(initialMomentID, at: initialStep) }
            else if resumeSavedPlace, let savedResume {
                if savedResume.place == .recap { place = .recap }
                else if let id = savedResume.momentID { open(id, at: savedResume.step) }
            }
            else if let main = journey?.moments.first(where: { $0.id == journey?.mainTakeawayID }) {
                model.encountered(main, game: game, journey: journey!, lineShown: false)
            }
        }
        .onChange(of: analysis) { _, _ in
            let latest = model.reviewJourney(for: game)
            guard journey?.revision != latest.revision else { return }
            if place == .overview { apply(latest) }
            else { updateNotice = "New analysis is available. Your current place is preserved; view it from the overview." }
        }
        .onChange(of: model.reviewGeneration) { _, _ in
            journey = nil; practice = nil; dismiss()
        }
        .safeAreaInset(edge: .bottom) {
            if place == .moment {
                HStack(spacing: 12) {
                    BoardIconButton(title: step > 0 ? "Previous plan step" : "Previous moment", symbol: "chevron.left") {
                        if step > 0 { step -= 1; bookmark() }
                        else if let items = journey?.moments, momentIndex > 0 { open(items[momentIndex - 1].id) }
                    }.disabled(momentIndex == 0 && step == 0).accessibilityIdentifier("game.previousMoment")
                    if let moment {
                        if moment.finding.isPuzzle {
                            BoardIconButton(title: "Practise", symbol: "scope") {
                                practice = ReviewPracticeEntry(findings: [moment.finding])
                            }.accessibilityIdentifier("game.practiceMoment")
                        }
                        NavigationLink {
                            GameReplayExplorer(game: game, initialPly: moment.plies[min(step, moment.plies.count - 1)])
                        } label: {
                            Image(systemName: "arrow.triangle.branch").font(.system(size: 17, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(ChessMeStyle.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        }.accessibilityLabel("Explore").accessibilityIdentifier("review.explore")
                    }
                    let hasNextStep = moment.map { $0.kind == .plan && step + 1 < $0.plies.count } ?? false
                    PrimaryButton(title: hasNextStep ? "Next step" : momentIndex + 1 < (journey?.moments.count ?? 0) ? "Next moment" : "Review recap") {
                        if hasNextStep { step += 1; bookmark(); return }
                        guard let items = journey?.moments else { return }
                        if momentIndex + 1 < items.count { open(items[momentIndex + 1].id) }
                        else { place = .recap; bookmark() }
                    }.accessibilityLabel(hasNextStep ? "Next plan step" : momentIndex + 1 < (journey?.moments.count ?? 0) ? "Next moment" : "Review recap")
                        .accessibilityIdentifier("game.nextMoment")
                }.padding(.horizontal, 22).padding(.vertical, 10).background(ChessMeStyle.paper)
            }
        }
        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        GamePlayerNames(game: game, outcome: model.outcome(for: game), prominent: true)
                        status
                        if let moment { Text(moment.title).font(ChessMeStyle.title(23)); Text(moment.explanation) }
                    }.padding(22)
                }.background(ChessMeStyle.paper).navigationTitle("Review details")
                    .toolbar { Button("Done") { showingDetails = false } }
            }
        }
        .sheet(item: $practice) { entry in
            NavigationStack {
                ReviewPracticeSetView(findings: entry.findings, originGameID: game.id) { practice = nil }
            }
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let analysis {
                Text("\(analysis.source.capitalized) review · \(analysis.analyzedPlies)/\(analysis.totalPlies) decisions")
                    .font(.caption).foregroundStyle(ChessMeStyle.muted).accessibilityIdentifier("game.reviewStatus")
                Text("Saved analysis: " + (analysis.engineVersion.hasPrefix("arasan") ? "Arasan 26" :
                     analysis.engineVersion.hasPrefix("stockfish") ? "Stockfish 19" : "\(analysis.engineVersion)"))
                    .font(.caption).foregroundStyle(ChessMeStyle.muted)
                if !analysis.isComplete { Text("Takeaways cover the analysed portion of this game.").font(.caption) }
                if let job = model.localAnalysisJob(for: game.id), job.isPending {
                    Text(analysis.isComplete ? "Your saved review is ready. A deeper pass is \(job.state.rawValue)." : job.statusText)
                        .font(.caption).accessibilityIdentifier("game.deeperReviewStatus")
                }
            } else {
                Text(model.localAnalysisJob(for: game.id)?.statusText ?? "No saved analysis yet. You can still replay the game.")
                    .font(.subheadline)
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let main = journey?.moments.first(where: { $0.id == journey?.mainTakeawayID }) {
                PaperCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Main takeaway")
                        Button { open(main.id) } label: {
                            Text(main.title).font(ChessMeStyle.title(24)).foregroundStyle(ChessMeStyle.ink)
                        }.accessibilityIdentifier("review.mainTakeaway")
                    }
                }
            }
            if let savedResume, let journey,
               (savedResume.place == .recap || journey.moments.contains(where: { $0.id == savedResume.momentID })),
               savedResume.place != .overview {
                PrimaryButton(title: "Resume review", symbol: "play.fill") {
                    if savedResume.place == .recap { place = .recap }
                    else if let id = savedResume.momentID { open(id, at: savedResume.step) }
                }.accessibilityIdentifier("review.resume")
            }
            if let first = journey?.moments.first {
                PrimaryButton(title: "Review key moments", symbol: "play.fill") { open(first.id) }
                    .accessibilityIdentifier("review.start")
            } else if analysis?.isComplete == true {
                Text("No clear teaching moments were found by this review. You can still explore the game.")
            }
            NavigationLink { GameReplayExplorer(game: game) } label: { Label("Explore game", systemImage: "arrow.triangle.branch") }
                .accessibilityIdentifier("game.explore")
            ForEach(journey?.moments ?? []) { item in
                Button { open(item.id) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text("Move \(item.finding.moveNumber)").font(.caption.monospacedDigit())
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text(item.kind == .plan ? "Plan sequence · \(item.plies.count) key decisions" :
                                 item.kind == .strength ? "An instructive strong decision" : "An improvement to consider")
                                .font(.caption).foregroundStyle(ChessMeStyle.muted)
                        }
                        Spacer()
                        Image(systemName: visited.contains(item.id) ? "checkmark.circle" : "chevron.right")
                    }.foregroundStyle(ChessMeStyle.ink).padding(.vertical, 10)
                }.buttonStyle(.plain).accessibilityIdentifier("review.moment.\(item.id)")
            }
            observations
            Button("Finish for now") { place = .recap; bookmark() }.frame(minHeight: 44)
        }
    }

    private func momentView(_ item: ReviewMoment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Moment \(momentIndex + 1)/\(journey?.moments.count ?? 0) · Move \(item.finding.moveNumber)")
                    .font(.caption.weight(.semibold)).foregroundStyle(ChessMeStyle.muted)
                Spacer()
                Text(model.isDemo ? "Sample" : analysis?.source == "cloud" ? "Cloud review" : "Device review")
                    .font(.caption).foregroundStyle(ChessMeStyle.muted)
            }
            Text(item.title).font(ChessMeStyle.title(22)).fixedSize(horizontal: false, vertical: true)
            if item.kind == .plan, item.plies.count > 1 {
                Text("Step \(step + 1)/\(item.plies.count)").font(.caption.weight(.medium))
                    .accessibilityIdentifier("review.planSteps")
            }
            let offset = item.kind == .plan ? (item.plies[min(step, item.plies.count - 1)] - item.plies[0]) : 0
            ReviewLineView(fen: item.finding.positionFEN, moves: item.keyLine, perspective: game.playerSide,
                           cachedProof: item.lineProof, initialCursor: offset)
            Text(item.explanation).font(.subheadline).lineSpacing(2).lineLimit(3).accessibilityIdentifier("review.idea")
        }
    }

    private var recap: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review recap").font(ChessMeStyle.title(28))
            Text("\(visited.count) of \(journey?.moments.count ?? 0) selected moments visited.").font(.subheadline)
            Text("Reviewing and practising are recorded separately.").font(.caption).foregroundStyle(ChessMeStyle.muted)
            if let main = journey?.moments.first(where: { $0.id == journey?.mainTakeawayID }) {
                Button("Main takeaway: " + main.title) { open(main.id) }
            }
            let eligible = journey?.moments.filter { $0.finding.isPuzzle }.map(\.finding) ?? []
            if !eligible.isEmpty {
                PrimaryButton(title: "Practice from this game", symbol: "scope") {
                    practice = ReviewPracticeEntry(findings: eligible)
                }.accessibilityIdentifier("review.practiceGame")
            }
            if let journey { ReviewRelatedList(moments: journey.moments, returnGameID: game.id) }
            ForEach((journey?.moments ?? []).filter { !visited.contains($0.id) }) { item in
                Button("Not visited: " + item.title) { open(item.id) }
            }
            Button("Return to overview", action: showOverview).frame(minHeight: 44)
            observations
        }
    }

    private var observations: some View {
        let items = model.reviewState.observations.filter { $0.gameID == game.id }
        return Group {
            if !items.isEmpty {
                Text("Connections to earlier lessons").font(ChessMeStyle.title(21))
                ForEach(items) { item in ReviewObservationLink(observation: item) }
            }
        }
    }
    private func open(_ id: String, at selectedStep: Int = 0) {
        guard let journey, let item = journey.moments.first(where: { $0.id == id }) else { return }
        momentID = id; step = min(max(0, selectedStep), max(0, item.plies.count - 1)); place = .moment
        if !visited.contains(id) { visited.append(id) }
        model.encountered(item, game: game, journey: journey, lineShown: true); bookmark()
    }
    private func bookmark() {
        guard let journey else { return }
        let value = ReviewBookmark(gameID: game.id, revision: journey.revision, place: place, momentID: momentID,
                                   step: step, visited: visited, finished: place == .recap && visited.count == journey.moments.count)
        model.saveBookmark(value); savedResume = value.finished ? nil : value
    }
    private func apply(_ latest: ReviewJourney) {
        if let savedResume, savedResume.revision != latest.revision,
           !latest.moments.contains(where: { $0.id == savedResume.momentID }) {
            self.savedResume = nil
            updateNotice = "This review changed. Choose a moment from the updated overview."
        }
        journey = latest
        if savedResume != nil { savedResume?.revision = latest.revision }
        visited = visited.filter { id in latest.moments.contains { $0.id == id } }
        model.reconcileReview(game: game, journey: latest)
    }
    private func showOverview() {
        place = .overview
        apply(model.reviewJourney(for: game))
    }
}

struct ReviewRelatedList: View {
    let moments: [ReviewMoment]
    var sessionID: String? = nil
    var returnGameID: String? = nil
    @EnvironmentObject private var model: AppModel
    var body: some View {
        let connections = uniqueConnections
        if !connections.isEmpty {
            Text("Optional related positions").font(ChessMeStyle.title(21))
            ForEach(connections) { connection in
                NavigationLink {
                    ReviewPracticeView(finding: connection.puzzle.reviewFinding, puzzle: connection.puzzle,
                                       linkedTargetID: connection.targetID, connectionText: connection.explanation,
                                       sessionID: sessionID, returnGameID: returnGameID)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Try a related position · estimated \(connection.puzzle.rating)").font(.subheadline)
                        Text("Lichess catalogue · optional").font(.caption).foregroundStyle(ChessMeStyle.muted)
                        if model.hasSeenReviewPuzzle(connection.puzzle) { Text("Previously seen puzzle").font(.caption) }
                    }.padding(.vertical, 8)
                }
            }
        } else {
            Text(model.puzzlesLoading ? "Related-position matching is in progress. You can continue." :
                 "No verified related position is available for these lessons.").font(.caption).foregroundStyle(ChessMeStyle.muted)
        }
    }
    private var uniqueConnections: [ReviewPuzzleConnection] {
        var seen = Set<String>()
        return moments.flatMap { model.relatedConnections(for: $0) }.filter { seen.insert($0.id).inserted }
    }
}
