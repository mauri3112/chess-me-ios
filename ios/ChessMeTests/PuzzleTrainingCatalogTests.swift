import XCTest
import ChessMeCore
@testable import ChessMe

@MainActor
final class PuzzleTrainingCatalogTests: XCTestCase {
    func testDiscoveryUsesSelectedThemeAndClampedTargetWithoutGameData() async throws {
        let puzzle = try XCTUnwrap(DemoContent.puzzleExamples.first)
        let catalog = PuzzleTrainingCatalog { themes, rating, excluding in
            XCTAssertEqual(themes, ["fork": 1])
            XCTAssertEqual(rating, 3000)
            XCTAssertTrue(excluding.isEmpty)
            return [PuzzleMatch(puzzle: puzzle, matchedThemes: ["fork"]), PuzzleMatch(puzzle: puzzle, matchedThemes: ["fork"])]
        }
        await catalog.load(theme: "fork", rating: 9000)
        XCTAssertEqual(catalog.puzzles.map(\.id), [puzzle.id])
        XCTAssertFalse(catalog.isLoading)
    }

    func testCancelledSelectionCannotPublishStaleResults() async throws {
        let puzzle = try XCTUnwrap(DemoContent.puzzleExamples.first)
        var response: CheckedContinuation<[PuzzleMatch], Never>?
        let catalog = PuzzleTrainingCatalog { _, _, _ in
            await withCheckedContinuation { response = $0 }
        }
        let request = Task { await catalog.load(theme: "mate", rating: 1200) }
        while response == nil { await Task.yield() }
        catalog.cancel()
        response?.resume(returning: [PuzzleMatch(puzzle: puzzle, matchedThemes: ["mate"])])
        await request.value
        XCTAssertTrue(catalog.puzzles.isEmpty)
        XCTAssertFalse(catalog.isLoading)
        XCTAssertNil(catalog.notice)
    }

    func testFindingAnotherSetExcludesTheLastPreview() async throws {
        let puzzle = try XCTUnwrap(DemoContent.puzzleExamples.first)
        var requests = 0
        let catalog = PuzzleTrainingCatalog { _, _, excluding in
            requests += 1
            if requests == 1 {
                XCTAssertTrue(excluding.isEmpty)
                return [PuzzleMatch(puzzle: puzzle, matchedThemes: ["mate"])]
            }
            XCTAssertEqual(excluding, [puzzle.id])
            return []
        }
        await catalog.load(theme: "mate", rating: 1200)
        await catalog.load(theme: "mate", rating: 1200)
        XCTAssertEqual(requests, 2)
        XCTAssertTrue(catalog.puzzles.isEmpty)
    }

    func testFailedFilterUsesRecordedFailuresAndDeduplicatesCollections() throws {
        let puzzle = try XCTUnwrap(DemoContent.puzzleExamples.first)
        let failure = PracticeRecord(findingID: "lichess-puzzle-\(puzzle.id)", correctCount: 2, failedCount: 1, dueAt: .distantFuture, lastPracticedAt: Date())
        XCTAssertEqual(PuzzleTrainingCatalog.failed(in: [puzzle, puzzle], records: [failure]).map(\.id), [puzzle.id])
        var success = failure
        success.failedCount = 0
        XCTAssertTrue(PuzzleTrainingCatalog.failed(in: [puzzle], records: [success]).isEmpty)
        XCTAssertTrue(PuzzleTrainingCatalog.failed(in: [], records: [failure]).isEmpty)
    }

    func testUnavailableCatalogueEndsLoadingAndExplainsOfflineFallback() async {
        let catalog = PuzzleTrainingCatalog { _, _, _ in throw PuzzleServiceError.unavailable }
        await catalog.load(theme: "mate", rating: 1200)
        XCTAssertFalse(catalog.isLoading)
        XCTAssertTrue(catalog.puzzles.isEmpty)
        XCTAssertTrue(catalog.notice?.contains("Saved puzzles still work offline") == true)
    }

    func testModernPracticeFailureRemainsAvailableAfterLibraryRoundTrip() throws {
        let puzzle = try XCTUnwrap(DemoContent.puzzleExamples.first)
        let model = AppModel(previewLibrary: LibrarySnapshot())
        var run = try model.prepareReviewRun(finding: puzzle.reviewFinding, puzzle: puzzle)
        run.attempt.decisions.append(ReviewDecision(positionFEN: puzzle.positionFEN, move: "f7f8", grade: .mistake))
        XCTAssertTrue(model.saveReviewRun(run, generation: model.reviewGeneration))
        let restored = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(model.library))
        let review = try XCTUnwrap(restored.review)
        let retained = review.runs.compactMap(\.puzzleSnapshot)
        XCTAssertTrue(restored.practice.isEmpty, "Modern attempts must not depend on the legacy record")
        XCTAssertEqual(PuzzleTrainingCatalog.failed(in: retained, records: restored.practice, attempts: review.attempts).map(\.id), [puzzle.id])
        var revealed = run.attempt
        revealed.decisions = []; revealed.outcome = .revealed
        XCTAssertTrue(PuzzleTrainingCatalog.failed(in: retained, records: [], attempts: [revealed]).isEmpty)
    }

    func testUnsavedCorrectCatalogueAttemptRemainsResumableAfterRoundTrip() throws {
        let puzzle = try XCTUnwrap(DemoContent.puzzleExamples.first)
        let model = AppModel(previewLibrary: LibrarySnapshot())
        var run = try model.prepareReviewRun(finding: puzzle.reviewFinding, puzzle: puzzle)
        XCTAssertTrue(run.submitStoredMove(try ChessMove(uci: puzzle.solution[0])))
        XCTAssertFalse(run.isFinished)
        XCTAssertFalse(run.attempt.hasMistake)
        XCTAssertTrue(model.saveReviewRun(run, generation: model.reviewGeneration))
        XCTAssertTrue(model.favoritePuzzles.isEmpty)
        XCTAssertTrue(model.recommendedPuzzles.isEmpty)
        let restored = AppModel(previewLibrary: try JSONDecoder().decode(LibrarySnapshot.self,
            from: JSONEncoder().encode(model.library)))
        XCTAssertTrue(restored.hasResumableReview)
        let route = try XCTUnwrap(restored.reviewState.standalonePractice)
        XCTAssertEqual(route.runID, run.id)
        XCTAssertNil(route.returnGameID)
        XCTAssertNil(route.parentRunID)
        restored.resumeReviewSession()
        XCTAssertEqual(restored.activeLesson?.id, run.sourceFinding.id)
        var resumed = try restored.prepareReviewRun(finding: run.sourceFinding, puzzle: puzzle,
            linkedTargetID: run.targetID, resumeRunID: route.runID)
        XCTAssertEqual(resumed.id, run.id)
        XCTAssertEqual(resumed.currentFEN, run.currentFEN)
        XCTAssertEqual(resumed.pendingReply, puzzle.solution[1])
        resumed.playReply()
        XCTAssertTrue(resumed.submitStoredMove(try ChessMove(uci: puzzle.solution[2])))
        XCTAssertTrue(resumed.isFinished)
        XCTAssertTrue(restored.saveReviewRun(resumed, generation: restored.reviewGeneration))
        // Keep the result reachable until Continue or Back explicitly clears its route.
        XCTAssertEqual(restored.reviewState.standalonePractice?.runID, resumed.id)
        restored.changeReview { $0.standalonePractice = nil }
        restored.endSession()
        XCTAssertFalse(restored.hasResumableReview)
    }

    func testCatalogueRestartReplacesRetiredResumeAndDeletionRejectsLateSave() throws {
        let puzzle = try XCTUnwrap(DemoContent.puzzleExamples.first)
        let model = AppModel(previewLibrary: LibrarySnapshot())
        let first = try model.prepareReviewRun(finding: puzzle.reviewFinding, puzzle: puzzle)
        let generation = model.reviewGeneration
        // Opening a formerly orphaned retained run repairs its missing route too.
        model.changeReview { $0.standalonePractice = nil }
        let reopened = try model.prepareReviewRun(finding: puzzle.reviewFinding, puzzle: puzzle)
        XCTAssertEqual(reopened.id, first.id)
        XCTAssertEqual(model.reviewState.standalonePractice?.runID, first.id)
        model.retireUnfinishedReviewRun(finding: puzzle.reviewFinding, puzzle: puzzle, linkedTargetID: nil)
        XCTAssertNil(model.reviewState.standalonePractice)
        XCTAssertFalse(model.hasResumableReview)
        XCTAssertEqual(model.reviewState.attempts.first?.outcome, .ungraded)
        let replacement = try model.prepareReviewRun(finding: puzzle.reviewFinding, puzzle: puzzle)
        XCTAssertNotEqual(replacement.id, first.id)
        XCTAssertEqual(model.reviewState.standalonePractice?.runID, replacement.id)
        var skipped = replacement
        skipped.skip()
        XCTAssertTrue(model.saveReviewRun(skipped, generation: generation))
        // Mirrors the existing Skip/Back finish path, which clears only its own route.
        model.changeReview { if $0.standalonePractice?.runID == skipped.id { $0.standalonePractice = nil } }
        XCTAssertFalse(model.hasResumableReview)
        model.deleteLocalData()
        XCTAssertFalse(model.saveReviewRun(first, generation: generation))
        XCTAssertNil(model.reviewState.standalonePractice)
    }

    func testSessionPuzzleDoesNotReplaceCatalogueResumeButExplicitReturnStillWorks() throws {
        let puzzle = try XCTUnwrap(DemoContent.puzzleExamples.first)
        let model = AppModel(previewLibrary: LibrarySnapshot())
        let direct = try model.prepareReviewRun(finding: puzzle.reviewFinding, puzzle: puzzle)
        model.changeReview { $0.session = ReviewFollowUpSession(targetIDs: ["session-target"]) }
        let sessionID = try XCTUnwrap(model.reviewState.session?.id)
        let related = try model.prepareReviewRun(finding: puzzle.reviewFinding, puzzle: puzzle,
            linkedTargetID: "session-target", sessionID: sessionID)
        XCTAssertEqual(model.reviewState.session?.activeRelatedRunID, related.id)
        XCTAssertEqual(model.reviewState.standalonePractice?.runID, direct.id)
        let returning = try model.prepareReviewRun(finding: puzzle.reviewFinding, puzzle: puzzle,
            linkedTargetID: "return-target", returnGameID: "source-game", parentRunID: "parent-run")
        XCTAssertEqual(model.reviewState.standalonePractice?.runID, returning.id)
        XCTAssertEqual(model.reviewState.standalonePractice?.returnGameID, "source-game")
        XCTAssertEqual(model.reviewState.standalonePractice?.parentRunID, "parent-run")
        XCTAssertEqual(model.reviewState.session?.activeRelatedRunID, related.id)
    }

}
