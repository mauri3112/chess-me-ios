import Foundation
import ChessMeCore

extension AppModel {
    var reviewState: ReviewLibrary { library.review ?? ReviewLibrary() }

    @discardableResult
    func changeReview(deferSave: Bool = false, _ change: (inout ReviewLibrary) -> Void) -> Bool {
        var state = reviewState
        change(&state)
        updateReviewState(state)
        if deferSave { scheduleNavigationSave(); return true }
        let saved = persist()
        reviewSaveError = saved ? nil : "Your latest practice or line changes have not been saved. Retry while they remain open."
        return saved
    }

    func reviewJourney(for game: ChessGame) -> ReviewJourney {
        let analysis = gameAnalysis(for: game.id)
        if let cached = reviewJourneyCache[game.id], cached.game == game, cached.analysis == analysis { return cached.journey }
        let journey = ReviewJourney(game: game, analysis: analysis)
        // Bound view caching; durable state is in the local library.
        if reviewJourneyCache.count >= 30, let oldest = reviewJourneyCache.keys.first { reviewJourneyCache.removeValue(forKey: oldest) }
        reviewJourneyCache[game.id] = (game, analysis, journey)
        return journey
    }

    func saveBookmark(_ bookmark: ReviewBookmark) {
        guard library.games.contains(where: { $0.id == bookmark.gameID }) else { return }
        if reviewState.bookmarks.first(where: { $0.gameID == bookmark.gameID }) == bookmark { return }
        changeReview(deferSave: true) {
            $0.bookmarks.removeAll { $0.gameID == bookmark.gameID }
            $0.bookmarks.append(bookmark)
        }
    }

    func encountered(_ moment: ReviewMoment, game: ChessGame, journey: ReviewJourney, lineShown: Bool) {
        guard library.games.contains(where: { $0.id == game.id && $0.username == game.username && $0.hasSameMainline(as: game) }),
              journey.gameID == game.id, journey.moments.contains(where: { $0.id == moment.id }),
              reviewJourney(for: game).moments.first(where: { $0.id == moment.id })?.evidenceRevision == moment.evidenceRevision else { return }
        let history = journey.history.map { Array($0.positions.prefix(moment.plies.first ?? 0)).map(\.repetitionKey) } ?? []
        changeReview(deferSave: true) { state in
            if moment.finding.isPuzzle {
                state.enroll(ReviewLearningTarget(username: game.username, finding: moment.finding, revision: moment.evidenceRevision,
                                                 history: history, ideaKey: moment.ideaKey))
            }
            state.expose(moment.id, kind: .idea)
            if lineShown { state.expose(moment.id, kind: .line) }
        }
    }

    func reconcileReview(game: ChessGame, journey: ReviewJourney) {
        guard library.games.contains(where: { $0.id == game.id && $0.username == game.username && $0.hasSameMainline(as: game) }),
              let analysis = gameAnalysis(for: game.id), reviewJourney(for: game).revision == journey.revision else { return }
        let ids = Set(journey.moments.map(\.id))
        let observations = ReviewGameConnections.observations(game: game, journey: journey, targets: reviewState.targets)
        changeReview(deferSave: true) { state in
            for index in state.targets.indices where state.targets[index].finding.gameID == game.id {
                let target = state.targets[index]
                if let current = journey.moments.first(where: { $0.id == target.id }) {
                    state.targets[index].invalidated = current.finding.positionFEN != target.finding.positionFEN ||
                        current.finding.bestMove != target.finding.bestMove ||
                        current.finding.continuation != target.finding.continuation ||
                        current.finding.isPuzzle != target.finding.isPuzzle || current.ideaKey != target.ideaKey
                } else if analysis.isComplete {
                    state.targets[index].invalidated = !ids.contains(target.id)
                }
            }
            state.observations.removeAll { $0.gameID == game.id }
            state.observations.append(contentsOf: observations)
            let invalid = Set(state.targets.filter(\.invalidated).map(\.id))
            state.observations.removeAll { invalid.contains($0.targetID) }
        }
    }

    @discardableResult
    func saveReviewLine(game: ChessGame, replay: GameReplay, expectedGeneration: UUID? = nil, snapshotID: String? = nil) -> Bool {
        guard expectedGeneration == nil || expectedGeneration == reviewGeneration else { return false }
        let retainedSource = library.games.contains { $0.id == game.id && $0.username == game.username && $0.hasSameMainline(as: game) }
        let retainedSnapshot = snapshotID.map { id in reviewState.savedLines.contains { $0.id == id } || reviewState.runs.contains { $0.id == id } } ?? false
        guard retainedSource || retainedSnapshot else {
            reviewSaveError = "This source context is no longer retained. Return to your current games or saved lines."
            return false
        }
        do {
            let line = try SavedReviewLine(game: game, replay: replay)
            return changeReview { $0.save(line) }
        } catch {
            reviewSaveError = error.localizedDescription
            return false
        }
    }

    func target(for finding: MoveFinding) -> ReviewLearningTarget? {
        if let target = reviewState.targets.first(where: { $0.id == finding.id }) { return target }
        guard let game = library.games.first(where: { $0.id == finding.gameID }) else { return nil }
        let journey = reviewJourney(for: game)
        guard let moment = journey.moments.first(where: { $0.id == finding.id }) else { return nil }
        encountered(moment, game: game, journey: journey, lineShown: false)
        return reviewState.targets.first { $0.id == finding.id }
    }

    func storedDecisionDepth(for run: AdaptiveReviewRun, move: ChessMove) -> Int? {
        guard let target = reviewState.targets.first(where: { $0.id == run.targetID }),
              !target.invalidated, target.revision == run.revision,
              let game = library.games.first(where: { $0.id == run.sourceFinding.gameID }),
              let history = reviewJourney(for: game).history,
              let root = history.positions.firstIndex(where: { $0.fen == run.rootFEN }),
              Array(history.positions.prefix(root)).map(\.repetitionKey) == run.rootHistory,
              let proof = ReviewLineProof(position: history.positions[root], moves: run.sourceFinding.continuation),
              run.acceptedMoves.count < proof.moves.count,
              run.acceptedMoves == Array(proof.moves.prefix(run.acceptedMoves.count)),
              proof.positions[run.acceptedMoves.count].fen == run.currentFEN,
              proof.moves[run.acceptedMoves.count] == move.uci,
              let grade = gameAnalysis(for: game.id)?.moveAssessments?.first(where: {
                  $0.ply == root && $0.positionFEN == run.rootFEN && $0.bestMove == run.sourceFinding.bestMove
              }), grade.completedDepth >= ReviewMoveAcceptance.minimumDepth,
              run.acceptedMoves.count < grade.completedDepth else { return nil }
        return grade.completedDepth
    }

    func practiceLeadIn(for run: AdaptiveReviewRun) -> MoveHistory? {
        guard run.acceptedMoves.isEmpty, !run.isFinished else { return nil }
        if let puzzle = run.puzzleSnapshot, let start = try? ChessPosition(fen: puzzle.setupFEN),
           let move = try? ChessMove(uci: puzzle.setupMove) {
            return try? MoveHistory(position: start).appending([move])
        }
        guard let game = library.games.first(where: { $0.id == run.sourceFinding.gameID }),
              let history = reviewJourney(for: game).history,
              let index = history.positions.firstIndex(where: { $0.fen == run.rootFEN }) else { return nil }
        let lead = history.prefix(through: index).leadIn()
        return lead.moves.isEmpty ? nil : lead
    }

    func practiceExploration(for run: AdaptiveReviewRun) throws -> ChessGame {
        let history = library.games.first(where: { $0.id == run.sourceFinding.gameID }).flatMap { reviewJourney(for: $0).history }
        let index = history?.positions.firstIndex { $0.fen == run.rootFEN }
        return try run.explorationGame(prefix: index.flatMap { history?.prefix(through: $0) })
    }

    func puzzleConnectionExplanation(for run: AdaptiveReviewRun) -> String? {
        if let connection = run.puzzleConnection, connection.targetID == run.targetID,
           connection.puzzle == run.puzzleSnapshot { return connection.explanation }
        // Older runs did not pin the connection. Recover one only from the
        // same still-supported lesson revision and the exact puzzle snapshot.
        guard let puzzle = run.puzzleSnapshot,
              let target = reviewState.targets.first(where: { $0.id == run.targetID }), !target.invalidated,
              target.revision == run.attempt.linkedLessonRevision,
              let game = library.games.first(where: { $0.id == target.finding.gameID }),
              let moment = reviewJourney(for: game).moments.first(where: { $0.id == target.id }),
              moment.evidenceRevision == target.revision else { return nil }
        return ReviewPuzzleConnection.match(puzzle: puzzle, moment: moment)?.explanation
    }

    func prepareReviewRun(finding: MoveFinding, puzzle: TrainingPuzzle? = nil, linkedTargetID: String? = nil,
                          resumeSessionResult: Bool = false, sessionID: String? = nil, resumeRunID: String? = nil,
                          returnGameID: String? = nil, parentRunID: String? = nil) throws -> AdaptiveReviewRun {
        let target = linkedTargetID.flatMap { id in reviewState.targets.first { $0.id == id } } ?? (puzzle == nil ? self.target(for: finding) : nil)
        guard target?.invalidated != true else { throw ChessError.invalidMove("This lesson changed. Open its latest source review before practising.") }
        if puzzle == nil, let target,
           target.finding.positionFEN != finding.positionFEN || target.finding.bestMove != finding.bestMove ||
            target.finding.continuation != finding.continuation {
            throw ChessError.invalidMove("This exercise uses earlier evidence. Open the current lesson from Practice or its source review.")
        }
        let targetID = linkedTargetID ?? target?.id ?? finding.id
        guard puzzle != nil || target != nil else { throw ChessError.invalidMove("The source lesson is no longer retained. Return to Games and open a supported current review.") }
        if let resumeRunID, var pinned = reviewState.runs.first(where: { $0.id == resumeRunID && $0.isConsistent }),
           pinned.targetID == targetID, pinned.attempt.puzzleID == puzzle?.id,
           (puzzle != nil || pinned.revision == target?.revision) {
            pinned.resumePractice()
            _ = saveReviewRun(pinned, generation: reviewGeneration)
            return pinned
        }
        if resumeSessionResult, let session = reviewState.session, session.canResume,
           let completed = reviewState.runs.last(where: {
               session.attemptIDs.contains($0.id) && $0.targetID == targetID && $0.attempt.puzzleID == puzzle?.id &&
               $0.isFinished && $0.isConsistent && (puzzle != nil || $0.revision == target?.revision)
           }) { return completed }
        if var existing = reviewState.runs.last(where: {
            $0.targetID == targetID && $0.attempt.puzzleID == puzzle?.id && !$0.isFinished &&
            $0.rootFEN == finding.positionFEN && (puzzle != nil || $0.revision == target?.revision)
        }) {
            guard existing.isConsistent else { throw ChessError.invalidMove("This saved exercise cannot be restored safely. Skip it and start a new attempt from the lesson.") }
            existing.resumePractice()
            _ = saveReviewRun(existing, generation: reviewGeneration)
            changeReview { state in
                if state.session?.id == sessionID && state.session?.targetIDs.contains(targetID) == true && state.session?.attemptIDs.contains(existing.id) == false {
                    state.session?.attemptIDs.append(existing.id)
                }
                if puzzle != nil, let sessionID, state.session?.id == sessionID { state.session?.activeRelatedRunID = existing.id }
                else if puzzle != nil, returnGameID != nil || parentRunID != nil {
                    state.standalonePractice = ReviewStandalonePractice(runID: existing.id, parentRunID: parentRunID, returnGameID: returnGameID)
                }
            }
            return existing
        }
        let history = puzzle.flatMap { try? ChessPosition(fen: $0.setupFEN) }.map { [$0.repetitionKey] } ?? target?.history ?? []
        let revision = puzzle.map { ReviewIdentity.make([$0.id, $0.positionFEN, $0.solution.joined(separator: " ")]) }
            ?? target?.revision ?? ReviewIdentity.make([finding.id, finding.positionFEN, finding.source])
        let seen = puzzle.map(hasSeenReviewPuzzle) ?? reviewState.exposures.contains { $0.targetID == targetID }
        var run = try AdaptiveReviewRun(finding: finding, revision: revision, history: history,
                                        kind: puzzle == nil ? .game : .relatedPuzzle, puzzleID: puzzle?.id,
                                        seenBefore: seen, learningTargetID: targetID, puzzle: puzzle)
        if puzzle != nil { run.attempt.linkedLessonRevision = target?.revision }
        // Optional recap puzzles can reference a member that has never been
        // encountered. Retain deletion provenance without enrolling that lesson.
        let sourceFinding = target?.finding ?? reviewState.session?.findings?.first { $0.id == targetID }
        let parent = parentRunID.flatMap { id in reviewState.runs.first { $0.id == id } }
        run.attempt.sourceGameID = sourceFinding?.gameID ?? returnGameID ?? parent?.attempt.sourceGameID
        run.attempt.sourceUsername = target?.username ?? library.games.first { $0.id == run.attempt.sourceGameID }?.username ?? parent?.attempt.sourceUsername
        if let puzzle, let game = library.games.first(where: { $0.id == run.attempt.sourceGameID }),
           let moment = reviewJourney(for: game).moments.first(where: { $0.id == targetID }),
           target == nil || target?.revision == moment.evidenceRevision {
            run.puzzleConnection = ReviewPuzzleConnection.match(puzzle: puzzle, moment: moment)
        }
        changeReview {
            $0.runs.append(run); $0.record(run.attempt)
            if $0.session?.id == sessionID && $0.session?.targetIDs.contains(targetID) == true { $0.session?.attemptIDs.append(run.id) }
            if puzzle != nil, let sessionID, $0.session?.id == sessionID { $0.session?.activeRelatedRunID = run.id }
            else if puzzle != nil, returnGameID != nil || parentRunID != nil {
                $0.standalonePractice = ReviewStandalonePractice(runID: run.id, parentRunID: parentRunID, returnGameID: returnGameID)
            }
        }
        return run
    }

    @discardableResult
    func saveReviewRun(_ run: AdaptiveReviewRun, generation: UUID) -> Bool {
        guard generation == reviewGeneration, reviewState.runs.contains(where: { $0.id == run.id }) else { return false }
        if run.attempt.kind == .game, let target = reviewState.targets.first(where: { $0.id == run.targetID }),
           target.invalidated || target.revision != run.revision { return false }
        return changeReview { state in
            state.runs.removeAll { $0.id == run.id }
            state.runs.append(run)
            state.record(run.attempt)
        }
    }

    func relatedConnections(for moment: ReviewMoment) -> [ReviewPuzzleConnection] {
        let candidates = (library.puzzleRecommendations ?? []).filter { $0.gameID == moment.finding.gameID }
            .flatMap(\.matches).map(\.puzzle).filter { abs($0.rating - puzzleTargetRating) <= 400 }
            .sorted {
                if hasSeenReviewPuzzle($0) != hasSeenReviewPuzzle($1) { return !hasSeenReviewPuzzle($0) }
                return abs($0.rating - puzzleTargetRating) < abs($1.rating - puzzleTargetRating)
            }
        var seen = Set<String>()
        return candidates.compactMap { puzzle in
            guard seen.insert(puzzle.id).inserted else { return nil }
            return ReviewPuzzleConnection.match(puzzle: puzzle, moment: moment)
        }
    }

    func hasSeenReviewPuzzle(_ puzzle: TrainingPuzzle) -> Bool {
        if reviewState.attempts.contains(where: { $0.puzzleID == puzzle.id }) ||
            library.practice.contains(where: { $0.findingID == "lichess-puzzle-\(puzzle.id)" }) { return true }
        guard let root = try? ChessPosition(fen: puzzle.positionFEN) else { return true }
        func sameBoard(_ fen: String) -> Bool { (try? ChessPosition(fen: fen).repetitionKey) == root.repetitionKey }
        let seenTargets = Set(reviewState.exposures.map(\.targetID))
        return reviewState.attempts.contains { sameBoard($0.rootFEN) } ||
            reviewState.targets.contains { seenTargets.contains($0.id) && sameBoard($0.finding.positionFEN) } ||
            reviewState.savedLines.contains { sameBoard($0.positionFEN) }
    }

    func retireUnfinishedReviewRun(finding: MoveFinding, puzzle: TrainingPuzzle?, linkedTargetID: String?) {
        let id = linkedTargetID ?? finding.id
        changeReview { state in
            for index in state.runs.indices where state.runs[index].targetID == id &&
                state.runs[index].attempt.puzzleID == puzzle?.id && !state.runs[index].isFinished {
                state.runs[index].attempt.outcome = .ungraded
                state.runs[index].attempt.endedAt = Date()
                let attempt = state.runs[index].attempt
                state.record(attempt)
            }
        }
    }

    func relatedConnection(for finding: MoveFinding) -> ReviewPuzzleConnection? {
        guard let game = library.games.first(where: { $0.id == finding.gameID }),
              let moment = reviewJourney(for: game).moments.first(where: { $0.id == finding.id }) else { return nil }
        let connections = relatedConnections(for: moment)
        let alreadyOffered = Set(reviewState.attempts.filter {
            $0.startedAt >= (reviewState.session?.startedAt ?? Date().addingTimeInterval(-3_600))
        }.compactMap(\.puzzleID))
        return connections.first { !alreadyOffered.contains($0.puzzle.id) }
    }

    func updateTarget(_ id: String, action: ReviewTargetAction) {
        changeReview { state in
            guard let index = state.targets.firstIndex(where: { $0.id == id }) else { return }
            switch action {
            case .keep: state.targets[index].kept = true; state.targets[index].dismissed = false
            case .dismiss: state.targets[index].dismissed = true
            case .restore: state.targets[index].dismissed = false
            case .deferUntil(let date): state.targets[index].deferredUntil = date
            }
        }
    }

    var readyReviewTargets: [ReviewLearningTarget] {
        reviewState.targets.filter { $0.ready(at: Date()) && isDemo == $0.finding.gameID.hasPrefix("demo-") }
    }
    var suggestedReviewTargets: [ReviewLearningTarget] {
        let excluded = Set(reviewState.targets.filter { isDemo != $0.finding.gameID.hasPrefix("demo-") }.map(\.id))
            .union(reviewState.attempts.filter { $0.startedAt > Date().addingTimeInterval(-3_600) && $0.outcome != .inProgress }.map(\.targetID))
        return reviewState.suggestedSet(excluding: excluded)
    }
    var hasResumableReview: Bool { reviewState.standalonePractice != nil || reviewState.session?.canResume == true }
}

enum ReviewTargetAction {
    case keep, dismiss, restore, deferUntil(Date)
}
