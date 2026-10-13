import XCTest

final class ChessMeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--demo", "--ui-testing", "--reset-design", "--reset-engine", "--reset-evaluation", "--reset-local-analysis"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        try super.tearDownWithError()
    }

    func testCloudSetupShowsOnlyTheNextRequiredStep() {
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.tabBars.buttons["Games"].tap()
        let cloud = app.buttons["cloud.open"]
        for _ in 0..<3 where !cloud.isHittable { app.scrollViews["games.scroll"].swipeUp() }
        cloud.tap()
        XCTAssertTrue(app.staticTexts["cloud.nextStep"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["cloud.nextStep"].label, "Connect Lichess")
        XCTAssertTrue(app.buttons["cloud.connectLichess"].isEnabled)
        XCTAssertFalse(app.switches["cloud.consent"].exists)
        XCTAssertFalse(app.buttons["cloud.proOptions"].exists)
        XCTAssertFalse(app.switches["cloud.enable"].exists)
        XCTAssertFalse(app.buttons["cloud.chooseGames"].exists)
        capture("Cloud setup with one next step")
        app.buttons["Connection & review details"].tap()
        XCTAssertTrue(app.buttons["cloud.restore"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.switches["cloud.enable"].exists, "Advanced details must not bypass entitlement verification")
        app.buttons["cloud.done"].tap()
        XCTAssertTrue(cloud.waitForExistence(timeout: 5))
    }

    func testConnectionKeepsAlternativeImportsBehindOneChoice() {
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let connect = app.buttons["connect.start"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        XCTAssertTrue(connect.isHittable, "Connection belongs above the welcome board")
        connect.tap()
        XCTAssertTrue(app.buttons["connection.connect"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["connection.connect"].isEnabled)
        XCTAssertFalse(app.textFields["connection.username"].exists)
        XCTAssertFalse(app.buttons["connection.pgn"].exists)
        let consent = app.switches["connection.consent"]
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["connection.connect"].isEnabled)
        capture("Simple Lichess connection")
        app.buttons["Other ways to import"].tap()
        XCTAssertTrue(app.buttons["connection.pgn"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["connection.publicProfile"].tap()
        XCTAssertTrue(app.textFields["connection.username"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Public profile"].exists)
        app.navigationBars["Public profile"].buttons.firstMatch.tap()
        app.buttons["connection.pgn"].tap()
        XCTAssertTrue(app.navigationBars["PGN import"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose a PGN file"].exists)
    }

    func testStandalonePaywallCanConnectLichessBeforeCloudConsent() {
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.tabBars.buttons["Games"].tap()
        app.buttons["games.period"].tap()
        XCTAssertTrue(app.buttons["window.7d"].waitForExistence(timeout: 5))
        app.buttons["window.7d"].tap()
        let connect = app.buttons["Connect Lichess before subscribing"]
        for _ in 0..<4 where !connect.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(connect.isEnabled, "Connecting Lichess must be possible before cloud consent is saved")
        capture("Standalone paywall account connection")
    }

    func testDemoReviewStartsAnInteractiveLesson() throws {
        let startLesson = app.buttons["lesson.start"]
        // The shared CI simulator can take longer to finish real device analysis.
        XCTAssertTrue(startLesson.waitForExistence(timeout: 90), "Demo analysis should produce a lesson.\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["Your review"].exists)
        XCTAssertFalse(app.staticTexts["PATTERNS TO PRACTISE"].exists)

        let review = XCTAttachment(screenshot: app.screenshot())
        review.name = "Demo review"
        review.lifetime = .keepAlways
        add(review)

        for _ in 0..<3 where !startLesson.isHittable {
            app.scrollViews["main.scroll"].swipeUp()
        }
        XCTAssertTrue(startLesson.isHittable, "The lesson entry point should be reachable by scrolling.")
        startLesson.tap()
        let square = app.descendants(matching: .any).matching(identifier: "board.square.a1").firstMatch
        XCTAssertTrue(square.waitForExistence(timeout: 10), "The lesson should show an interactive chessboard.")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "board.square.h8").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "board.design.classic").firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["analysis.panel"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["analysis.evaluation"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["analysis.evaluation"].value as? String, "?")
        XCTAssertEqual(app.sheets.count, 0, "Lessons fill the current tab.")
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        XCTAssertTrue(app.tabBars.buttons["Games"].exists)
        XCTAssertTrue(app.tabBars.buttons["Practice"].exists)
        XCTAssertEqual(board("classic").value as? String, "No engine suggestions")
        XCTAssertFalse(app.staticTexts["Find a better move"].exists)
        XCTAssertFalse(app.staticTexts["Move history"].exists)
        XCTAssertTrue(app.buttons["favorite.toggle"].isHittable)

        let lesson = XCTAttachment(screenshot: app.screenshot())
        lesson.name = "Interactive lesson"
        lesson.lifetime = .keepAlways
        add(lesson)

        let reveal = app.buttons["lesson.reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        app.scrollViews["lesson.scroll"].swipeUp()
        for _ in 0..<3 where !reveal.isHittable { app.scrollViews["lesson.scroll"].swipeUp() }
        reveal.tap()
        for _ in 0..<3 where !app.staticTexts["lesson.feedback"].exists { app.scrollViews["lesson.scroll"].swipeUp() }
        XCTAssertTrue(app.staticTexts["lesson.feedback"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["See the idea."].exists)
    }

    func testPaidWindowShowsSubscriptionAndCanBeDismissed() throws {
        app.tabBars.buttons["Games"].tap()
        app.buttons["games.period"].tap()
        let paidWindow = app.buttons["window.7d"]
        XCTAssertTrue(paidWindow.waitForExistence(timeout: 15))
        paidWindow.tap()

        let close = app.buttons["paywall.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "A paid review window should require Pro.")
        close.tap()

        XCTAssertTrue(app.buttons["games.period"].waitForExistence(timeout: 5))
        app.buttons["games.period"].tap()
        XCTAssertTrue(app.buttons["window.24h"].exists)
    }

    func testLessonDeselectsAndMovesThroughOneContinuousSession() throws {
        let start = app.buttons["lesson.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 90))
        let complete = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["review.pause"])
        wait(for: [complete], timeout: 90)
        for _ in 0..<3 where !start.isHittable { app.scrollViews["main.scroll"].swipeUp() }
        start.tap()
        XCTAssertTrue(app.buttons["board.square.a1"].waitForExistence(timeout: 10))
        let whiteToMove = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'White to move'")).firstMatch.exists
        let origin = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'board.square.' AND label CONTAINS %@", whiteToMove ? "white " : "black ")).firstMatch
        XCTAssertTrue(origin.exists)
        XCTAssertTrue(app.descendants(matching: .any)["analysis.evaluation"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["analysis.evaluation"].value as? String, "?")
        XCTAssertEqual(board("classic").value as? String, "No engine suggestions")
        origin.tap()
        XCTAssertEqual(origin.value as? String, "Selected")
        origin.tap()
        XCTAssertEqual(origin.value as? String, "")
        capture("Unaided lesson")
        let guidance = app.buttons["lesson.guidance"]
        for _ in 0..<4 where !guidance.isHittable || guidance.frame.maxY > app.buttons["session.next"].frame.minY - 12 {
            app.scrollViews["lesson.scroll"].swipeUp()
        }
        guidance.tap()
        XCTAssertEqual(guidance.label, "Hide analysis", app.debugDescription)
        let panel = app.descendants(matching: .any)["analysis.panel"]
        for _ in 0..<3 where !panel.exists { app.scrollViews["lesson.scroll"].swipeUp() }
        XCTAssertTrue(panel.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["analysis.evaluation"].exists)
        capture("Requested lesson analysis")
        let counter = app.staticTexts["session.position"]
        let first = counter.label
        let next = app.buttons["session.next"]
        for _ in 0..<5 where !next.isHittable { app.scrollViews["lesson.scroll"].swipeUp() }
        XCTAssertTrue(next.isHittable)
        next.tap()
        XCTAssertTrue(counter.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertNotEqual(counter.label, first, "The next lesson replaces content in the same tab.")
        XCTAssertFalse(app.descendants(matching: .any)["analysis.panel"].exists, "Every new lesson starts unaided.")
        XCTAssertEqual(board("classic").value as? String, "No engine suggestions")
        XCTAssertTrue(app.buttons["Done"].exists)
        let previous = app.buttons["session.previous"]
        for _ in 0..<5 where !previous.isHittable { app.scrollViews["lesson.scroll"].swipeUp() }
        previous.tap()
        XCTAssertEqual(counter.label, first)
    }

    func testGameAllowsAnimatedVariationsAndReturnsToOriginalTimeline() throws {
        XCTAssertTrue(app.buttons["lesson.start"].waitForExistence(timeout: 90))
        app.tabBars.buttons["Games"].tap()
        let game = app.buttons.containing(.staticText, identifier: "Practice partner").firstMatch
        XCTAssertTrue(game.waitForExistence(timeout: 5), app.debugDescription)
        game.tap()
        enterReplay()
        let e2 = app.buttons["board.square.e2"]
        XCTAssertTrue(e2.waitForExistence(timeout: 10))
        e2.tap()
        XCTAssertEqual(e2.value as? String, "Selected")
        e2.tap()
        XCTAssertEqual(e2.value as? String, "")
        e2.tap()
        app.buttons["board.square.e4"].tap()
        XCTAssertTrue(app.staticTexts["game.variation"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["game.variation"].label, "e4")
        XCTAssertTrue(app.buttons["board.square.e4"].label.contains("white pawn"))
        capture("Interactive game variation")
        let back = app.buttons["game.return"]
        for _ in 0..<3 where !back.isHittable { app.scrollViews["game.scroll"].swipeUp() }
        back.tap()
        XCTAssertFalse(app.staticTexts["game.variation"].exists)
        XCTAssertTrue(app.buttons["board.square.e2"].label.contains("white pawn"))
        XCTAssertEqual(app.staticTexts["game.position"].label, "Starting position")
        app.buttons["game.next"].tap()
        XCTAssertEqual(app.staticTexts["game.position"].label, "Ply 1/12")
    }

    func testNextPuzzleStartsUnaidedWithoutLeavingThePracticeFlow() throws {
        app.terminate()
        let example: [String: Any] = [
            "id": "sample-next-a", "setupFEN": "q3k1nr/1pp1nQpp/3p4/1P2p3/4P3/B1PP1b2/B5PP/5K2 b k - 0 17",
            "setupMove": "e8d7", "positionFEN": "q5nr/1ppknQpp/3p4/1P2p3/4P3/B1PP1b2/B5PP/5K2 w - - 1 18",
            "solution": ["a2e6", "d7d8", "f7f8"], "rating": 1760, "themes": ["mate", "mateIn2"],
            "openingTags": [], "url": "https://lichess.org/training/00sHx", "source": "lichess", "license": "CC0"
        ]
        var second = example
        second["id"] = "sample-next-b"
        second["rating"] = 1550
        let fixture: [String: Any] = [
            "games": [], "analyses": [], "practice": [], "isDemo": true, "skippedGames": 0,
            "puzzleRecommendations": [["gameID": "sample", "analysisSignature": "ui-fixture", "rating": 1760,
                "matchedAt": Date().timeIntervalSinceReferenceDate,
                "matches": [["puzzle": example, "matchedThemes": ["mate"]], ["puzzle": second, "matchedThemes": ["mate"]]]]]
        ]
        app.launchArguments = ["--ui-testing", "--reset-engine", "--reset-evaluation"]
        app.launchEnvironment["CHESSME_UI_TEST_LIBRARY"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launch()
        openPracticeHome()
        app.buttons["practice.puzzles"].tap()
        app.buttons["puzzles.play"].tap()
        let reveal = app.buttons["puzzle.reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 10))
        reveal.tap()
        XCTAssertTrue(app.buttons["puzzle.next"].waitForExistence(timeout: 10))
        capture("Completed puzzle with next action")
        app.buttons["puzzle.next"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Level' AND label CONTAINS '550'")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["puzzle.reveal"].exists)
        XCTAssertFalse(app.buttons["puzzle.next"].exists)
        XCTAssertFalse(app.staticTexts["See the solution"].exists)
        XCTAssertEqual(board("classic").value as? String, "No engine suggestions")
        XCTAssertEqual(app.sheets.count, 0)
        XCTAssertTrue(app.tabBars.buttons["Practice"].isSelected)
    }

    func testReviewClocksFollowMovesAndDoNotAssignTimesToVariations() {
        XCTAssertTrue(app.buttons["lesson.start"].waitForExistence(timeout: 90))
        app.tabBars.buttons["Games"].tap()
        let game = app.buttons.containing(.staticText, identifier: "Practice partner").firstMatch
        XCTAssertTrue(game.waitForExistence(timeout: 5))
        game.tap()
        enterReplay()
        let white = app.descendants(matching: .any)["game.clock.white"]
        let black = app.descendants(matching: .any)["game.clock.black"]
        XCTAssertTrue(white.waitForExistence(timeout: 10))
        XCTAssertEqual(white.value as? String, "5:00")
        XCTAssertEqual(black.value as? String, "5:00")
        let next = app.buttons["game.next"]
        for _ in 0..<3 where !next.isHittable { app.scrollViews["game.scroll"].swipeUp() }
        next.tap(); next.tap(); next.tap()
        for _ in 0..<3 where !white.isHittable { app.scrollViews["game.scroll"].swipeDown() }
        XCTAssertEqual(white.value as? String, "4:59")
        XCTAssertEqual(black.value as? String, "5:00")
        XCTAssertTrue(white.label.contains("You"))
        XCTAssertTrue(black.label.contains("Practice partner"))
        XCTAssertEqual(app.staticTexts["game.clock.lastMove.white"].label, "Last move ≈4.0s")
        XCTAssertEqual(app.staticTexts["game.clock.lastMove.black"].label, "First move untimed")
        XCTAssertFalse(app.buttons["game.previousMove"].exists)
        XCTAssertFalse(app.buttons["game.nextMove"].exists)
        XCTAssertFalse(app.staticTexts["Imported moves"].exists)
        capture("Player clocks and last move durations")
        app.buttons["board.square.g8"].tap()
        app.buttons["board.square.f6"].tap()
        XCTAssertTrue(app.staticTexts["game.variation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["game.clock.moveTiming"].label.contains("no recorded move times"))
        XCTAssertEqual(black.value as? String, "5:00")
        capture("Variation keeps the original game clocks")
    }

    func testLongReviewNavigatesWithRecordedClocksWhileAnalysisRuns() throws {
        app.terminate()
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "lichess-clock-game", withExtension: "json") ?? bundle.url(forResource: "lichess-clock-game", withExtension: "json", subdirectory: "Fixtures"))
        var game = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        game["playedAt"] = Date().timeIntervalSinceReferenceDate
        let fixture: [String: Any] = ["games": [game], "analyses": [], "practice": [], "isDemo": true, "skippedGames": 0]
        app.launchArguments = ["--ui-testing", "--reset-engine", "--reset-evaluation"]
        app.launchEnvironment["CHESSME_UI_TEST_LIBRARY"] = String(data: try JSONSerialization.data(withJSONObject: fixture), encoding: .utf8)
        app.launch()
        app.tabBars.buttons["Games"].tap()
        app.buttons.containing(.staticText, identifier: "TryingHard87").firstMatch.tap()
        enterReplay()
        let white = app.descendants(matching: .any)["game.clock.white"]
        XCTAssertTrue(white.waitForExistence(timeout: 10))
        XCTAssertEqual(white.value as? String, "2:30", "The real export includes a reduced starting clock")
        let next = app.buttons["game.next"]
        for _ in 0..<3 where !next.isHittable { app.scrollViews["game.scroll"].swipeUp() }
        for _ in 0..<6 { next.tap() }
        XCTAssertEqual(app.staticTexts["game.position"].label, "Ply 6/125")
        capture("Long review while device analysis runs")
        app.buttons["Last position"].tap()
        XCTAssertEqual(app.staticTexts["game.position"].label, "Ply 125/125")
        app.buttons["game.previous"].tap()
        XCTAssertEqual(app.staticTexts["game.position"].label, "Ply 124/125")
        capture("Long game final move and clocks")
    }

    func testEngineSettingsExposeDeviceLimitsAndCloudAvailability() throws {
        openSettings()
        let engines = app.buttons["settings.engines"]
        XCTAssertTrue(engines.waitForExistence(timeout: 5))
        engines.tap()
        XCTAssertTrue(app.navigationBars["Analysis engines"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.steppers["engine.depth"].exists, "Presets are the default configuration")
        app.buttons["Advanced"].tap()
        XCTAssertTrue(app.steppers["engine.depth"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Maximum depth: 21"].exists)
        app.buttons["Deep"].tap()
        XCTAssertTrue(app.staticTexts["Maximum depth: 24"].exists)
        XCTAssertTrue(app.buttons["engine.device"].label.contains("Stockfish"), app.debugDescription)
        capture("Device engine settings")
        let cloud = app.descendants(matching: .any)["engine.cloud"]
        for _ in 0..<4 where !cloud.exists { app.swipeUp() }
        XCTAssertTrue(cloud.exists, app.debugDescription)
        capture("Cloud engine availability")
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        openSettings()
        app.buttons["settings.engines"].tap()
        app.buttons["Advanced"].tap()
        XCTAssertTrue(app.staticTexts["Maximum depth: 24"].waitForExistence(timeout: 5), "Engine preferences should survive relaunch.")
    }

    func testMenuOffersSettingsAndDesignPersistsAcrossLaunches() throws {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-design"]
        app.launch()

        XCTAssertTrue(board("classic").waitForExistence(timeout: 10))
        capture("Classic welcome board")
        openSettings()
        let designRow = app.buttons["settings.design"]
        XCTAssertTrue(designRow.waitForExistence(timeout: 5))
        designRow.tap()
        XCTAssertTrue(app.navigationBars["Design"].waitForExistence(timeout: 5))

        let classic = app.buttons["design.option.classic"]
        XCTAssertTrue(classic.waitForExistence(timeout: 5))
        XCTAssertEqual(classic.value as? String, "Selected")
        capture("Classic design settings")

        for design in ["slate", "clay"] {
            let option = app.buttons["design.option.\(design)"]
            for _ in 0..<2 where !option.isHittable { app.scrollViews["design.scroll"].swipeUp() }
            option.tap()
            XCTAssertEqual(option.value as? String, "Selected")
            XCTAssertTrue(board(design).waitForExistence(timeout: 5))
            capture("\(design.capitalized) design settings")
        }

        app.navigationBars["Design"].buttons.element(boundBy: 0).tap()
        app.buttons["settings.done"].tap()
        XCTAssertTrue(board("clay").waitForExistence(timeout: 5), "The main board should change immediately.")

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(board("clay").waitForExistence(timeout: 10), "The design should remain selected after relaunch.")
        openSettings()
        app.buttons["settings.design"].tap()
        XCTAssertEqual(app.buttons["design.option.clay"].value as? String, "Selected")
        app.navigationBars["Design"].buttons.element(boundBy: 0).tap()
        app.buttons["settings.done"].tap()

        for tab in ["Practice", "Games"] {
            app.tabBars.buttons[tab].tap()
            openSettings()
            XCTAssertTrue(app.buttons["settings.design"].waitForExistence(timeout: 5))
            app.buttons["settings.done"].tap()
        }
    }

    func testLessonHistoryMarkerAndFavoriteStayInsideTheTab() throws {
        XCTAssertTrue(app.buttons["lesson.start"].waitForExistence(timeout: 90))
        app.tabBars.buttons["Practice"].tap()
        let lesson = app.buttons["practice.lesson.demo-missed-mate-6"]
        for _ in 0..<6 where !lesson.isHittable { app.swipeUp() }
        XCTAssertTrue(lesson.waitForExistence(timeout: 10), app.debugDescription)
        lesson.tap()
        XCTAssertEqual(app.sheets.count, 0)
        XCTAssertTrue(app.buttons["board.square.e2"].waitForExistence(timeout: 10))
        XCTAssertTrue((app.buttons["board.square.e2"].value as? String ?? "").contains("Original blunder destination"))
        let bar = app.descendants(matching: .any)["analysis.evaluation"]
        XCTAssertEqual(bar.value as? String, "?")
        let frame = board("classic").frame
        let previous = app.buttons["lesson.previousMove"]
        XCTAssertTrue(previous.isEnabled)
        previous.tap()
        XCTAssertTrue(app.buttons["lesson.playBestMove"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["lesson.return"].exists)
        app.buttons["lesson.nextMove"].tap()
        let favorite = app.buttons["favorite.toggle"]
        for _ in 0..<3 where !favorite.isHittable { app.scrollViews["lesson.scroll"].swipeUp() }
        favorite.tap()
        capture("Lesson with mistake square and history")
        let guidance = app.buttons["lesson.guidance"]
        for _ in 0..<4 where !guidance.isHittable || guidance.frame.maxY > app.buttons["session.next"].frame.minY - 12 {
            app.scrollViews["lesson.scroll"].swipeUp()
        }
        guidance.tap()
        XCTAssertEqual(guidance.label, "Hide analysis", app.debugDescription)
        let panel = app.descendants(matching: .any)["analysis.panel"]
        for _ in 0..<3 where !panel.exists { app.scrollViews["lesson.scroll"].swipeUp() }
        XCTAssertTrue(panel.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(board("classic").frame.width, frame.width, accuracy: 1)
        app.buttons["Done"].tap()
        openPracticeHome()
        app.buttons["practice.saved"].tap()
        XCTAssertTrue(app.staticTexts["Lessons and review moments"].waitForExistence(timeout: 5))
        capture("Saved lesson in favorites")
    }

    func testPuzzleRequiresTheWholeLineAndCanBeSaved() throws {
        openPracticeHome()
        app.buttons["practice.puzzles"].tap()
        let puzzle = app.buttons["puzzle.open.00sHx"]
        XCTAssertTrue(puzzle.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Puzzles for your games"].exists)
        let play = app.buttons["puzzles.play"]
        XCTAssertTrue(play.isHittable)
        XCTAssertTrue(play.label.contains("Play"))
        capture("Puzzles play button")
        play.tap()
        XCTAssertTrue(app.buttons["board.square.a2"].waitForExistence(timeout: 10))
        let puzzleSquare = app.descendants(matching: .any).matching(identifier: "board.square.a8").firstMatch
        let puzzleBoardTop = puzzleSquare.frame.minY
        XCTAssertFalse(app.staticTexts["Find the best move"].exists)
        app.buttons["board.square.a2"].tap()
        app.buttons["board.square.e6"].tap()
        XCTAssertTrue(app.staticTexts["puzzle.feedback"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["puzzle.feedback"].label, "Correct. Find your next move.")
        XCTAssertFalse(app.staticTexts["Line complete"].exists)
        XCTAssertTrue(app.buttons["board.square.f7"].waitForExistence(timeout: 5), "Wait for the animated opponent reply")
        app.buttons["board.square.f7"].tap()
        app.buttons["board.square.f8"].tap()
        XCTAssertTrue(app.staticTexts["Line complete"].waitForExistence(timeout: 5))
        capture("Puzzle board celebration stays in place")
        XCTAssertEqual(puzzleSquare.frame.minY, puzzleBoardTop, accuracy: 1, "Puzzle completion must not move the board squares.")
        let compare = app.buttons["training.compareMoves"]
        for _ in 0..<3 where !compare.isHittable { app.scrollViews["puzzle.scroll"].swipeUp() }
        let bar = app.descendants(matching: .any)["analysis.evaluation"]
        let evaluated = expectation(for: NSPredicate(format: "value != '?'"), evaluatedWith: bar)
        wait(for: [evaluated], timeout: 15)
        let score = bar.value as? String
        compare.tap()
        XCTAssertEqual(bar.value as? String, score)
        compare.tap()
        XCTAssertEqual(bar.value as? String, score)
        let favorite = app.buttons["favorite.toggle"]
        for _ in 0..<3 where !favorite.isHittable { app.scrollViews["puzzle.scroll"].swipeDown() }
        favorite.tap()
        capture("Completed multi-move Lichess puzzle")
        openPracticeHome()
        app.buttons["practice.saved"].tap()
        XCTAssertTrue(app.staticTexts["Lichess puzzles"].waitForExistence(timeout: 5))
        capture("Favorite Lichess puzzle")
    }

    func testWrongLessonMoveBouncesBackAndAllowsAnImmediateRetry() throws {
        XCTAssertTrue(app.buttons["lesson.start"].waitForExistence(timeout: 90))
        app.tabBars.buttons["Practice"].tap()
        let lesson = app.buttons["practice.lesson.demo-missed-mate-6"]
        for _ in 0..<6 where !lesson.isHittable { app.swipeUp() }
        lesson.tap()
        XCTAssertTrue(app.buttons["board.square.h5"].waitForExistence(timeout: 10))
        app.buttons["board.square.h5"].tap()
        app.buttons["board.square.e2"].tap()
        XCTAssertTrue(app.staticTexts["lesson.feedback"].waitForExistence(timeout: 2))
        let queen = app.buttons["board.square.h5"]
        XCTAssertTrue(queen.waitForExistence(timeout: 2), "The board should accept a retry while engine alternatives are still being evaluated")
        XCTAssertTrue(queen.label.contains("white queen"))
        XCTAssertTrue((app.buttons["board.square.f7"].value as? String ?? "").contains("Best destination"))
        let beforeSolve = board("classic").frame
        capture("Wrong move returned with good move highlights")
        queen.tap()
        XCTAssertEqual(queen.value as? String, "Selected")
        app.buttons["board.square.f7"].tap()
        XCTAssertTrue(app.staticTexts["lesson.success"].waitForExistence(timeout: 2))
        XCTAssertEqual(board("classic").frame.minY, beforeSolve.minY, accuracy: 1, "Success feedback must not move the board.")
        XCTAssertEqual(app.buttons["session.next"].value as? String, "Ready to continue")
        let compare = app.buttons["training.compareMoves"]
        let bar = app.descendants(matching: .any)["analysis.evaluation"]
        let evaluated = expectation(for: NSPredicate(format: "value != '?'"), evaluatedWith: bar)
        wait(for: [evaluated], timeout: 15)
        let score = bar.value as? String
        compare.tap()
        XCTAssertEqual(bar.value as? String, score)
        compare.tap()
        XCTAssertEqual(bar.value as? String, score)
        capture("Correct move and alternative highlights")
    }

    func testContinuationAllowsOwnMovesAndRestoresTheSolvedPosition() throws {
        app.terminate()
        let now = Date().timeIntervalSinceReferenceDate
        let finding: [String: Any] = [
            "id": "demo-continuation-2", "gameID": "demo-continuation", "gameLabel": "You vs Practice partner",
            "positionFEN": "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2",
            "playedMove": "h2h4", "bestMove": "g1f3", "acceptedMoves": ["g1f3"],
            "continuation": ["g1f3", "b8c6", "f1c4", "g8f6"], "centipawnLoss": 120,
            "theme": "Development", "explanation": "A demonstration of developing a knight before a wing pawn.",
            "hint": "Develop a knight.", "moveNumber": 2, "source": "device", "isPuzzle": true
        ]
        var following = finding
        following["id"] = "demo-continuation-following"
        let fixture: [String: Any] = [
            "games": [["id": "demo-continuation", "username": "You", "white": "You", "black": "Practice partner",
                       "playedAt": now - 60, "playerSide": "white", "moves": "e4 e5 h4 Nc6", "status": "resign"]],
            "analyses": [["gameID": "demo-continuation", "findings": [finding, following], "analyzedPlies": 2, "totalPlies": 2,
                          "source": "device", "completedAt": now, "engineVersion": "ui-demonstration"]],
            "practice": [], "isDemo": true, "skippedGames": 0
        ]
        app.launchEnvironment["CHESSME_UI_TEST_LIBRARY"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launch()
        app.tabBars.buttons["Practice"].tap()
        app.buttons["practice.lesson.demo-continuation-2"].tap()
        let knight = app.buttons["board.square.g1"]
        XCTAssertTrue(knight.waitForExistence(timeout: 10))
        let beforeSolve = board("classic").frame
        knight.tap()
        app.buttons["board.square.f3"].tap()
        XCTAssertTrue(app.staticTexts["lesson.success"].waitForExistence(timeout: 5))
        XCTAssertEqual(board("classic").frame.minY, beforeSolve.minY, accuracy: 1)
        XCTAssertEqual(app.buttons["session.next"].value as? String, "Ready to continue")
        XCTAssertEqual(app.buttons["session.next"].label, "Next position")
        app.buttons["lesson.continuation"].tap()
        XCTAssertTrue(app.buttons["board.square.f3"].label.contains("white knight"))
        XCTAssertTrue(app.staticTexts["Play the continuation yourself."].exists)
        let highlights = expectation(for: NSPredicate(format: "value CONTAINS 'good move highlights'"), evaluatedWith: board("classic"))
        wait(for: [highlights], timeout: 15)
        let alternative = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'board.square.' AND (value == 'Excellent destination' OR value == 'Good destination')")).firstMatch
        XCTAssertTrue(alternative.waitForExistence(timeout: 15), "Comparable moves should get lighter green highlights after analysis.")
        capture("Interactive continuation with good move squares")
        app.buttons["board.square.g8"].tap()
        app.buttons["board.square.f6"].tap()
        XCTAssertTrue(app.buttons["board.square.f6"].label.contains("black knight"), "The user can choose a move outside the saved continuation.")
        let undo = app.buttons["lesson.undo"]
        for _ in 0..<4 where !undo.isHittable { app.scrollViews["lesson.scroll"].swipeUp() }
        undo.tap()
        XCTAssertTrue(app.buttons["board.square.g8"].label.contains("black knight"))
        for _ in 0..<4 where !app.buttons["lesson.playBestMove"].isHittable { app.scrollViews["lesson.scroll"].swipeDown() }
        app.buttons["lesson.playBestMove"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'White to move'")).firstMatch.exists)
        let reset = app.buttons["lesson.reset"]
        for _ in 0..<4 where !reset.isHittable { app.scrollViews["lesson.scroll"].swipeUp() }
        reset.tap()
        XCTAssertTrue(app.buttons["board.square.b8"].label.contains("black knight"))
        XCTAssertTrue(app.buttons["board.square.g8"].label.contains("black knight"))
        XCTAssertTrue(app.buttons["board.square.f3"].label.contains("white knight"), "Reset returns to the solved position, preserving the lesson move.")
        let best = app.buttons["lesson.playBestMove"]
        XCTAssertTrue(best.exists)
        XCTAssertFalse(app.buttons["Back to lesson"].exists)
        XCTAssertFalse(app.buttons["Return to lesson"].exists)
        let previous = app.buttons["lesson.previousMove"]
        for _ in 0..<5 where !previous.isHittable { app.scrollViews["lesson.scroll"].swipeDown() }
        let navigationY = previous.frame.minY
        previous.tap()
        XCTAssertTrue(best.exists, "Best-move control remains available while browsing")
        XCTAssertEqual(previous.frame.minY, navigationY, accuracy: 2)
        for _ in 0..<5 where !best.isHittable { app.scrollViews["lesson.scroll"].swipeUp() }
        best.tap()
        XCTAssertTrue(best.exists)
        XCTAssertFalse((board("classic").value as? String ?? "").contains("2 engine suggestions"))
        capture("Practice navigation keeps best-move playback inside the lesson")
        app.buttons["session.next"].tap()
        XCTAssertEqual(app.staticTexts["session.position"].label, "2/2")
        XCTAssertFalse(app.staticTexts["lesson.success"].exists)
    }

    func testEvaluationPreferenceAndOpeningThreshold() throws {
        openSettings()
        let toggle = app.switches["settings.evaluationBar"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["settings.done"].tap()
        openPracticeHome()
        app.buttons["practice.puzzles"].tap()
        app.buttons["puzzle.open.00sHx"].tap()
        XCTAssertTrue(board("classic").waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["analysis.evaluation"].exists)
        openPracticeHome()
        app.buttons["openings.open"].tap()
        XCTAssertTrue(app.staticTexts["openings.coverage"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["openings.coverage"].label, "0 / 30 openings reviewed")
        capture("Opening sample threshold")
    }

    func testGuidedReviewMovesBetweenMomentsAndPreservesExplore() throws {
        app.terminate()
        let now = Date().timeIntervalSinceReferenceDate
        let first: [String: Any] = [
            "id": "guided-first", "gameID": "guided-game", "gameLabel": "You vs Practice partner",
            "positionFEN": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "playedMove": "h2h4", "bestMove": "e2e4", "acceptedMoves": ["e2e4"], "continuation": ["e2e4"],
            "centipawnLoss": 120, "theme": "Development", "explanation": "Claim the centre.", "hint": "Look at a central pawn.",
            "moveNumber": 1, "source": "device", "isPuzzle": true
        ]
        var second = first
        second["id"] = "guided-second"
        second["positionFEN"] = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"
        second["moveNumber"] = 2
        second["bestMove"] = "g1f3"
        second["acceptedMoves"] = ["g1f3"]
        second["continuation"] = ["g1f3"]
        let fixture: [String: Any] = [
            "games": [["id": "guided-game", "username": "You", "white": "You", "black": "Practice partner",
                       "playedAt": now - 60, "playerSide": "white", "moves": "e4 e5 h4 Nc6", "status": "resign"]],
            "analyses": [["gameID": "guided-game", "findings": [first, second], "analyzedPlies": 4, "totalPlies": 4,
                          "source": "device", "completedAt": now, "engineVersion": "ui-demonstration"]],
            "practice": [], "isDemo": true, "skippedGames": 0
        ]
        app.launchArguments = ["--ui-testing", "--reset-engine", "--reset-evaluation"]
        app.launchEnvironment["CHESSME_UI_TEST_LIBRARY"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launch()
        app.tabBars.buttons["Games"].tap()
        app.buttons["game.open.guided-game"].tap()
        XCTAssertTrue(app.buttons["game.nextMoment"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["game.moment"].exists)
        XCTAssertFalse(app.staticTexts["Completed game"].exists)
        XCTAssertTrue(app.buttons["board.square.e2"].label.contains("white pawn"))
        XCTAssertFalse(app.descendants(matching: .any)["analysis.panel"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["game.clock.white"].exists)
        app.buttons["game.nextMoment"].tap()
        XCTAssertFalse(app.staticTexts["game.moment"].exists)
        XCTAssertTrue(app.buttons["board.square.e4"].label.contains("white pawn"))
        XCTAssertTrue(app.buttons["game.practiceMoment"].exists)
        XCTAssertFalse(app.buttons["game.previousMove"].exists)
        capture("Guided game review")
        enterReplay()
        XCTAssertTrue(app.buttons["board.square.e2"].label.contains("white pawn"))
        XCTAssertTrue(app.descendants(matching: .any)["analysis.panel"].exists)
        XCTAssertTrue(app.buttons["game.move.1"].exists, "The move list remains available in Explore")
        for _ in 0..<3 where !app.buttons["game.explore"].isHittable { app.scrollViews["game.scroll"].swipeDown() }
        app.buttons["game.explore"].tap()
        XCTAssertFalse(app.staticTexts["game.moment"].exists)
        XCTAssertTrue(app.buttons["board.square.e4"].label.contains("white pawn"))
        app.buttons["game.previousMoment"].tap()
        XCTAssertFalse(app.staticTexts["game.moment"].exists)
    }

    private func openSettings() {
        let settings = app.buttons["app.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
    }

    private func openPracticeHome() {
        app.tabBars.buttons["Practice"].tap()
        for _ in 0..<4 {
            if app.buttons["practice.puzzles"].isHittable { break }
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
            else { app.scrollViews["practice.scroll"].swipeDown() }
        }
    }

    private func enterReplay() {
        let explore = app.buttons["game.explore"]
        XCTAssertTrue(explore.waitForExistence(timeout: 10))
        explore.tap()
        let first = app.buttons["First position"]
        for _ in 0..<3 where !first.isHittable { app.scrollViews["game.scroll"].swipeUp() }
        first.tap()
        for _ in 0..<3 where !app.buttons["board.square.e2"].isHittable { app.scrollViews["game.scroll"].swipeDown() }
    }

    func testOvernightDepthSettingsPersistAndExplainCompletedDepth() throws {
        openSettings()
        app.buttons["settings.localAnalysis"].tap()
        XCTAssertTrue(app.navigationBars["On-device analysis"].waitForExistence(timeout: 5))
        let night = app.switches["localAnalysis.overnight"]
        XCTAssertTrue(night.exists)
        XCTAssertEqual(night.value as? String, "0")
        let maximum = app.buttons["localAnalysis.level.maximum"]
        for _ in 0..<3 where !maximum.isHittable { app.swipeUp() }
        maximum.tap()
        XCTAssertTrue(maximum.isSelected)
        capture("On-device depth choices")
        for _ in 0..<3 where !night.isHittable { app.swipeDown() }
        night.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(night.value as? String, "1")
        capture("Overnight analysis enabled")
        app.terminate()
        app.launchArguments = ["--demo", "--ui-testing", "--reset-engine"]
        app.launch()
        openSettings()
        app.buttons["settings.localAnalysis"].tap()
        XCTAssertTrue(app.navigationBars["On-device analysis"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["localAnalysis.overnight"].value as? String, "1")
        XCTAssertTrue(app.buttons["localAnalysis.level.maximum"].isSelected)
    }

    func testBaseIPhone15CanSelectEveryDepthAndSeeNightCapacity() throws {
        app.terminate()
        app.launchArguments += ["--local-analysis-base-iphone15"]
        app.launch()
        openSettings()
        app.buttons["settings.localAnalysis"].tap()
        XCTAssertTrue(app.navigationBars["On-device analysis"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["localAnalysis.overnight"].isEnabled)
        for name in ["balanced", "deep", "maximum"] {
            let level = app.buttons["localAnalysis.level.\(name)"]
            for _ in 0..<3 where !level.isHittable { app.swipeUp() }
            XCTAssertTrue(level.isEnabled, "All depths are available on the 6 GB base iPhone 15")
            level.tap()
            XCTAssertTrue(level.isSelected)
            XCTAssertTrue(app.staticTexts["localAnalysis.capacity.\(name)"].exists)
        }
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '8 GB'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '3 hours'")).firstMatch.exists)
        XCTAssertEqual(app.staticTexts["localAnalysis.capacity.balanced"].label, "About 9–14 games per night")
        XCTAssertTrue(app.staticTexts["Initial estimate for a 40-move game"].firstMatch.exists)
        capture("Base iPhone 15 with all depths and nightly capacity")
        app.terminate()
        app.launchArguments.removeAll { $0 == "--reset-local-analysis" }
        app.launch()
        openSettings()
        app.buttons["settings.localAnalysis"].tap()
        XCTAssertTrue(app.buttons["localAnalysis.level.maximum"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["localAnalysis.level.maximum"].isSelected)
    }

    func testGameReviewKeepsItsQueueWhenNavigatingAway() throws {
        let start = app.buttons["lesson.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 90))
        let complete = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["review.pause"])
        wait(for: [complete], timeout: 90)
        app.tabBars.buttons["Games"].tap()
        app.buttons.containing(.staticText, identifier: "Practice partner").firstMatch.tap()
        let review = app.buttons["game.deepReview"]
        for _ in 0..<8 where !review.isHittable { app.scrollViews["game.scroll"].swipeUp() }
        XCTAssertTrue(review.isHittable)
        app.buttons["game.localSettings"].tap()
        XCTAssertTrue(app.navigationBars["On-device analysis"].waitForExistence(timeout: 5))
        let night = app.switches["localAnalysis.overnight"]
        night.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(night.value as? String, "1")
        app.buttons["Done"].tap()
        for _ in 0..<4 where !review.isHittable { app.scrollViews["game.scroll"].swipeUp() }
        XCTAssertTrue(review.isEnabled, "A game queued for tonight can also be started immediately.")
        review.tap()
        let status = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'localAnalysis.status.'")).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        capture("Game analysis progress")
        app.navigationBars.buttons.firstMatch.tap()
        let queue = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'library.analysis.'")).firstMatch
        XCTAssertTrue(queue.waitForExistence(timeout: 5), app.debugDescription)
        capture("Analysis continues in the library")
    }

    func testCompletedCachedReviewShowsGraphAndQualityHighlightsWithoutRerunning() throws {
        try launchReviewedGameFixture(cached: true)
        app.tabBars.buttons["Games"].tap()
        app.buttons["game.open.reviewed-game"].tap()
        let graph = app.descendants(matching: .any)["game.evaluationPlot"]
        XCTAssertTrue(graph.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["game.deepReview"].exists)
        XCTAssertTrue(app.staticTexts["game.reviewStatus"].label.contains("ready"))
        XCTAssertFalse(app.staticTexts["Completed game"].exists)
        XCTAssertFalse(app.staticTexts["game.moment"].exists)
        let match = app.staticTexts["game.match"]
        let explore = app.buttons["game.explore"]
        XCTAssertEqual(match.frame.midY, explore.frame.midY, accuracy: 8)
        XCTAssertGreaterThan(explore.frame.minX, match.frame.minX)
        for name in ["excellent", "inaccuracy", "mistake", "blunder"] {
            let filter = app.buttons["game.quality.\(name)"]
            for _ in 0..<5 where !filter.isHittable || filter.frame.maxY > app.tabBars.firstMatch.frame.minY - 12 { app.scrollViews["game.scroll"].swipeUp() }
            XCTAssertTrue(filter.isEnabled)
            XCTAssertLessThanOrEqual(filter.frame.maxX, app.frame.maxX)
            XCTAssertGreaterThanOrEqual(filter.frame.minX, app.frame.minX)
            filter.tap()
            XCTAssertTrue(filter.isSelected)
            XCTAssertTrue((graph.value as? String ?? "").lowercased().contains(name))
        }
        XCTAssertFalse(app.buttons["game.quality.best"].exists)
        XCTAssertFalse(app.buttons["game.quality.good"].exists)
        capture("Completed review with highlighted blunders and unclipped extremes")
        app.buttons["game.quality.blunder"].tap()
        XCTAssertEqual(graph.value as? String, "All reviewed moves")
        for _ in 0..<6 where !explore.isHittable { app.scrollViews["game.scroll"].swipeDown() }
        explore.tap()
        let white = app.descendants(matching: .any)["game.clock.white"]
        let black = app.descendants(matching: .any)["game.clock.black"]
        XCTAssertTrue(white.waitForExistence(timeout: 5))
        XCTAssertTrue(white.label.contains("You"))
        XCTAssertTrue(black.label.contains("Practice partner"))
        XCTAssertFalse(app.staticTexts["Explore the game"].exists)
        XCTAssertFalse(app.staticTexts["Clocks after move"].exists)
        XCTAssertFalse(app.staticTexts["Imported moves"].exists)
        XCTAssertFalse(app.buttons["game.previousMove"].exists)
        XCTAssertFalse(app.buttons["game.nextMove"].exists)
        capture("Simplified replay with player clock tiles")
        for _ in 0..<8 where !app.staticTexts["Review ready"].isHittable { app.scrollViews["game.scroll"].swipeUp() }
        XCTAssertTrue(app.staticTexts["Review ready"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Waiting for tonight'")).firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["game.open.reviewed-game"].tap()
        XCTAssertTrue(graph.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["game.deepReview"].exists)
    }

    func testSavedOpeningMistakesBecomeBookMovesWithoutAnotherReview() throws {
        try launchReviewedGameFixture(cached: true, opening: true)
        app.tabBars.buttons["Games"].tap()
        app.buttons["game.open.reviewed-game"].tap()
        let opening = app.staticTexts["game.openingName"]
        XCTAssertTrue(opening.waitForExistence(timeout: 10))
        XCTAssertTrue(opening.label.contains("Ruy Lopez"))
        XCTAssertEqual(app.staticTexts["game.bookSummary"].label, "C78 · 9 book moves")
        XCTAssertFalse(app.buttons["game.deepReview"].exists)
        XCTAssertFalse(app.buttons["game.nextMoment"].exists)
        capture("Saved review recognizes the Ruy Lopez opening")
        app.buttons["game.explore"].tap()
        let first = app.buttons["game.move.1"]
        for _ in 0..<6 where !first.isHittable { app.scrollViews["game.scroll"].swipeUp() }
        XCTAssertTrue(first.label.contains("Book move"))
        first.tap()
        let grade = app.descendants(matching: .any)["game.moveQuality"]
        for _ in 0..<4 where !grade.isHittable { app.scrollViews["game.scroll"].swipeUp() }
        XCTAssertTrue(grade.exists && grade.label == "Book", app.debugDescription)
        for quality in ["excellent", "inaccuracy", "mistake", "blunder"] {
            let filter = app.buttons["game.quality.\(quality)"]
            XCTAssertTrue(filter.exists)
            XCTAssertFalse(filter.isEnabled)
        }
        capture("Book moves keep their evaluation graph without false mistake counts")
        let pawn = app.buttons["board.square.c7"]
        for _ in 0..<6 where !pawn.isHittable { app.scrollViews["game.scroll"].swipeDown() }
        pawn.tap()
        app.buttons["board.square.c5"].tap()
        let currentOpening = app.staticTexts["game.currentOpening"]
        for _ in 0..<6 where !currentOpening.isHittable { app.scrollViews["game.scroll"].swipeUp() }
        XCTAssertEqual(currentOpening.label, "Sicilian Defense")
        XCTAssertEqual(grade.label, "Book")
        XCTAssertEqual(app.staticTexts["game.variation"].label, "c5")
        XCTAssertTrue(app.buttons["game.move.2"].label.contains("e5"), "Trying another opening preserves the imported mainline")
        capture("Explored Sicilian variation is recognized as opening theory")
        app.buttons["game.return"].tap()
        XCTAssertFalse(app.staticTexts["game.variation"].exists)
    }

    private func launchReviewedGameFixture(cached: Bool, opening: Bool = false) throws {
        app.terminate()
        let now = Date().timeIntervalSinceReferenceDate
        let configurationID = "stockfish-d24-n100000-m32-t15.0-l120-a35-total5000000-threads2"
        let scores = opening ? [30, 30, 15, 20, 25] : [100_000, 50, -600, 1_000, -100_000]
        let qualities = ["excellent", "inaccuracy", "mistake", "inaccuracy", "blunder"]
        let played = ["e2e4", "g1f3", "f1b5", "b5a4", "e1g1"]
        let positions = [
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2",
            "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
            "r1bqkbnr/1ppp1ppp/p1n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4",
            "r1bqkb1r/1ppp1ppp/p1n2n2/4p3/B3P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 2 5"
        ]
        let assessments: [[String: Any]] = (0..<5).map { index in
            ["ply": index * 2, "positionFEN": opening ? positions[index] : positions[index].replacingOccurrences(of: "pppppppp", with: "ppppppp1").replacingOccurrences(of: "pppp1ppp", with: "pppp1pp1").replacingOccurrences(of: "1ppp1ppp", with: "1ppp1pp1"),
             "playedMove": played[index], "bestMove": played[index], "quality": qualities[index],
             "centipawnLoss": 100, "whiteScore": scores[index], "completedDepth": 24, "isProvisional": true]
        }
        let review: [String: Any] = ["gameID": "reviewed-game", "findings": [], "analyzedPlies": 5, "totalPlies": 5,
            "source": "device", "completedAt": now, "engineVersion": "stockfish-19-1a298aa575a0-chessme-v1",
            "configurationID": configurationID, "moveAssessments": assessments]
        let job: [String: Any] = ["id": "reviewed-job", "gameID": "reviewed-game", "level": "balanced", "nightOnly": true,
            "requiresPro": false, "createdAt": now - 60, "state": "completed", "checkpoint": review,
            "message": "Waiting for tonight and charging",
            "configuration": ["engine": "stockfish", "depth": 24, "nodesPerCandidate": 100_000, "memoryMB": 32,
                              "secondsPerPosition": 15, "topMoves": 2, "searchNodeLimit": 5_000_000, "engineThreads": 2]]
        var game: [String: Any] = ["id": "reviewed-game", "username": "You", "white": "You", "black": "Practice partner",
                       "playedAt": now - 60, "playerSide": "white", "moves": "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O", "status": "resign",
                       "clockData": ["initialSeconds": 300, "incrementSeconds": 3, "source": "lichess",
                                     "remainingCentiseconds": [30_000, 30_000, 29_000, 29_500, 28_500, 29_000, 28_000, 27_500, 26_000]]]
        if !opening { game["initialFEN"] = positions[0].replacingOccurrences(of: "pppppppp", with: "ppppppp1") }
        let fixture: [String: Any] = [
            "games": [game],
            "analyses": cached ? [] : [review], "localAnalysisJobs": [job], "practice": [], "isDemo": true, "skippedGames": 0]
        app.launchArguments = ["--ui-testing", "--reset-engine", "--reset-evaluation", "--reset-local-analysis"]
        app.launchEnvironment["CHESSME_UI_TEST_LIBRARY"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launch()
    }

    func testSelectedNightQueueAndCancellationLeaveOtherGamesUnchanged() throws {
        try launchQueueFixture()
        app.tabBars.buttons["Games"].tap()
        let first = app.descendants(matching: .any)["library.analysis.demo-queue-a"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.contains("Not analyzed"))
        app.buttons["games.addAnalysis"].tap()
        chooseAnalysisSchedule("games.queueNight")
        analysisSelection("demo-queue-a").tap()
        XCTAssertEqual(analysisSelection("demo-queue-a").value as? String, "Selected")
        app.buttons["analysis.cancel"].tap()
        XCTAssertTrue(first.label.contains("Not analyzed"))
        app.buttons["games.addAnalysis"].tap()
        chooseAnalysisSchedule("games.queueNight")
        analysisSelection("demo-queue-a").tap()
        XCTAssertEqual(analysisSelection("demo-queue-a").value as? String, "Selected")
        capture("Choose individual games for night analysis")
        app.buttons["analysis.save"].tap()
        capture("Night queue immediately after Save")
        let queued = expectation(for: NSPredicate(format: "label CONTAINS 'Night analysis queued'"), evaluatedWith: first)
        wait(for: [queued], timeout: 5)
        XCTAssertTrue(app.descendants(matching: .any)["library.analysis.demo-queue-b"].label.contains("Not analyzed"))
        XCTAssertFalse(app.staticTexts["Queued for tonight"].exists)
        XCTAssertFalse(app.staticTexts["Queued on device"].exists)
        capture("Games show recorded results and visual queue status")
        app.buttons["game.open.demo-queue-a"].tap()
        XCTAssertEqual(app.staticTexts["game.match"].label, "You vs Aster")
        XCTAssertTrue(app.descendants(matching: .any)["game.result"].label.contains("won"))
        capture("Winning game review uses You and the opponent")
    }

    func testSelectedGamesCanStartImmediateAnalysis() throws {
        try launchQueueFixture()
        app.tabBars.buttons["Games"].tap()
        app.buttons["games.addAnalysis"].tap()
        chooseAnalysisSchedule("games.queueNow")
        analysisSelection("demo-queue-b").tap()
        XCTAssertEqual(analysisSelection("demo-queue-b").value as? String, "Selected")
        app.buttons["analysis.save"].tap()
        let selected = app.descendants(matching: .any)["library.analysis.demo-queue-b"]
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        let admitted = expectation(for: NSPredicate(format: "label CONTAINS 'Device analysis' OR label CONTAINS 'review ready' OR label CONTAINS 'Analysis queued'"), evaluatedWith: selected)
        wait(for: [admitted], timeout: 10)
        XCTAssertFalse(selected.label.contains("Night analysis"))
        XCTAssertTrue(app.descendants(matching: .any)["library.analysis.demo-queue-a"].label.contains("Not analyzed"))
        capture("Immediate device analysis has a progress indicator")
    }

    func testSavedFilterSlidesBothWaysAndMainHeadersHaveOneTitle() throws {
        try launchQueueFixture()
        XCTAssertEqual(app.staticTexts["app.title"].label, "Today")
        XCTAssertFalse(app.staticTexts["chess-me"].exists)
        app.tabBars.buttons["Games"].tap()
        XCTAssertEqual(app.staticTexts["app.title"].label, "Games")
        let saved = app.buttons["games.saved"]
        let original = saved.frame.minX
        saved.tap()
        XCTAssertEqual(saved.value as? String, "Selected")
        XCTAssertLessThan(saved.frame.minX, original - 70)
        XCTAssertTrue(saved.isHittable)
        XCTAssertTrue(app.buttons["game.open.demo-queue-a"].exists)
        XCTAssertFalse(app.buttons["game.open.demo-queue-b"].exists)
        capture("Saved games control moves with its heart to the left")
        saved.tap()
        XCTAssertEqual(saved.value as? String, "Not selected")
        let returned = expectation(for: NSPredicate { _, _ in abs(saved.frame.minX - original) < 2 }, evaluatedWith: saved)
        wait(for: [returned], timeout: 5)
        XCTAssertTrue(app.buttons["game.open.demo-queue-b"].exists)
        capture("Saved games control returns to the right")
        app.tabBars.buttons["Practice"].tap()
        XCTAssertEqual(app.staticTexts["app.title"].label, "Practice")
        XCTAssertFalse(app.staticTexts["chess-me"].exists)
    }

    private func launchQueueFixture() throws {
        app.terminate()
        let now = Date().timeIntervalSinceReferenceDate
        let games: [[String: Any]] = ["Aster", "Birch", "Cedar"].enumerated().map { index, name in
            ["id": "demo-queue-\(["a", "b", "c"][index])", "username": "Learner", "white": "Learner", "black": name,
             "playedAt": now - Double(index + 1) * 60, "playerSide": "white", "moves": "e4 e5 Nf3 Nc6", "status": "resign",
             "result": ["1-0", "0-1", "1/2-1/2"][index]]
        }
        let review: [String: Any] = ["gameID": "demo-queue-c", "findings": [], "analyzedPlies": 2, "totalPlies": 2,
                                     "source": "cloud", "completedAt": now, "engineVersion": "ui-demonstration"]
        let fixture: [String: Any] = ["games": games, "analyses": [review], "practice": [], "isDemo": true,
                                     "favoriteGameIDs": ["demo-queue-a"], "skippedGames": 0]
        app.launchArguments = ["--ui-testing", "--reset-engine", "--reset-evaluation", "--reset-local-analysis"]
        app.launchEnvironment["CHESSME_UI_TEST_LIBRARY"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launch()
    }

    private func chooseAnalysisSchedule(_ identifier: String) {
        // iOS 27 exposes both a popup wrapper and its actionable menu item.
        let choices = app.descendants(matching: .any).matching(identifier: identifier)
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 5))
        choices.element(boundBy: choices.count - 1).tap()
        XCTAssertTrue(app.buttons["analysis.save"].waitForExistence(timeout: 5))
    }

    private func analysisSelection(_ gameID: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "analysis.select.\(gameID)").firstMatch
    }

    private func board(_ design: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "board.design.\(design)").firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
