import SwiftUI
import ChessMeCore

struct ReviewTargetHistoryView: View {
    let targetID: String
    @EnvironmentObject private var model: AppModel
    private var target: ReviewLearningTarget? { model.reviewState.targets.first { $0.id == targetID } }
    private var attempts: [ReviewPracticeAttempt] {
        model.reviewState.attempts.filter { $0.targetID == targetID }.sorted { $0.startedAt > $1.startedAt }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let target {
                    Text(target.finding.theme).font(ChessMeStyle.title(27))
                    Text(target.finding.gameLabel).font(.subheadline)
                    Text("First encountered \(target.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                    if target.invalidated {
                        Text("The source analysis changed. This retained lesson is available to inspect; new practice requires a supported current version.").font(.subheadline)
                    } else {
                        NavigationLink { ReviewPracticeView(finding: target.finding) } label: { Text("Practise now") }.frame(minHeight: 44)
                    }
                    if let game = model.library.games.first(where: { $0.id == target.finding.gameID }) {
                        NavigationLink { GameDetailView(game: game, initialMomentID: targetID) } label: { Text("Open source review") }
                    }
                    Text("Practice evidence").font(ChessMeStyle.title(22))
                    let recalled = attempts.filter { model.reviewState.qualifiesForRecall($0) }
                    evidence("Recalled later", attempts: recalled)
                    let transferred = attempts.filter { model.reviewState.qualifiesForRelatedEvidence($0) }
                    evidence("Solved new related position", attempts: transferred)
                    Text("These labels describe specific attempts. They do not establish mastery or a cause for later results. Topic cues, exposure, and assistance remain visible below.").font(.caption)
                    if attempts.isEmpty { Text("No practice attempts yet. Skipped optional puzzles remain unassessed.").font(.subheadline) }
                    ForEach(attempts) { attempt in
                        NavigationLink { ReviewAttemptView(attemptID: attempt.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(attempt.kind == .game ? attempt.summary : "Related puzzle · " + attempt.summary)
                                Text(attempt.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                            }.padding(.vertical, 6)
                        }
                    }
                    Text("Later-game observations").font(ChessMeStyle.title(22))
                    let observations = model.reviewState.observations.filter { $0.targetID == targetID }.sorted { $0.playedAt > $1.playedAt }
                    if observations.isEmpty {
                        Text("No supported later-game connection yet. A broad topic match or an uncertain game date is not evidence.").font(.caption)
                    }
                    ForEach(observations) { item in ReviewObservationLink(observation: item) }
                    ReviewLineView(fen: target.finding.positionFEN, moves: target.finding.continuation,
                                   label: "Retained lesson line")
                        .onAppear { model.changeReview { $0.expose(targetID, kind: .line) } }
                } else { Text("This lesson is no longer stored on this device.") }
                ReviewSaveNotice()
            }.padding(22)
        }.background(ChessMeStyle.paper).navigationTitle("Lesson history").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
    @ViewBuilder private func evidence(_ label: String, attempts: [ReviewPracticeAttempt]) -> some View {
        if let latest = attempts.first {
            NavigationLink { ReviewAttemptView(attemptID: latest.id) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Label(label, systemImage: "checkmark.circle")
                    Text(latest.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                }
            }
        } else { Text(label + ": not yet evidenced").font(.subheadline).foregroundStyle(ChessMeStyle.muted) }
    }
}

struct ReviewAttemptView: View {
    let attemptID: String
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let attempt = model.reviewState.attempts.first(where: { $0.id == attemptID }) {
                    Text(attempt.summary).font(ChessMeStyle.title(27))
                    Text(attempt.kind == .game ? "Game-derived exercise" : "Separate catalogue puzzle").font(.subheadline)
                    Text(attempt.startedAt.formatted(date: .complete, time: .shortened)).font(.caption)
                    if model.reviewState.qualifiesForRecall(attempt) { Label("Recalled later", systemImage: "checkmark.circle") }
                    if model.reviewState.qualifiesForRelatedEvidence(attempt) {
                        Label("Solved new related position", systemImage: "checkmark.circle")
                    }
                    Text(attempt.knownSeenBefore ? "This position was known to have been seen before." :
                         "No prior exposure is recorded on this device.").font(.caption)
                    if attempt.topicCued {
                        Text(attempt.kind == .game ? "The stated exercise goal provided a topic cue." :
                             "A topic cue was provided by the related-position invitation.").font(.caption)
                    }
                    if !attempt.help.isEmpty {
                        Text("Help used: " + attempt.help.map(\.rawValue).joined(separator: ", ")).font(.subheadline)
                    }
                    if attempt.hasMistake { Text("This attempt included a mistaken choice or retry.").font(.subheadline) }
                    ReviewLineView(fen: attempt.rootFEN, moves: attempt.line,
                                   perspective: (try? ChessPosition(fen: attempt.rootFEN).sideToMove) ?? .white,
                                   label: "Moves accepted in this attempt")
                        .onAppear {
                            if !attempt.line.isEmpty { model.changeReview { $0.expose(attempt.targetID, kind: .line) } }
                        }
                    ForEach(attempt.decisions) { decision in
                        VStack(alignment: .leading, spacing: 4) {
                            let board = try? ChessPosition(fen: decision.positionFEN)
                            let notation = (try? board?.san(ChessMove(uci: decision.move))) ?? decision.move
                            Text("\(notation) · \(decision.grade.rawValue.capitalized)").font(.subheadline)
                            Text(decision.date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                        }
                    }
                    if let puzzleID = attempt.puzzleID, let url = URL(string: "https://lichess.org/training/\(puzzleID)") {
                        Link("Source puzzle \(puzzleID) · Lichess CC0", destination: url)
                    }
                    if let target = model.reviewState.targets.first(where: { $0.id == attempt.targetID }) {
                        if attempt.kind == .game && (target.revision != attempt.evidenceRevision || target.invalidated) {
                            Text("This attempt used an earlier analysis revision. Its moves remain recorded; it does not establish recall of the current lesson.").font(.caption)
                        }
                        NavigationLink { ReviewTargetHistoryView(targetID: target.id) } label: { Text("Lesson and evidence history") }
                    }
                } else { Text("This attempt is no longer stored on this device.") }
            }.padding(22)
        }.background(ChessMeStyle.paper).navigationTitle("Attempt details").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}

struct ReviewObservationLink: View {
    let observation: ReviewGameObservation
    var body: some View {
        NavigationLink { ReviewObservationView(observation: observation) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(observation.kind == .soundChoice ? "Sound choice in a later game" : "Another opportunity in a later game")
                    .font(.subheadline.weight(.medium))
                Text("Move \(observation.ply / 2 + 1) · \(observation.playedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
            }.padding(.vertical, 6)
        }
    }
}

private struct ReviewObservationView: View {
    let observation: ReviewGameObservation
    @EnvironmentObject private var model: AppModel
    private var isCurrent: Bool {
        model.reviewState.observations.contains(observation) && model.reviewState.targets.contains {
            $0.id == observation.targetID && !$0.invalidated && $0.revision == observation.lessonRevision
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !isCurrent {
                    Text("This connection changed with its source analysis. Open the current lesson history to see supported observations.").font(.subheadline)
                } else {
                Text(observation.kind == .soundChoice ? "A sound later choice" : "A later missed opportunity").font(ChessMeStyle.title(26))
                Text(observation.explanation).font(.subheadline)
                Text("The board evidence connects these positions. This is separate from practice results and does not show that practice caused the choice.").font(.caption)
                Text("Played \(observation.playedAt.formatted(date: .abbreviated, time: .shortened)); assessed \(observation.assessedAt.formatted(date: .abbreviated, time: .shortened)).").font(.caption)
                ReviewLineView(fen: observation.positionFEN, moves: observation.keyLine,
                               perspective: (try? ChessPosition(fen: observation.positionFEN).sideToMove) ?? .white)
                if let game = model.library.games.first(where: { $0.id == observation.gameID }) {
                    NavigationLink { GameReplayExplorer(game: game, initialPly: observation.ply) } label: { Text("Open later game") }
                }
                NavigationLink { ReviewTargetHistoryView(targetID: observation.targetID) } label: { Text("Open earlier lesson") }
                }
            }.padding(22)
        }.background(ChessMeStyle.paper).navigationTitle("Game connection").navigationBarTitleDisplayMode(.inline)
    }
}
