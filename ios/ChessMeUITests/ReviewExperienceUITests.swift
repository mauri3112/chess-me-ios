import XCTest

final class ReviewExperienceUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-engine", "--reset-evaluation", "--reset-local-analysis"]
        let now = Date().timeIntervalSinceReferenceDate
        let root = "r5k1/7p/8/4p3/3P4/8/7P/5RK1 w - - 0 1"
        let after = "6k1/7p/8/4P3/8/8/r6P/5RK1 w - - 1 2"
        let assessments: [[String: Any]] = [
            ["ply": 0, "positionFEN": root, "playedMove": "d4e5", "bestMove": "d4e5", "quality": "best",
             "centipawnLoss": 0, "whiteScore": 0, "completedDepth": 15, "isProvisional": true],
            ["ply": 2, "positionFEN": after, "playedMove": "f1d1", "bestMove": "f1d1", "quality": "excellent",
             "centipawnLoss": 19, "whiteScore": -1, "completedDepth": 15, "isProvisional": true]
        ]
        let fixture: [String: Any] = [
            "games": [["id": "demo-review-plan", "username": "Learner", "white": "Learner", "black": "Partner",
                       "playedAt": now - 60, "playerSide": "white", "moves": "d4e5 a8a2 f1d1", "initialFEN": root,
                       "status": "resign", "timestampIsExact": true]],
            "analyses": [["gameID": "demo-review-plan", "findings": [], "analyzedPlies": 2, "totalPlies": 2,
                          "source": "device", "completedAt": now, "engineVersion": "demonstration-reference", "moveAssessments": assessments]],
            "practice": [], "isDemo": true, "skippedGames": 0
        ]
        app.launchEnvironment["CHESSME_UI_TEST_LIBRARY"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launch()
    }
    override func tearDownWithError() throws { app.terminate(); app = nil }

    func testOverviewPlanStepOptionalPracticeAndExactReturn() {
        openGame()
        XCTAssertTrue(app.buttons["review.mainTakeaway"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["game.nextMoment"].exists, "The first entry is the overview")
        app.buttons["review.start"].tap()
        XCTAssertTrue(app.staticTexts["review.idea"].waitForExistence(timeout: 5))
        tap("Next plan step")
        XCTAssertTrue(app.staticTexts["Step 2/2"].exists)
        capture("Plan sequence second decision")
        tap("game.practiceMoment")
        XCTAssertTrue(app.staticTexts["practice.prompt"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["analysis.panel"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["analysis.evaluation"].exists)
        tap("practice.skip")
        XCTAssertTrue(app.staticTexts["practice.recapCount"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 of 1 core positions completed."].exists)
        tap("Return to review")
        XCTAssertTrue(app.staticTexts["Step 2/2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["review.idea"].exists)
        capture("Exact return to plan step")
    }

    func testExplicitSaveAndOpeningCollectionWithSearchAndSideFilter() {
        openGame(); tap("game.explore")
        XCTAssertTrue(app.buttons["board.square.f1"].waitForExistence(timeout: 5))
        app.buttons["board.square.f1"].tap(); app.buttons["board.square.d1"].tap()
        XCTAssertTrue(app.staticTexts["game.variation"].waitForExistence(timeout: 5))
        tap("game.saveLine")
        XCTAssertTrue(app.staticTexts["game.lineSaved"].waitForExistence(timeout: 5))
        tap("game.return")
        XCTAssertTrue(app.buttons["game.restoreLine"].waitForExistence(timeout: 5))
        tap("game.restoreLine")
        XCTAssertTrue(app.staticTexts["game.variation"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        tap("games.savedLines")
        XCTAssertTrue(app.navigationBars["Saved lines"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Unclassified opening"].exists)
        let line = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'lines.open.'")).firstMatch
        XCTAssertTrue(line.exists)
        line.tap()
        XCTAssertTrue(app.staticTexts["Your saved variation"].exists || app.buttons["Next position"].exists)
        capture("Saved line with source context")
    }

    func testReviewAndPracticeEvidenceStaySeparateAndManualControlsRemainAvailable() {
        openGame(); tap("review.start")
        app.tabBars.buttons["Practice"].tap()
        XCTAssertTrue(app.staticTexts["Your lessons"].waitForExistence(timeout: 5))
        let manage = app.buttons["Manage lesson"]
        for _ in 0..<5 where !manage.isHittable { app.swipeUp() }
        XCTAssertTrue(manage.isHittable)
        manage.tap(); app.buttons["Dismiss suggestion"].tap()
        app.buttons["Dismissed"].tap()
        let restoreMenu = app.buttons["Manage lesson"]
        XCTAssertTrue(restoreMenu.exists)
        restoreMenu.tap(); app.buttons["Restore"].tap()
        app.buttons["All"].tap()
        let history = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Open a file and activate the rook' AND label CONTAINS 'Learner' ")).firstMatch
        if history.exists { history.tap() }
        else { app.staticTexts["Open a file and activate the rook"].firstMatch.tap() }
        XCTAssertTrue(app.staticTexts["Recalled later: not yet evidenced"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Solved new related position: not yet evidenced"].exists)
        capture("Separate evidence history before attempts")
    }

    func testRequestedHelpStaysOnTheDecisionAndRecapDoesNotRequirePuzzles() {
        openGame(); tap("review.start"); tap("game.practiceMoment")
        XCTAssertTrue(app.buttons["board.square.d4"].waitForExistence(timeout: 5))
        let pawn = app.buttons["board.square.d4"]
        pawn.tap(); XCTAssertEqual(pawn.value as? String, "Selected")
        pawn.tap(); XCTAssertEqual(pawn.value as? String, "")
        tap("practice.hint")
        XCTAssertTrue(app.staticTexts["practice.hintText"].exists)
        XCTAssertTrue(app.buttons["board.square.d4"].label.contains("white pawn"))
        tap("practice.reveal")
        XCTAssertTrue(app.staticTexts["Answer reviewed"].waitForExistence(timeout: 5))
        tap("practice.continue")
        XCTAssertTrue(app.staticTexts["practice.recapCount"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 of 1 core positions completed."].exists)
        tap("Return to review")
        XCTAssertTrue(app.staticTexts["Step 1/2"].waitForExistence(timeout: 5))
    }

    func testNoLessonsAndPartialCoverageKeepExploreAvailable() throws {
        app.terminate()
        var fixture = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(app.launchEnvironment["CHESSME_UI_TEST_LIBRARY"]!.utf8)) as? [String: Any])
        var reviews = try XCTUnwrap(fixture["analyses"] as? [[String: Any]])
        reviews[0]["analyzedPlies"] = 1; reviews[0]["moveAssessments"] = []
        fixture["analyses"] = reviews
        app.launchEnvironment["CHESSME_UI_TEST_LIBRARY"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launch(); openGame()
        XCTAssertTrue(app.staticTexts["game.reviewStatus"].label.contains("1/2"))
        XCTAssertTrue(app.buttons["game.explore"].exists)
        XCTAssertFalse(app.buttons["review.start"].exists)
        capture("Honest partial review without invented lessons")
    }

    func testOptionalRelatedPuzzleReturnsToItsOfferingResultAndCountsSeparately() throws {
        app.terminate()
        let now = Date().timeIntervalSinceReferenceDate
        let source = "7k/5ppp/8/8/8/8/8/R5K1 w - - 1 2"
        let setup = "6k1/5ppp/8/8/8/8/8/4R1K1 b - - 0 1"
        let puzzleRoot = "7k/5ppp/8/8/8/8/8/4R1K1 w - - 1 2"
        let finding: [String: Any] = ["id": "backrank-lesson", "gameID": "demo-review-plan", "gameLabel": "Learner vs Partner",
            "positionFEN": source, "playedMove": "a1a2", "bestMove": "a1a8", "acceptedMoves": ["a1a8"],
            "continuation": ["a1a8"], "centipawnLoss": 500, "theme": "Missed checkmate", "explanation": "Inspect the back rank.",
            "hint": "Consider checks.", "moveNumber": 2, "source": "device", "isPuzzle": true, "quality": "blunder"]
        let puzzle: [String: Any] = ["id": "backrank-test", "setupFEN": setup, "setupMove": "g8h8", "positionFEN": puzzleRoot,
            "solution": ["e1e8"], "rating": 1200, "themes": ["backRankMate"], "openingTags": [],
            "url": "https://lichess.org/training/backrank-test", "source": "lichess", "license": "CC0"]
        let fixture: [String: Any] = [
            "games": [["id": "demo-review-plan", "username": "Learner", "white": "Learner", "black": "Partner", "playedAt": now - 60,
                       "playerSide": "white", "moves": "a1a2", "initialFEN": source, "status": "resign"]],
            "analyses": [["gameID": "demo-review-plan", "findings": [finding], "analyzedPlies": 1, "totalPlies": 1,
                          "source": "device", "completedAt": now, "engineVersion": "demonstration-reference"]],
            "puzzleRecommendations": [["gameID": "demo-review-plan", "analysisSignature": "demonstration", "rating": 1200,
                                       "matches": [["puzzle": puzzle, "matchedThemes": ["backRankMate"]]], "matchedAt": now]],
            "practice": [], "isDemo": true, "skippedGames": 0]
        app.launchEnvironment["CHESSME_UI_TEST_LIBRARY"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launch(); openGame(); tap("review.start"); tap("game.practiceMoment")
        XCTAssertTrue(app.buttons["board.square.a1"].waitForExistence(timeout: 5))
        app.buttons["board.square.a1"].tap(); app.buttons["board.square.a8"].tap()
        tap("practice.related")
        XCTAssertTrue(app.buttons["board.square.e1"].waitForExistence(timeout: 5))
        app.buttons["board.square.e1"].tap(); app.buttons["board.square.e8"].tap()
        XCTAssertFalse(app.buttons["practice.related"].exists, "Optional puzzles do not create an endless required chain")
        tap("practice.continue")
        XCTAssertTrue(app.buttons["practice.related"].waitForExistence(timeout: 5), "Returns to the original game exercise result")
        tap("practice.continue")
        XCTAssertTrue(app.staticTexts["1 of 1 core positions completed."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Optional related attempts"].exists)
        capture("Optional puzzle separate from completed core set")
    }

    private func openGame() {
        app.tabBars.buttons["Games"].tap()
        XCTAssertTrue(app.buttons["game.open.demo-review-plan"].waitForExistence(timeout: 5))
        app.buttons["game.open.demo-review-plan"].tap()
    }
    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<7 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable, app.debugDescription)
        button.tap()
    }
    private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = title
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
