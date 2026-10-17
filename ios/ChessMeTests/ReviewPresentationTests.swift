import XCTest
import ChessMeCore
@testable import ChessMe

final class ReviewPresentationTests: XCTestCase {
    private var savedOvernightPreferences: Data?
    override func setUpWithError() throws {
        try super.setUpWithError()
        savedOvernightPreferences = UserDefaults.standard.data(forKey: "analysis.overnight.settings")
        UserDefaults.standard.removeObject(forKey: "analysis.overnight.settings")
    }
    override func tearDownWithError() throws {
        if let savedOvernightPreferences { UserDefaults.standard.set(savedOvernightPreferences, forKey: "analysis.overnight.settings") }
        else { UserDefaults.standard.removeObject(forKey: "analysis.overnight.settings") }
        try super.tearDownWithError()
    }
    private func completeJob(game: ChessGame, configuration: DeviceEngineConfiguration) throws -> LocalAnalysisJob {
        let analysis = try LocalAnalyzer(options: AnalysisOptions(maximumDepth: 1)).analyze(game: game)
        let review = GameAnalysis(gameID: game.id, findings: analysis.findings, analyzedPlies: analysis.analyzedPlies,
            totalPlies: analysis.totalPlies, engineVersion: StockfishEngine.version,
            configurationID: configuration.options.configurationID, moveAssessments: analysis.moveAssessments)
        var job = LocalAnalysisJob(gameID: game.id, configuration: configuration, level: .balanced, nightOnly: true)
        job.checkpoint = review; job.state = .completed
        return job
    }

    @MainActor
    func testRestoredCompleteCheckpointIsVisibleAndDoesNotOfferAnotherAnalysis() throws {
        let game = try XCTUnwrap(DemoContent.games().first)
        let empty = AppModel(previewLibrary: LibrarySnapshot())
        let configuration = empty.deepConfiguration(.maximum)
        var job = try completeJob(game: game, configuration: configuration)
        job.state = .running; job.message = "Waiting for tonight"
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], isDemo: true, localAnalysisJobs: [job]))
        let coordinator = DeviceAnalysisCoordinator(model: model, schedulerEnabled: false)
        defer { coordinator.pause() }
        XCTAssertTrue(model.gameAnalysis(for: game.id)?.isComplete == true)
        XCTAssertEqual(model.localAnalysisJob(for: game.id)?.state, .completed)
        XCTAssertEqual(model.localAnalysisJob(for: game.id)?.statusText, "Review ready")
        XCTAssertNil(model.deviceReviewAction(for: game.id))
        XCTAssertFalse(model.isAnalyzing)
    }

    @MainActor
    func testCachedCompleteReviewIsNotScheduledAgainByOvernightPreferences() throws {
        let game = try XCTUnwrap(DemoContent.games().first)
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], isDemo: true))
        let configuration = model.deepConfiguration(.balanced)
        let job = try completeJob(game: game, configuration: configuration)
        model.updateLibrary { $0.localAnalysisJobs = [job]; $0.analyses = [job.checkpoint!] }
        model.overnightSettings.enabled = true
        XCTAssertEqual(model.library.localAnalysisJobs?.count, 1)
        XCTAssertFalse(model.library.localAnalysisJobs?.first?.isPending ?? true)
        XCTAssertNil(model.deviceReviewAction(for: game.id))
        model.pauseAnalysis()
    }

    @MainActor
    func testBackgroundCompletionPublishesTheReviewAndKeepsDeeperWorkVisible() throws {
        let game = try XCTUnwrap(DemoContent.games().first)
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], isDemo: true))
        let balanced = try completeJob(game: game, configuration: model.deepConfiguration(.balanced))
        var deeper = LocalAnalysisJob(gameID: game.id, configuration: model.deepConfiguration(.deep), level: .deep, nightOnly: true)
        deeper.state = .running
        model.updateLibrary { $0.localAnalysisJobs = [balanced, deeper] }
        model.acceptDeviceCheckpoint(balanced.checkpoint!)
        XCTAssertEqual(model.localAnalysisJob(for: game.id)?.id, deeper.id)
        XCTAssertTrue(model.gameAnalysis(for: game.id)?.isComplete == true)
        XCTAssertNil(model.deviceReviewAction(for: game.id), "A running upgrade has progress rather than another analyze action")
        let done = try completeJob(game: game, configuration: deeper.configuration).checkpoint!
        model.updateLibrary { $0.localAnalysisJobs?[1].state = .completed; $0.localAnalysisJobs?[1].checkpoint = done }
        model.acceptDeviceCheckpoint(done)
        XCTAssertEqual(model.gameAnalysis(for: game.id)?.configurationID, done.configurationID)
        XCTAssertNil(model.deviceReviewAction(for: game.id))
        XCTAssertEqual(model.localAnalysisJob(for: game.id)?.statusText, "Review ready")
    }

    @MainActor
    func testLaterOrdinaryReviewCannotReplaceACompletedDeeperReview() throws {
        let game = try XCTUnwrap(DemoContent.games().first)
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], isDemo: true))
        let deep = try completeJob(game: game, configuration: model.deepConfiguration(.maximum))
        let ordinary = try completeJob(game: game, configuration: model.deepConfiguration(.balanced))
        model.updateLibrary { $0.localAnalysisJobs = [deep, ordinary]; $0.analyses = [deep.checkpoint!] }
        model.acceptDeviceCheckpoint(ordinary.checkpoint!)
        XCTAssertEqual(model.gameAnalysis(for: game.id)?.configurationID, deep.checkpoint?.configurationID)
    }

    @MainActor
    func testCompletedDeeperReviewClearsARedundantNightQueueImmediately() throws {
        let game = try XCTUnwrap(DemoContent.games().first)
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], isDemo: true))
        let deep = try completeJob(game: game, configuration: model.deepConfiguration(.maximum))
        let waiting = LocalAnalysisJob(gameID: game.id, configuration: model.deepConfiguration(.balanced), level: .balanced, nightOnly: true)
        model.updateLibrary { $0.localAnalysisJobs = [deep, waiting] }
        model.acceptDeviceCheckpoint(deep.checkpoint!)
        XCTAssertFalse(model.library.localAnalysisJobs?.contains(where: \.isPending) ?? true)
        XCTAssertEqual(model.localAnalysisJob(for: game.id)?.statusText, "Review ready")
        XCTAssertNil(model.deviceReviewAction(for: game.id))
    }

    func testExtremeGraphDotsAndHighlightRingsStayInsideThePlot() {
        let size = CGSize(width: 300, height: 90)
        let layout = EvaluationTimelineGeometry(size: size, totalPlies: 9)
        func assessment(ply: Int, score: Int) -> MoveAssessment {
            MoveAssessment(ply: ply, positionFEN: ChessPosition.initial.fen, playedMove: "e2e4", bestMove: "e2e4",
                           quality: .blunder, centipawnLoss: 1_000, whiteScore: score, completedDepth: 20, isProvisional: true)
        }
        let values = [assessment(ply: 0, score: 100_000), assessment(ply: 8, score: -100_000)]
        for value in values {
            let point = layout.point(for: value)
            XCTAssertGreaterThanOrEqual(point.x - 7.5, 0)
            XCTAssertLessThanOrEqual(point.x + 7.5, size.width)
            XCTAssertGreaterThanOrEqual(point.y - 7.5, 0)
            XCTAssertLessThanOrEqual(point.y + 7.5, size.height)
        }
        XCTAssertEqual(layout.nearest(to: 300, assessments: values)?.ply, 8)
        XCTAssertEqual(layout.nearest(to: 0, assessments: values)?.ply, 0)
    }

    private func legacyOpeningReview(game: ChessGame, configuration: DeviceEngineConfiguration, source: String = "device") throws -> GameAnalysis {
        let replay = try GameReplay(game: game)
        let assessments = [0, 2].map { ply in
            MoveAssessment(ply: ply, positionFEN: replay.positions[ply].fen, playedMove: replay.moves[ply].uci,
                           bestMove: ply == 0 ? "d2d4" : "g1f3", quality: .mistake, centipawnLoss: 200,
                           whiteScore: 200, completedDepth: 24, isProvisional: true)
        }
        let findings = assessments.map { value in
            MoveFinding(id: "\(game.id)-\(value.ply)", gameID: game.id, gameLabel: game.label, positionFEN: value.positionFEN,
                        playedMove: value.playedMove, bestMove: value.bestMove, acceptedMoves: [value.bestMove], continuation: [value.bestMove],
                        centipawnLoss: 200, theme: "Forcing moves", explanation: "Old engine label", hint: "Check",
                        moveNumber: replay.positions[value.ply].fullmoveNumber, source: source)
        }
        return GameAnalysis(gameID: game.id, findings: findings, analyzedPlies: 2, totalPlies: 2, source: source,
                            engineVersion: StockfishEngine.version, configurationID: configuration.options.configurationID, moveAssessments: assessments)
    }

    @MainActor
    func testRestoredBookMistakesAreCorrectedInCachedJobsHistoryAndRecommendations() throws {
        let game = ChessGame(id: "opening-restored", username: "Learner", white: "Learner", black: "Partner", playedAt: Date(),
                             playerSide: .white, moves: "e4 e5 h4 Nc6", status: "resign")
        let configuration = AppModel(previewLibrary: LibrarySnapshot()).deepConfiguration(.balanced)
        let review = try legacyOpeningReview(game: game, configuration: configuration)
        var job = LocalAnalysisJob(gameID: game.id, configuration: configuration, level: .balanced, nightOnly: true)
        job.state = .completed; job.checkpoint = review
        let practice = PracticeRecord(findingID: review.findings[0].id, correctCount: 3, failedCount: 1, dueAt: Date(), lastPracticedAt: Date())
        let recommendation = PuzzleRecommendationSet(gameID: game.id, analysisSignature: "old-mistake-labels", rating: 1200, matches: [], matchedAt: Date())
        let snapshot = LibrarySnapshot(games: [game], practice: [practice], isDemo: true,
            analysisHistory: [try legacyOpeningReview(game: game, configuration: configuration, source: "cloud")],
            favoriteFindings: [review.findings[0]], puzzleRecommendations: [recommendation], localAnalysisJobs: [job])
        let model = AppModel(previewLibrary: snapshot)
        model.reconcileLocalAnalysisResults()
        let result = try XCTUnwrap(model.gameAnalysis(for: game.id))
        XCTAssertEqual(result.moveAssessments?.map(\.quality), [.book, .mistake])
        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertEqual(result.completedAt, review.completedAt)
        XCTAssertEqual(result.configurationID, review.configurationID)
        XCTAssertEqual(model.library.analysisHistory?.first?.moveAssessments?.first?.quality, .book)
        XCTAssertTrue(model.library.puzzleRecommendations?.isEmpty == true)
        XCTAssertTrue(model.favoriteFindings.isEmpty)
        XCTAssertEqual(model.library.favoriteFindings?.first?.id, review.findings[0].id, "Saved bookmarks remain recoverable")
        XCTAssertEqual(model.library.practice.first?.correctCount, 3)
        XCTAssertEqual(model.localAnalysisJob(for: game.id)?.state, .completed)
        XCTAssertNil(model.deviceReviewAction(for: game.id))
    }

    @MainActor
    func testIncomingCloudReviewUsesBookLabelsAndKeepsSourceAndRemainingMistake() throws {
        let game = ChessGame(id: "opening-cloud", username: "Learner", white: "Learner", black: "Partner", playedAt: Date(),
                             playerSide: .white, moves: "e4 e5 h4 Nc6", status: "resign")
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], isDemo: true))
        let review = try legacyOpeningReview(game: game, configuration: model.deepConfiguration(.balanced), source: "cloud")
        model.acceptDeviceCheckpoint(review)
        XCTAssertEqual(model.gameAnalysis(for: game.id)?.source, "cloud")
        XCTAssertEqual(model.gameAnalysis(for: game.id)?.moveAssessments?.first?.quality, .book)
        XCTAssertTrue(model.findings.isEmpty)
    }

    @MainActor
    func testOpeningCorrectionDoesNotCompleteAPartialCheckpoint() throws {
        let game = ChessGame(id: "opening-partial", username: "Learner", white: "Learner", black: "Partner", playedAt: Date(),
                             playerSide: .white, moves: "e4 e5 h4 Nc6", status: "resign")
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], isDemo: true))
        let configuration = model.deepConfiguration(.balanced)
        let saved = try legacyOpeningReview(game: game, configuration: configuration)
        let partial = GameAnalysis(gameID: game.id, findings: Array(saved.findings.prefix(1)), analyzedPlies: 1, totalPlies: 2,
            completedAt: saved.completedAt, engineVersion: saved.engineVersion, configurationID: saved.configurationID,
            moveAssessments: Array(saved.moveAssessments!.prefix(1)))
        var job = LocalAnalysisJob(gameID: game.id, configuration: configuration, level: .balanced, nightOnly: true)
        job.state = .running; job.checkpoint = partial
        model.updateLibrary { $0.localAnalysisJobs = [job] }
        XCTAssertEqual(model.gameAnalysis(for: game.id)?.moveAssessments?.first?.quality, .book)
        XCTAssertEqual(model.gameAnalysis(for: game.id)?.analyzedPlies, 1)
        XCTAssertFalse(model.gameAnalysis(for: game.id)?.isComplete ?? true)
        XCTAssertEqual(model.localAnalysisJob(for: game.id)?.state, .running)
    }
}
