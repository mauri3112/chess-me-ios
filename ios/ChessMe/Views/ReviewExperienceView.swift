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
    var label = "Review key line"
    @State private var cursor = 0
    private var proof: ReviewLineProof? {
        (try? ChessPosition(fen: fen)).flatMap { ReviewLineProof(position: $0, moves: moves) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(ChessMeStyle.muted)
            if let proof {
                let index = min(cursor, proof.moves.count)
                ChessBoardView(position: proof.positions[index], perspective: perspective)
                Text(proof.notation.joined(separator: " ")).font(.subheadline.monospaced())
                    .accessibilityIdentifier("review.keyLine")
                HStack {
                    Button("Previous position") { cursor = max(0, index - 1) }.disabled(index == 0)
                    Spacer()
                    Text("\(index)/\(proof.moves.count)").font(.caption.monospacedDigit())
                    Spacer()
                    Button("Next position") { cursor = min(proof.moves.count, index + 1) }.disabled(index == proof.moves.count)
                }.font(.caption).frame(minHeight: 44)
            } else if let board = try? ChessPosition(fen: fen) {
                ChessBoardView(position: board, perspective: perspective)
                Text("A supporting line is not available for this position.").font(.caption)
            }
        }.onChange(of: fen + moves.joined()) { _, _ in cursor = 0 }
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
    private var analysis: GameAnalysis? { model.gameAnalysis(for: game.id) }
    private var moment: ReviewMoment? { journey?.moments.first { $0.id == momentID } }
    private var momentIndex: Int { journey?.moments.firstIndex { $0.id == momentID } ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GamePlayerNames(game: game, outcome: model.outcome(for: game), prominent: true)
                    .accessibilityIdentifier("game.match")
                if model.isDemo { Eyebrow(text: "Sample game") }
                status
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
                FavoriteButton(selected: model.isFavorite(game)) { model.toggleFavorite(game) }
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Moment \(momentIndex + 1) of \(journey?.moments.count ?? 0)").font(.caption)
                Spacer()
                Button("Overview", action: showOverview)
            }
            Text(item.title).font(ChessMeStyle.title(26))
            Text(item.explanation).font(.subheadline).lineSpacing(3).accessibilityIdentifier("review.idea")
            if item.kind == .plan, item.plies.count > 1 {
                HStack {
                    Button("Previous plan step") { step = max(0, step - 1); bookmark() }.disabled(step == 0)
                    Spacer()
                    Text("Step \(step + 1)/\(item.plies.count)").font(.caption)
                    Spacer()
                    Button("Next plan step") { step = min(item.plies.count - 1, step + 1); bookmark() }
                        .disabled(step + 1 >= item.plies.count)
                }.font(.caption).frame(minHeight: 44).accessibilityIdentifier("review.planSteps")
            }
            let offset = item.kind == .plan ? (item.plies[min(step, item.plies.count - 1)] - item.plies[0]) : 0
            let proof = (try? ChessPosition(fen: item.finding.positionFEN))
                .flatMap { ReviewLineProof(position: $0, moves: item.keyLine) }
            let start = proof?.positions[min(offset, proof?.moves.count ?? 0)].fen ?? item.finding.positionFEN
            ReviewLineView(fen: start, moves: Array(item.keyLine.dropFirst(offset)), perspective: game.playerSide,
                           label: item.kind == .plan ? "Played plan sequence" : "Illustrative review line")
                .id(item.id + String(step))
            NavigationLink {
                GameReplayExplorer(game: game, initialPly: item.plies[min(step, item.plies.count - 1)])
            } label: { Label("Explore alternatives", systemImage: "arrow.triangle.branch") }
                .accessibilityIdentifier("review.explore")
            if item.finding.isPuzzle {
                Button(item.kind == .plan ? "Practice the plan's key decision" : "Practice this moment") {
                    practice = ReviewPracticeEntry(findings: [item.finding])
                }.font(.subheadline.weight(.semibold)).frame(minHeight: 44).accessibilityIdentifier("game.practiceMoment")
                if item.kind == .plan && step > 0 {
                    Text("Practice starts at move \(item.finding.moveNumber) and returns to this plan step.").font(.caption)
                }
                Button("Keep for practice") { model.updateTarget(item.id, action: .keep) }.frame(minHeight: 44)
            } else {
                Text("This moment is available to review and explore; its exercise cannot yet be graded reliably.").font(.caption)
            }
            HStack {
                Button("Previous moment") {
                    guard let items = journey?.moments, momentIndex > 0 else { return }; open(items[momentIndex - 1].id)
                }.disabled(momentIndex == 0).accessibilityIdentifier("game.previousMoment")
                Spacer()
                Button(momentIndex + 1 < (journey?.moments.count ?? 0) ? "Next moment" : "Review recap") {
                    guard let items = journey?.moments else { return }
                    if momentIndex + 1 < items.count { open(items[momentIndex + 1].id) }
                    else { place = .recap; bookmark() }
                }.accessibilityIdentifier("game.nextMoment")
            }.frame(minHeight: 44)
            Button("Finish for now") { place = .recap; bookmark() }.frame(minHeight: 44)
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
