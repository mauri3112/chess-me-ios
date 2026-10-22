import Foundation
import Testing
@testable import ChessMeCore

@Suite(.serialized)
struct ReviewExperienceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func finding(_ board: ChessPosition, line: [String], id: String = "lesson", gameID: String = "game") -> MoveFinding {
        MoveFinding(id: id, gameID: gameID, gameLabel: "Learner vs Partner", positionFEN: board.fen,
                    playedMove: board.legalMoves().first?.uci ?? line[0], bestMove: line[0], acceptedMoves: [line[0]],
                    continuation: line, centipawnLoss: 180, theme: "A supported lesson", explanation: "Inspect the line.",
                    hint: "Look at the threats.", moveNumber: board.fullmoveNumber, source: "device", isPuzzle: true)
    }
    private func evaluation(_ board: ChessPosition, line: [String], score: Int = 300, other: (String, Int)? = nil,
                            depth: Int = 12) throws -> PositionEvaluation {
        var values = [MoveEvaluation(move: try ChessMove(uci: line[0]), score: score, continuation: try line.map(ChessMove.init(uci:)))]
        if let other { values.append(MoveEvaluation(move: try ChessMove(uci: other.0), score: other.1,
                                                    continuation: [try ChessMove(uci: other.0)])) }
        return PositionEvaluation(moves: values.sorted { $0.score > $1.score }, completedDepth: depth, nodes: 10_000)
    }
    private func plan(quality: MoveQuality = .best, id: String = "plan", date: Date? = nil) throws -> (ChessGame, GameAnalysis, ReviewJourney) {
        let game = ChessGame(id: id, username: "Learner", white: "Learner", black: "Partner", playedAt: date ?? now,
                             playerSide: .white, moves: "d4e5 g8f7 a1d1",
                             initialFEN: "6k1/8/8/4p3/3P4/8/8/R5K1 w - - 0 1", status: "resign", timestampIsExact: true)
        let replay = try GameReplay(game: game)
        let assessments = [0, 2].map { ply in
            MoveAssessment(ply: ply, positionFEN: replay.positions[ply].fen, playedMove: replay.moves[ply].uci,
                           bestMove: replay.moves[ply].uci, quality: ply == 2 ? quality : .best,
                           centipawnLoss: ply == 2 && quality == .blunder ? 500 : 0, whiteScore: 600,
                           completedDepth: 12, isProvisional: true)
        }
        let review = GameAnalysis(gameID: id, findings: [], analyzedPlies: 2, totalPlies: 2, completedAt: now,
                                  engineVersion: "reference-fixture", moveAssessments: assessments)
        return (game, review, ReviewJourney(game: game, analysis: review))
    }

    @Test func savedLinesKeepExactPrefixAndOpeningAndDoNotSaveOnExploration() throws {
        let game = ChessGame(id: "saved-game", username: "Learner", white: "Learner", black: "Partner", playedAt: now,
                             playerSide: .white, moves: "e4 e5 Nf3 Nc6 Bb5 a6", status: "resign")
        var replay = try GameReplay(game: game), library = ReviewLibrary()
        #expect(throws: ChessError.self) { try SavedReviewLine(game: game, replay: replay) }
        replay.navigate(to: 4)
        try replay.play(ChessMove(uci: "f1b5"))
        #expect(library.savedLines.isEmpty)
        let line = try SavedReviewLine(game: game, replay: replay, now: now)
        library.save(line); library.save(line)
        #expect(library.savedLines.count == 1)
        #expect(line.repetitionHistory.count == 4 && line.prefix.count == 4)
        #expect(line.opening?.contains("Ruy Lopez") == true)
        #expect(line.matches(search: "Ruy", side: .white) && !line.matches(search: "Ruy", side: .black))
        #expect(try GameReplay(game: line.replayGame()).positions.last == replay.position)
        try replay.play(ChessMove(uci: "a7a6"))
        #expect(try SavedReviewLine(game: game, replay: replay).id != line.id)
        #expect(OpeningFamily.name(for: nil) == "Unclassified opening")
        #expect(OpeningFamily.name(for: "Sicilian Defense: Najdorf Variation") == "Sicilian Defense")
    }

    @Test func plansConnectActualDecisionsAndRejectAnUnsupportedPositiveLabel() throws {
        let (_, _, good) = try plan()
        let sequence = try #require(good.moments.first { $0.kind == .plan })
        #expect(sequence.plies == [0, 2] && sequence.keyLine == ["d4e5", "g8f7", "a1d1"])
        #expect(sequence.finding.isPuzzle && sequence.explanation.contains("d-file"))
        #expect(good.mainTakeawayID == sequence.id)
        let (_, _, mistimed) = try plan(quality: .blunder)
        let bad = try #require(mistimed.moments.first { $0.kind == .plan })
        #expect(!bad.finding.isPuzzle && bad.finding.quality == .blunder)
        #expect(bad.explanation.contains("lost value"))
        #expect(good.moments.map { $0.plies[0] } == good.moments.map { $0.plies[0] }.sorted())
    }

    @Test func revisionIncludesEvidenceEvenIfTheCompletionTimestampDoesNotChange() throws {
        let (game, original, _) = try plan()
        let changed = GameAnalysis(gameID: original.gameID, findings: [], analyzedPlies: 1, totalPlies: 2,
                                   completedAt: original.completedAt, engineVersion: original.engineVersion,
                                   moveAssessments: Array((original.moveAssessments ?? []).prefix(1)))
        #expect(ReviewJourney(game: game, analysis: original).revision != ReviewJourney(game: game, analysis: changed).revision)
        let (_, _, same) = try plan()
        let updated = GameAnalysis(gameID: original.gameID, findings: [], analyzedPlies: 2, totalPlies: 2,
                                    completedAt: now.addingTimeInterval(60), engineVersion: original.engineVersion,
                                    moveAssessments: original.moveAssessments)
        #expect(same.moments.first?.evidenceRevision == ReviewJourney(game: game, analysis: updated).moments.first?.evidenceRevision)
        #expect(ReviewJourney(game: game, analysis: nil).moments.isEmpty)
    }

    @Test func soundOwnAlternativeIsNotRejectedForBeingAbsentFromCachedPV() throws {
        let board = ChessPosition.initial, e4 = try ChessMove(uci: "e2e4"), d4 = try ChessMove(uci: "d2d4")
        let incomplete = try evaluation(board, line: [e4.uci], score: 30)
        if case .ungraded = ReviewMoveAcceptance.judge(move: d4, position: board, evaluation: incomplete) {} else { Issue.record("Missing candidate must remain ungraded") }
        let verified = try evaluation(board, line: [e4.uci], score: 30, other: (d4.uci, 20))
        if case .accepted(let line) = ReviewMoveAcceptance.judge(move: d4, position: board, evaluation: verified) { #expect(line == [d4.uci]) }
        else { Issue.record("An independently evaluated sound alternative must be accepted") }
        let shallow = try evaluation(board, line: [d4.uci], depth: 2)
        if case .ungraded = ReviewMoveAcceptance.judge(move: d4, position: board, evaluation: shallow) {} else { Issue.record("Insufficient depth must be ungraded") }
    }

    @Test func everyLegallyProvenImmediateMateIsAcceptedWithoutAnEnginePV() throws {
        let board = try ChessPosition(fen: "7k/5K2/8/6Q1/8/8/8/8 w - - 1 2")
        let mates = try board.legalMoves().filter { try board.applying($0).outcome() == .checkmate(winner: .white) }
        #expect(mates.count > 1)
        let empty = PositionEvaluation(moves: [], completedDepth: 0, nodes: 0)
        for move in mates {
            if case .accepted = ReviewMoveAcceptance.judge(move: move, position: board, evaluation: empty) {} else { Issue.record("A legal mating alternative was rejected") }
        }
    }

    @Test func pinnedNonMatingPuzzleAcceptsItsWholeLineWithoutFreshAnalysis() throws {
        let setup = try ChessPosition(fen: "6k1/7p/2p5/3q4/8/5Q2/8/RR1R2K1 b - - 0 1")
        let root = try setup.applying(ChessMove(uci: "h7h6"))
        let puzzle = TrainingPuzzle(id: "stored-exchange", setupFEN: setup.fen, setupMove: "h7h6", positionFEN: root.fen,
                                    solution: ["d1d5", "c6d5", "f3d5"], rating: 1600, themes: ["advantage"],
                                    url: URL(string: "https://lichess.org/training/stored-exchange")!)
        var run = try AdaptiveReviewRun(finding: puzzle.reviewFinding, revision: "pinned", kind: .relatedPuzzle,
                                        puzzleID: puzzle.id, puzzle: puzzle)
        #expect(!run.requiresMate && run.requiredDecisions == 2)
        let storedDecision1 = !run.submitStoredMove(try ChessMove(uci: "a1a2"))
        #expect(storedDecision1)
        #expect(run.acceptedMoves.isEmpty)
        let storedDecision2 = run.submitStoredMove(try ChessMove(uci: "d1d5"))
        #expect(storedDecision2)
        #expect(run.pendingReply == "c6d5" && !run.isFinished)
        run.playReply()
        run = try JSONDecoder().decode(AdaptiveReviewRun.self, from: JSONEncoder().encode(run))
        let storedDecision3 = run.submitStoredMove(try ChessMove(uci: "f3d5"))
        #expect(storedDecision3)
        #expect(run.attempt.outcome == .completed && run.attempt.cleanCompletion)
        #expect(run.acceptedMoves == puzzle.solution && run.pendingReply == nil)
    }

    @Test func storedGameAnswersRequireMatchingDepthAndAcceptThePinnedEndpoint() throws {
        let (_, _, journey) = try plan()
        let item = try #require(journey.moments.first { $0.kind == .plan })
        var run = try AdaptiveReviewRun(finding: item.finding, revision: "pinned")
        let move = try ChessMove(uci: "d4e5")
        let storedDecision4 = !run.submitStoredMove(move)
        #expect(storedDecision4)
        let storedDecision5 = !run.submitStoredMove(move, verifiedDepth: 5)
        #expect(storedDecision5)
        let storedDecision6 = run.submitStoredMove(move, verifiedDepth: 12)
        #expect(storedDecision6)
        run.playReply()
        let storedDecision7 = run.submitStoredMove(try ChessMove(uci: "a1d1"), verifiedDepth: 12)
        #expect(storedDecision7)
        #expect(run.acceptedDecisions == 2 && run.isFinished)
    }

    @Test func revealedAndAcceptedContinuationsStaySeparateFromAttemptCreditInExplore() throws {
        let puzzle = LearningTests.puzzle
        var run = try AdaptiveReviewRun(finding: puzzle.reviewFinding, revision: "pinned", kind: .relatedPuzzle,
                                        puzzleID: puzzle.id, puzzle: puzzle)
        let storedDecision8 = run.submitStoredMove(try ChessMove(uci: puzzle.solution[0]))
        #expect(storedDecision8)
        run.playReply()
        let prefix = run.acceptedMoves
        run.reviewAnswer()
        let replay = try GameReplay(game: run.explorationGame())
        #expect(replay.moves.map(\.uci) == [puzzle.setupMove] + puzzle.solution)
        #expect(run.acceptedMoves == prefix && run.attempt.outcome == .revealed)
        let (_, _, journey) = try plan()
        let item = try #require(journey.moments.first { $0.kind == .plan })
        var gameRun = try AdaptiveReviewRun(finding: item.finding, revision: "pinned")
        gameRun.reviewAnswer()
        #expect(try GameReplay(game: gameRun.explorationGame()).moves.map(\.uci) == item.keyLine)
        #expect(gameRun.acceptedMoves.isEmpty && !gameRun.attempt.cleanCompletion)
    }

    @Test func pendingReplyRoundTripsAndCannotBePlayedTwice() throws {
        let puzzle = LearningTests.puzzle
        let board = try ChessPosition(fen: puzzle.positionFEN)
        var run = try AdaptiveReviewRun(finding: puzzle.reviewFinding, revision: "r", history: [try ChessPosition(fen: puzzle.setupFEN).repetitionKey], kind: .relatedPuzzle)
        run.submit(try ChessMove(uci: puzzle.solution[0]), evaluation: try evaluation(board, line: puzzle.solution, score: 99_997))
        #expect(!run.isFinished && run.acceptedDecisions == 1 && run.pendingReply == "d7d8")
        run = try JSONDecoder().decode(AdaptiveReviewRun.self, from: JSONEncoder().encode(run))
        run.playReply(); let after = run
        run.playReply()
        #expect(run == after && run.acceptedMoves == ["a2e6", "d7d8"])
        #expect(run.history.count == 3)
        let mate = try ChessMove(uci: "f7f8")
        run.submit(mate, evaluation: PositionEvaluation(moves: [], completedDepth: 0, nodes: 0))
        #expect(run.attempt.outcome == .completed && run.acceptedDecisions == 2)
    }

    @Test func alternateWinningMateFollowsItsOwnBranchUntilTheActualMate() throws {
        let root = try ChessPosition(fen: "7k/5K2/8/6Q1/8/8/8/8 w - - 1 2")
        var run = try AdaptiveReviewRun(finding: finding(root, line: ["g5g7"]), revision: "mate")
        let result = try evaluation(root, line: ["g5f6", "h8h7", "f6g7"], score: 99_997, other: ("g5g7", 99_999))
        run.submit(try ChessMove(uci: "g5f6"), evaluation: result)
        #expect(!run.isFinished && run.pendingReply == "h8h7")
        run.playReply()
        run.submit(try ChessMove(uci: "f6g7"), evaluation: PositionEvaluation(moves: [], completedDepth: 0, nodes: 0))
        #expect(run.attempt.outcome == .completed && run.acceptedMoves == ["g5f6", "h8h7", "f6g7"])
    }

    @Test func planPracticeIncludesItsFollowUpAndPreservesAcceptedPrefixOnMistake() throws {
        let (_, _, journey) = try plan()
        let item = try #require(journey.moments.first { $0.kind == .plan })
        var run = try AdaptiveReviewRun(finding: item.finding, revision: journey.revision)
        #expect(run.requiredDecisions == 2 && run.goal == .openFile(3))
        run.submit(try ChessMove(uci: "d4e5"), evaluation: try evaluation(run.position, line: item.keyLine))
        #expect(!run.isFinished)
        run.playReply()
        let before = run.currentFEN, prefix = run.acceptedMoves
        let wrong = try ChessMove(uci: "a1a2")
        let rejected = PositionEvaluation(moves: [
            MoveEvaluation(move: try ChessMove(uci: "a1d1"), score: 600, continuation: [try ChessMove(uci: "a1d1")]),
            MoveEvaluation(move: wrong, score: 0, continuation: [wrong, try ChessMove(uci: "f7g6")])
        ], completedDepth: 12, nodes: 1000)
        run.submit(wrong, evaluation: rejected)
        #expect(run.attempt.hasMistake && run.currentFEN == before && run.acceptedMoves == prefix)
        run.requestHelp(.counterline)
        #expect(run.currentFEN == before && run.acceptedMoves == prefix)
        run.submit(try ChessMove(uci: "a1d1"), evaluation: try evaluation(run.position, line: ["a1d1", "f7g6"], score: 600))
        #expect(!run.isFinished && run.pendingReply == "f7g6")
        run.playReply()
        #expect(run.isFinished && run.attempt.outcome == .completed && !run.attempt.cleanCompletion)
    }

    @Test func transientCaptureDoesNotCompleteBeforeTheRequiredRecapture() throws {
        let root = try ChessPosition(fen: "6k1/7p/2p5/3q4/8/5Q2/8/RR1R2K1 w - - 0 1")
        var run = try AdaptiveReviewRun(finding: finding(root, line: ["d1d5", "c6d5", "f3d5"]), revision: "capture")
        #expect(run.goal == .materialGain(500) && run.requiredDecisions == 2)
        run.submit(try ChessMove(uci: "a1a2"), evaluation: try evaluation(root, line: ["a1a2", "h7h6", "f3d5", "c6d5"], score: 1000))
        run.playReply()
        run.submit(try ChessMove(uci: "f3d5"), evaluation: try evaluation(run.position, line: ["f3d5", "c6d5"], score: 1000))
        #expect(!run.isFinished && run.pendingReply == "c6d5")
        run.playReply()
        #expect(!run.isFinished && run.attempt.outcome == .inProgress)
    }

    @Test func cachedAlternativeEndpointDoesNotCompleteAnUnmetGoal() throws {
        let root = try ChessPosition(fen: "6k1/7p/2p5/3q4/8/5Q2/8/RR1R2K1 w - - 0 1")
        var run = try AdaptiveReviewRun(finding: finding(root, line: ["d1d5", "c6d5", "f3d5"]), revision: "alternate-endpoint")
        #expect(run.goal == .materialGain(500))
        run.submit(try ChessMove(uci: "a1a2"), evaluation: try evaluation(root, line: ["a1a2", "h7h6", "b1b2"], score: 1000))
        run.playReply()
        #expect(run.submitStoredMove(try ChessMove(uci: "b1b2")))
        #expect(run.attempt.decisions.last?.grade == .accepted)
        #expect(run.attempt.outcome == .ungraded, "A cached move grade does not establish the source's material goal.")
    }

    @Test func neuralBudgetsAndIdentityHonorTheSelectedLongReview() {
        let maximum = AnalysisOptions(maximumDepth: 32, memoryMegabytes: 128, timeLimitSeconds: 180,
                                      engine: .arasan, searchNodeLimit: 100_000_000, engineThreads: 2)
        #expect(maximum.memoryMegabytes == 128 && maximum.timeLimitSeconds == 180 && maximum.engineThreads == 1)
        let smaller = AnalysisOptions(maximumDepth: 32, memoryMegabytes: 128, timeLimitSeconds: 180,
                                      engine: .arasan, searchNodeLimit: 20_000_000)
        #expect(maximum.configurationID != smaller.configurationID)
    }

    @Test func relatedMatchingRequiresAConcreteMechanismAndLegalSetup() throws {
        let setup = try ChessPosition(fen: "6k1/5ppp/8/8/8/8/8/4R1K1 b - - 0 1")
        let root = try setup.applying(ChessMove(uci: "g8h8"))
        let proof = try #require(ReviewLineProof(position: root, moves: ["e1e8"]))
        let idea = try #require(ReviewIdeaProof.identify(proof))
        #expect(idea.key == "back-rank-mate")
        let sourceRoot = try ChessPosition(fen: "7k/5ppp/8/8/8/8/8/R5K1 w - - 1 2")
        let f = finding(sourceRoot, line: ["a1a8"])
        let moment = ReviewMoment(id: f.id, finding: f, kind: .improvement, plies: [0], ideaKey: idea.key,
                                  keyLine: ["a1a8"], explanation: idea.explanation)
        let matching = TrainingPuzzle(id: "backrank", setupFEN: setup.fen, setupMove: "g8h8", positionFEN: root.fen,
                                      solution: proof.moves, rating: 1200, themes: ["unrelated-tag"], url: URL(string: "https://lichess.org/training/backrank")!)
        #expect(ReviewPuzzleConnection.match(puzzle: matching, moment: moment) != nil)
        let repeated = ReviewMoment(id: f.id, finding: finding(root, line: proof.moves), kind: .improvement,
                                    plies: [0], ideaKey: idea.key, keyLine: proof.moves, explanation: idea.explanation)
        #expect(ReviewPuzzleConnection.match(puzzle: matching, moment: repeated) == nil)
        #expect(ReviewPuzzleConnection.match(puzzle: LearningTests.puzzle, moment: moment) == nil)
        let generic = ReviewMoment(id: f.id, finding: f, kind: .improvement, plies: [0], ideaKey: "mate", keyLine: proof.moves, explanation: "Mate")
        #expect(ReviewPuzzleConnection.match(puzzle: matching, moment: generic) == nil)
        let malformed = TrainingPuzzle(id: "bad", setupFEN: setup.fen, setupMove: "g8h8", positionFEN: root.fen,
                                       solution: ["e1e9"], rating: 1200, themes: ["backRankMate"], url: matching.url)
        #expect(ReviewPuzzleConnection.match(puzzle: malformed, moment: moment) == nil)
    }

    @Test func forkPayoffMustWinAnAttackedTargetAfterTheReply() throws {
        let real = try ChessPosition(fen: "8/8/4k3/5q2/8/5N2/8/R3K3 w - - 0 1")
        let realLine = try #require(ReviewLineProof(position: real, moves: ["f3d4", "e6d6", "d4f5"]))
        #expect(ReviewIdeaProof.identify(realLine)?.key == "fork-knight")
        // Capturing a hanging queen before being captured is not a demonstrated
        // fork payoff, even though the knight briefly attacks both rooks.
        let falseFork = try ChessPosition(fen: "4k3/8/1rp2r2/3q4/8/2N5/8/4K3 w - - 0 1")
        let line = try #require(ReviewLineProof(position: falseFork, moves: ["c3d5", "c6d5"]))
        #expect(ReviewIdeaProof.identify(line)?.key == "material-gain")
    }

    @Test func deeperReferenceDistinguishesSoundAndRefutedRookActivation() throws {
        // Independently selected chess positions. Stockfish runs only in the
        // host test process; the native app uses Arasan and excludes this engine.
        let engine = LocalAnalyzer(options: AnalysisOptions(maximumDepth: 15, memoryMegabytes: 16,
            timeLimitSeconds: 3, engine: .stockfish, searchNodeLimit: 1_000_000))
        for (fen, shouldAccept) in [
            ("r5k1/7p/8/4p3/3P4/8/7P/5RK1 w - - 0 1", true),
            ("r5k1/7p/8/4p3/3P4/1b6/7P/5RK1 w - - 0 1", false)
        ] {
            var board = try ChessPosition(fen: fen), history: [String] = []
            for token in ["d4e5", "a8a2"] { history.append(board.repetitionKey); board = try board.applying(ChessMove(uci: token)) }
            let move = try ChessMove(uci: "f1d1")
            let result = try engine.evaluate(position: board, repetitionHistory: history, requiredMove: move)
            #expect(result.completedDepth >= 6)
            switch ReviewMoveAcceptance.judge(move: move, position: board, evaluation: result) {
            case .accepted: #expect(shouldAccept)
            case .mistake(_, let counterline):
                #expect(!shouldAccept)
                #expect(counterline.dropFirst().first == "b3d1")
            case .ungraded: Issue.record("The deeper reference case should provide a supported verdict")
            }
        }
    }

    @Test func delayedRecallSchedulingIsDerivedFromFactsAndDuplicateSavesAreIdempotent() throws {
        let board = ChessPosition.initial, f = finding(board, line: ["e2e4"])
        var state = ReviewLibrary()
        state.enroll(ReviewLearningTarget(username: "Learner", finding: f, revision: "r", history: [], ideaKey: nil, now: now))
        state.expose(f.id, kind: .line, now: now)
        func completed(at start: Date, help: Bool = false) -> ReviewPracticeAttempt {
            var a = ReviewPracticeAttempt(targetID: f.id, evidenceRevision: "r", rootFEN: board.fen, now: start)
            a.decisions = [ReviewDecision(positionFEN: board.fen, move: "e2e4", grade: .accepted, date: start)]
            a.outcome = .completed; a.endedAt = start.addingTimeInterval(30)
            if help { a.help = [.hint] }
            return a
        }
        let immediate = completed(at: now.addingTimeInterval(60))
        state.record(immediate)
        #expect(!state.qualifiesForRecall(immediate))
        let later = completed(at: now.addingTimeInterval(2 * 86_400))
        state.record(later)
        #expect(state.qualifiesForRecall(later))
        var exposedDuringRun = state
        exposedDuringRun.expose(f.id, kind: .line, now: later.startedAt.addingTimeInterval(10))
        #expect(!exposedDuringRun.qualifiesForRecall(later))
        var rehearsal = state
        var unresolved = completed(at: later.startedAt.addingTimeInterval(300))
        unresolved.outcome = .ungraded
        rehearsal.record(unresolved)
        let retry = completed(at: later.startedAt.addingTimeInterval(360))
        rehearsal.record(retry)
        #expect(!rehearsal.qualifiesForRecall(retry))
        #expect(state.targets[0].dueAt == later.endedAt!.addingTimeInterval(3 * 86_400))
        let due = state.targets[0].dueAt
        state.record(later); #expect(state.attempts.count == 2 && state.targets[0].dueAt == due)
        let assisted = completed(at: now.addingTimeInterval(6 * 86_400), help: true)
        state.record(assisted)
        #expect(!state.qualifiesForRecall(assisted))
        #expect(state.targets[0].dueAt == assisted.endedAt!.addingTimeInterval(86_400))
        var skipped = completed(at: now.addingTimeInterval(8 * 86_400)); skipped.outcome = .skipped; skipped.decisions = []
        state.record(skipped)
        #expect(state.targets[0].dueAt == assisted.endedAt!.addingTimeInterval(86_400))
        let restored = try JSONDecoder().decode(ReviewLibrary.self, from: JSONEncoder().encode(state))
        #expect(restored.attempts == state.attempts && restored.targets == state.targets)
        #expect(try JSONDecoder().decode(ReviewLibrary.self, from: Data("{}".utf8)).attempts.isEmpty)
    }

    @Test func transferEvidenceNeedsAVerifiedParentRevisionAndFreshFullAttempt() throws {
        let f = finding(.initial, line: ["e2e4"])
        var library = ReviewLibrary()
        library.enroll(ReviewLearningTarget(username: "Learner", finding: f, revision: "current", history: [], ideaKey: "back-rank-mate", now: now))
        var attempt = ReviewPracticeAttempt(targetID: f.id, kind: .relatedPuzzle, puzzleID: "external",
                                            evidenceRevision: "puzzle-r", rootFEN: ChessPosition.initial.fen, now: now)
        attempt.outcome = .completed; attempt.endedAt = now.addingTimeInterval(30)
        attempt.decisions = [ReviewDecision(positionFEN: attempt.rootFEN, move: "e2e4", grade: .accepted)]
        #expect(!library.qualifiesForRelatedEvidence(attempt))
        attempt.linkedLessonRevision = "current"
        #expect(library.qualifiesForRelatedEvidence(attempt))
        attempt.knownSeenBefore = true
        #expect(!library.qualifiesForRelatedEvidence(attempt))
        attempt.knownSeenBefore = false; library.targets[0].invalidated = true
        #expect(!library.qualifiesForRelatedEvidence(attempt))
    }

    @Test func revisedLessonKeepsManualControlWithoutPromotingOldAttempts() throws {
        let f = finding(.initial, line: ["e2e4"])
        var state = ReviewLibrary()
        var old = ReviewLearningTarget(username: "Learner", finding: f, revision: "old", history: [], ideaKey: nil, now: now)
        old.kept = true; old.dismissed = true; old.invalidated = true
        state.enroll(old)
        let revised = ReviewLearningTarget(username: "Learner", finding: f, revision: "new", history: [], ideaKey: nil, now: now.addingTimeInterval(500))
        state.enroll(revised)
        #expect(state.targets.count == 1 && state.targets[0].revision == "new")
        #expect(state.targets[0].kept && state.targets[0].dismissed && !state.targets[0].invalidated)
    }

    @Test func laterGameConnectionsUseRealChronologyAndWorstPlanDecision() throws {
        let (original, _, source) = try plan()
        let moment = try #require(source.moments.first { $0.kind == .plan })
        let target = ReviewLearningTarget(username: original.username, finding: moment.finding, revision: source.revision,
                                          history: [], ideaKey: moment.ideaKey, now: now)
        let (later, _, good) = try plan(id: "later", date: now.addingTimeInterval(500))
        let observations = ReviewGameConnections.observations(game: later, journey: good, targets: [target])
        #expect(observations.count == 1 && observations[0].kind == .soundChoice)
        let (badGame, _, bad) = try plan(quality: .blunder, id: "bad-later", date: now.addingTimeInterval(600))
        #expect(ReviewGameConnections.observations(game: badGame, journey: bad, targets: [target]).first?.kind == .missedOpportunity)
        #expect(ReviewGameConnections.observations(game: original, journey: source, targets: [target]).isEmpty)
        let (older, _, oldJourney) = try plan(id: "old-import", date: now.addingTimeInterval(-500))
        #expect(ReviewGameConnections.observations(game: older, journey: oldJourney, targets: [target]).isEmpty)
        let uncertain = ChessGame(id: "pgn-unknown", username: "Learner", white: "Learner", black: "Partner",
                                  playedAt: now.addingTimeInterval(600), playerSide: .white, moves: later.moves,
                                  initialFEN: later.initialFEN, status: "resign", timestampIsExact: false)
        #expect(ReviewGameConnections.observations(game: uncertain, journey: good, targets: [target]).isEmpty)
    }

    @Test func boundedSessionsDiversityAndAccountDeletionKeepExplicitLinesSeparate() throws {
        var state = ReviewLibrary()
        for i in 0..<8 {
            var target = ReviewLearningTarget(username: i == 7 ? "Other" : "Learner", finding: finding(.initial, line: ["e2e4"], id: "t\(i)"),
                                               revision: "r", history: [], ideaKey: "idea\(i % 4)", now: now)
            target.dueAt = now; state.enroll(target)
        }
        let set = state.suggestedSet(now: now)
        #expect(set.count == 3 && Set(set.compactMap(\.ideaKey)).count == 3)
        state.targets[0].dismissed = true; state.targets[1].deferredUntil = now.addingTimeInterval(300)
        #expect(!state.suggestedSet(now: now).contains { $0.id == "t0" || $0.id == "t1" })
        state.removeAccount("Learner", gameIDs: [])
        #expect(state.targets.count == 1 && state.targets[0].username == "Other")
    }
}
