import XCTest
import ChessMeCore
@testable import ChessMe

final class ReviewExperienceTests: XCTestCase {
    @MainActor private func fixture() throws -> (AppModel, ChessGame, MoveFinding) {
        let game = try XCTUnwrap(DemoContent.games().first)
        let review = try LocalAnalyzer(options: AnalysisOptions(maximumDepth: 1, nodesPerMove: 800)).analyze(game: game)
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], analyses: [review], isDemo: true))
        let moment = try XCTUnwrap(model.reviewJourney(for: game).moments.first { $0.finding.isPuzzle })
        model.encountered(moment, game: game, journey: model.reviewJourney(for: game), lineShown: true)
        return (model, game, moment.finding)
    }

    @MainActor func testAttemptIdentitySurvivesSnapshotAndDuplicateSaveWithoutDuplicateOutcome() throws {
        let (model, _, finding) = try fixture()
        var run = try model.prepareReviewRun(finding: finding)
        let generation = model.reviewGeneration
        run.reviewAnswer()
        XCTAssertTrue(model.saveReviewRun(run, generation: generation))
        XCTAssertTrue(model.saveReviewRun(run, generation: generation))
        XCTAssertEqual(model.reviewState.attempts.count, 1)
        let data = try JSONEncoder().encode(model.library)
        let restored = AppModel(previewLibrary: try JSONDecoder().decode(LibrarySnapshot.self, from: data))
        XCTAssertEqual(restored.reviewState.attempts.first?.id, run.id)
        XCTAssertEqual(restored.reviewState.targets.first?.dueAt, model.reviewState.targets.first?.dueAt)
        XCTAssertFalse(restored.reviewState.qualifiesForRecall(run.attempt))
    }

    @MainActor func testLocalDeletionInvalidatesLatePracticeAndRemovesNewCollections() throws {
        let (model, game, finding) = try fixture()
        let run = try model.prepareReviewRun(finding: finding), generation = model.reviewGeneration
        var replay = try GameReplay(game: game)
        try replay.play(ChessMove(uci: "d2d4"))
        XCTAssertTrue(model.saveReviewLine(game: game, replay: replay))
        XCTAssertEqual(model.reviewState.savedLines.count, 1)
        let staleJourney = model.reviewJourney(for: game)
        let staleMoment = try XCTUnwrap(staleJourney.moments.first)
        model.deleteLocalData()
        XCTAssertNotEqual(model.reviewGeneration, generation)
        XCTAssertFalse(model.saveReviewRun(run, generation: generation))
        model.encountered(staleMoment, game: game, journey: staleJourney, lineShown: true)
        XCTAssertFalse(model.saveReviewLine(game: game, replay: replay))
        XCTAssertTrue(model.reviewState.attempts.isEmpty && model.reviewState.targets.isEmpty && model.reviewState.savedLines.isEmpty)
    }

    @MainActor func testOptionalPuzzlePersistsItsRecapOrStandaloneReturnAfterSnapshotRestore() throws {
        let (model, game, finding) = try fixture()
        model.openLesson(finding)
        let sessionID = try XCTUnwrap(model.reviewState.session?.id)
        model.changeReview { $0.session?.finished = true; $0.session?.surface = .recap; $0.session?.index = 1 }
        let puzzle = try XCTUnwrap(DemoContent.puzzleExamples.first)
        let run = try model.prepareReviewRun(finding: puzzle.reviewFinding, puzzle: puzzle,
                                              sessionID: sessionID)
        XCTAssertTrue(model.hasResumableReview)
        XCTAssertEqual(model.reviewState.session?.activeRelatedRunID, run.id)
        let restored = AppModel(previewLibrary: try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(model.library)))
        restored.resumeReviewSession()
        XCTAssertNotNil(restored.activeLesson)
        XCTAssertEqual(restored.reviewState.session?.surface, .recap)
        let standalone = try restored.prepareReviewRun(finding: puzzle.reviewFinding, puzzle: puzzle, returnGameID: game.id)
        XCTAssertEqual(restored.reviewState.standalonePractice?.runID, standalone.id)
        XCTAssertEqual(restored.reviewState.standalonePractice?.returnGameID, game.id)
    }

    @MainActor func testResumeUsesPinnedSessionAndBookmarkOutsideGamesFilter() throws {
        let (model, game, finding) = try fixture()
        let bookmark = ReviewBookmark(gameID: game.id, revision: "pinned", place: .moment,
                                      momentID: finding.id, step: 1, visited: [finding.id])
        model.saveBookmark(bookmark)
        var session = ReviewFollowUpSession(targetIDs: [finding.id], originGameID: game.id)
        session.index = 0
        model.changeReview { $0.session = session }
        model.resumeReviewSession()
        XCTAssertEqual(model.session.map(\.id), [finding.id])
        XCTAssertEqual(model.reviewState.session?.originGameID, game.id)
        XCTAssertEqual(model.reviewState.bookmarks.first?.step, 1)
        model.endSession()
        XCTAssertFalse(model.reviewState.session?.finished ?? true)
        model.changeReview { $0.targets[0].dismissed = true }
        let before = model.reviewState.targets[0]
        model.resumeReviewSession()
        XCTAssertEqual(model.reviewState.targets[0], before)
    }

    @MainActor func testSessionMembershipDoesNotEnrollUnvisitedExercises() throws {
        let (model, game, finding) = try fixture()
        let unvisited = MoveFinding(id: "not-yet-visited", gameID: finding.gameID, gameLabel: finding.gameLabel,
            positionFEN: finding.positionFEN, playedMove: finding.playedMove, bestMove: finding.bestMove,
            acceptedMoves: finding.acceptedMoves, continuation: finding.continuation, centipawnLoss: finding.centipawnLoss,
            theme: finding.theme, explanation: finding.explanation, hint: finding.hint, moveNumber: finding.moveNumber)
        model.changeReview { $0.session = ReviewFollowUpSession(targetIDs: [finding.id, unvisited.id], findings: [finding, unvisited]) }
        model.resumeReviewSession()
        XCTAssertEqual(model.session.map(\.id), [finding.id, unvisited.id])
        XCTAssertEqual(model.reviewState.targets.map(\.id), [finding.id])
        let sessionID = try XCTUnwrap(model.reviewState.session?.id)
        model.changeReview { $0.session?.surface = .recap }
        let puzzle = try XCTUnwrap(DemoContent.puzzleExamples.first)
        var run = try model.prepareReviewRun(finding: puzzle.reviewFinding, puzzle: puzzle,
                                             linkedTargetID: unvisited.id, sessionID: sessionID)
        XCTAssertEqual(run.targetID, unvisited.id)
        XCTAssertEqual(run.attempt.sourceGameID, game.id)
        XCTAssertEqual(run.attempt.sourceUsername, game.username)
        XCTAssertTrue(model.reviewState.session?.attemptIDs.contains(run.id) == true)
        XCTAssertEqual(model.reviewState.targets.map(\.id), [finding.id])
        run.attempt.outcome = .completed; run.attempt.endedAt = Date()
        run.attempt.decisions = [ReviewDecision(positionFEN: run.rootFEN, move: puzzle.solution[0], grade: .accepted)]
        XCTAssertFalse(model.reviewState.qualifiesForRelatedEvidence(run.attempt))
        XCTAssertTrue(model.saveReviewRun(run, generation: model.reviewGeneration))
        // Replacing the set cannot erase the account-removal provenance.
        model.changeReview { $0.session = ReviewFollowUpSession(targetIDs: []) }
        var restored = try JSONDecoder().decode(ReviewLibrary.self, from: JSONEncoder().encode(model.reviewState))
        restored.removeAccount(game.username, gameIDs: [game.id])
        XCTAssertFalse(restored.attempts.contains { $0.id == run.id })
        XCTAssertFalse(restored.runs.contains { $0.id == run.id })
    }

    @MainActor func testCorrectedContinuationCannotContinueAnOldRunAndAdoptsLatestOnEncounter() throws {
        let (model, game, finding) = try fixture()
        let run = try model.prepareReviewRun(finding: finding)
        model.changeReview { $0.targets[0].invalidated = true }
        XCTAssertFalse(model.saveReviewRun(run, generation: model.reviewGeneration))
        XCTAssertThrowsError(try model.prepareReviewRun(finding: finding))
        let oldReview = try XCTUnwrap(model.gameAnalysis(for: game.id))
        let newReview = GameAnalysis(gameID: oldReview.gameID, findings: oldReview.findings,
            analyzedPlies: oldReview.analyzedPlies, totalPlies: oldReview.totalPlies, source: oldReview.source,
            completedAt: oldReview.completedAt.addingTimeInterval(60), engineVersion: oldReview.engineVersion,
            configurationID: oldReview.configurationID, moveAssessments: oldReview.moveAssessments)
        model.updateLibrary { $0.analyses = [newReview] }
        let current = model.reviewJourney(for: game)
        let moment = try XCTUnwrap(current.moments.first { $0.id == finding.id })
        model.changeReview { state in
            let old = state.targets[0]
            var prior = ReviewLearningTarget(username: old.username, finding: old.finding, revision: "superseded",
                                             history: old.history, ideaKey: old.ideaKey)
            prior.dismissed = true; prior.invalidated = true
            state.targets[0] = prior
        }
        model.encountered(moment, game: game, journey: current, lineShown: true)
        XCTAssertEqual(model.reviewState.targets[0].revision, moment.evidenceRevision)
        XCTAssertTrue(model.reviewState.targets[0].dismissed)
        XCTAssertFalse(model.reviewState.targets[0].invalidated)
        let replacement = try model.prepareReviewRun(finding: finding)
        XCTAssertEqual(replacement.revision, moment.evidenceRevision)
    }

    @MainActor func testPinnedOldReviewCannotReplaceCurrentLessonEvidence() throws {
        let (model, game, old) = try fixture()
        let pinned = model.reviewJourney(for: game)
        let oldMoment = try XCTUnwrap(pinned.moments.first { $0.id == old.id })
        let board = try ChessPosition(fen: old.positionFEN)
        let alternative = try XCTUnwrap(board.legalMoves().first { $0.uci != old.bestMove && $0.uci != old.playedMove })
        let changed = MoveFinding(id: old.id, gameID: old.gameID, gameLabel: old.gameLabel, positionFEN: old.positionFEN,
            playedMove: old.playedMove, bestMove: alternative.uci, acceptedMoves: [alternative.uci], continuation: [alternative.uci],
            centipawnLoss: old.centipawnLoss, theme: old.theme, explanation: old.explanation, hint: old.hint,
            moveNumber: old.moveNumber, source: old.source, isPuzzle: true, quality: .blunder)
        let review = GameAnalysis(gameID: game.id, findings: [changed], analyzedPlies: 1, totalPlies: 1)
        model.updateLibrary { $0.analyses = [review] }
        let current = model.reviewJourney(for: game)
        let latest = try XCTUnwrap(current.moments.first { $0.id == old.id })
        model.reconcileReview(game: game, journey: current)
        model.encountered(latest, game: game, journey: current, lineShown: true)
        let currentRevision = model.reviewState.targets[0].revision
        XCTAssertNotEqual(currentRevision, oldMoment.evidenceRevision)
        model.encountered(oldMoment, game: game, journey: pinned, lineShown: true)
        model.reconcileReview(game: game, journey: pinned)
        XCTAssertEqual(model.reviewState.targets[0].revision, currentRevision)
        XCTAssertFalse(model.reviewState.targets[0].invalidated)
    }

    func testLegacyLibraryWithoutReviewRecordsLoadsAndNativeDoesNotLinkStockfish() throws {
        let legacy = Data("{\"games\":[],\"analyses\":[],\"practice\":[],\"isDemo\":false,\"skippedGames\":0}".utf8)
        XCTAssertNil(try JSONDecoder().decode(LibrarySnapshot.self, from: legacy).review)
        XCTAssertFalse(StockfishEngine.isAvailable)
        XCTAssertEqual(DeviceEngineConfiguration().engine, .arasan)
        XCTAssertFalse(DeviceEngine.available.contains(.stockfish))
    }
}
