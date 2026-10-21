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

    func testTodayOffersPuzzlesAndOpeningPractice() throws {
        try launchQueueFixture()
        let puzzles = app.buttons["today.puzzles"]
        for _ in 0..<4 where !puzzles.isHittable { app.scrollViews["main.scroll"].swipeUp() }
        XCTAssertTrue(puzzles.isHittable)
        capture("Today practice shortcuts")
        puzzles.tap()
        XCTAssertTrue(app.navigationBars["Related puzzles"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["today.openings"].tap()
        XCTAssertTrue(app.staticTexts["openings.coverage"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'For Learner'")).firstMatch.exists)
        capture("Opening practice without player preamble")
    }

    func testTimeControlFiltersGamesAndManualAnalysisSelection() throws {
        try launchQueueFixture(pendingJobs: true)
        app.tabBars.buttons["Games"].tap()
        XCTAssertEqual(app.buttons["games.reviewed"].value as? String, "All")
        capture("Games with vivid win and loss colors")
        app.buttons["games.speed"].tap()
        chooseMenuItem("games.speed.bullet")
        XCTAssertTrue(app.buttons["game.open.demo-queue-a"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["game.open.demo-queue-b"].exists)
        capture("Games filtered to bullet with vivid player results")
        app.buttons["games.addAnalysis"].tap()
        chooseAnalysisSchedule("games.queueNight")
        XCTAssertTrue(analysisSelection("demo-queue-a").waitForExistence(timeout: 5))
        XCTAssertFalse(analysisSelection("demo-queue-b").exists)
        XCTAssertTrue(app.buttons["analysis.speed"].exists)
        capture("Manual analysis respects the selected time control")
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

    func testGameAllowsAnimatedVariationsAndReturnsToOriginalTimeline() throws {
        XCTAssertTrue(app.buttons["lesson.start"].waitForExistence(timeout: 90))
        app.tabBars.buttons["Games"].tap()
        let game = app.buttons["game.open.demo-missed-mate"]
        XCTAssertTrue(game.waitForExistence(timeout: 5), app.debugDescription)
        game.tap()
        enterReplay()
        let e2 = app.buttons["board.square.e2"]
        XCTAssertTrue(e2.waitForExistence(timeout: 10))
        e2.tap()
        XCTAssertEqual(e2.value as? String, "Selected")
        e2.tap()
        XCTAssertNotEqual(e2.value as? String, "Selected", "Deselecting preserves any current engine highlight")
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

    func testReviewClocksFollowMovesAndDoNotAssignTimesToVariations() {
        XCTAssertTrue(app.buttons["lesson.start"].waitForExistence(timeout: 90))
        app.tabBars.buttons["Games"].tap()
        let game = app.buttons["game.open.demo-missed-mate"]
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
        app.buttons["game.open.\(try XCTUnwrap(game["id"] as? String))"].tap()
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
        XCTAssertTrue(app.descendants(matching: .any)["engine.device"].label.contains("Arasan"), app.debugDescription)
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
        XCTAssertTrue(app.descendants(matching: .any)["practice.board"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["analysis.evaluation"].exists)
        app.buttons["practice.options"].tap()
        let reveal = app.buttons["practice.reveal"]
        for _ in 0..<5 where !reveal.isHittable { app.swipeUp() }
        reveal.tap()
        let explore = app.buttons["practice.explorePuzzle"]
        for _ in 0..<7 where !explore.isHittable { app.swipeUp() }
        explore.tap()
        XCTAssertTrue(app.descendants(matching: .any)["analysis.panel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["analysis.evaluation"].exists)
        openPracticeHome()
        app.buttons["openings.open"].tap()
        XCTAssertTrue(app.staticTexts["openings.coverage"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["openings.coverage"].label, "0 / 30 openings reviewed")
        capture("Opening sample threshold")
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
        for _ in 0..<4 where !app.buttons["localAnalysis.level.maximum"].exists { app.swipeUp() }
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
        for _ in 0..<4 where !app.buttons["localAnalysis.level.maximum"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["localAnalysis.level.maximum"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["localAnalysis.level.maximum"].isSelected)
    }

    func testGameReviewKeepsItsQueueWhenNavigatingAway() throws {
        let start = app.buttons["lesson.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 90))
        let complete = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["review.pause"])
        wait(for: [complete], timeout: 90)
        app.tabBars.buttons["Games"].tap()
        app.buttons["game.open.demo-missed-mate"].tap()
        enterReplay()
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
        app.navigationBars.buttons.firstMatch.tap()
        let queue = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'library.analysis.'")).firstMatch
        XCTAssertTrue(queue.waitForExistence(timeout: 5), app.debugDescription)
        capture("Analysis continues in the library")
    }

    func testCompletedCachedReviewShowsGraphAndQualityHighlightsWithoutRerunning() throws {
        try launchReviewedGameFixture(cached: true)
        app.tabBars.buttons["Games"].tap()
        app.buttons["game.open.reviewed-game"].tap()
        enterReplay()
        let graph = app.descendants(matching: .any)["game.evaluationPlot"]
        XCTAssertTrue(graph.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["game.deepReview"].exists)
        XCTAssertTrue(app.staticTexts["game.reviewStatus"].label.contains("ready"))
        XCTAssertFalse(app.staticTexts["Completed game"].exists)
        XCTAssertFalse(app.staticTexts["game.moment"].exists)
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
        for _ in 0..<6 where !app.descendants(matching: .any)["game.clock.white"].isHittable { app.scrollViews["game.scroll"].swipeDown() }
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
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["game.open.reviewed-game"].tap()
        enterReplay()
        XCTAssertTrue(graph.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["game.deepReview"].exists)
    }

    func testSavedOpeningMistakesBecomeBookMovesWithoutAnotherReview() throws {
        try launchReviewedGameFixture(cached: true, opening: true)
        app.tabBars.buttons["Games"].tap()
        app.buttons["game.open.reviewed-game"].tap()
        enterReplay()
        let opening = app.staticTexts["game.openingName"]
        XCTAssertTrue(opening.waitForExistence(timeout: 10))
        XCTAssertTrue(opening.label.contains("Ruy Lopez"))
        XCTAssertEqual(app.staticTexts["game.bookSummary"].label, "C78 · 9 book moves")
        XCTAssertFalse(app.buttons["game.deepReview"].exists)
        XCTAssertFalse(app.buttons["game.nextMoment"].exists)
        capture("Saved review recognizes the Ruy Lopez opening")
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
        let configurationID = "arasan-d24-n100000-m32-t15.0-l120-a35-total5000000-threads1"
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
        let assessments = positions.indices.map { index -> [String: Any] in
            var fen = positions[index]
            if !opening {
                fen = fen.replacingOccurrences(of: "pppppppp", with: "ppppppp1")
                fen = fen.replacingOccurrences(of: "pppp1ppp", with: "pppp1pp1")
                fen = fen.replacingOccurrences(of: "1ppp1ppp", with: "1ppp1pp1")
            }
            return ["ply": index * 2, "positionFEN": fen, "playedMove": played[index],
                    "bestMove": ["d2d4", "b1c3", "d2d4", "d2d4", "d2d4"][index], "quality": qualities[index], "centipawnLoss": 100,
                    "whiteScore": scores[index], "bestWhiteScore": opening ? scores[index] + 100 : [100_000, 150, -150, 1100, -400][index],
                    "completedDepth": 24, "isProvisional": true]
        }
        let review: [String: Any] = ["gameID": "reviewed-game", "findings": [], "analyzedPlies": 5, "totalPlies": 5,
            "source": "device", "completedAt": now, "engineVersion": "arasan-26.0-v8-20260622",
            "configurationID": configurationID, "moveAssessments": assessments]
        let job: [String: Any] = ["id": "reviewed-job", "gameID": "reviewed-game", "level": "balanced", "nightOnly": true,
            "requiresPro": false, "createdAt": now - 60, "state": "completed", "checkpoint": review,
            "message": "Waiting for tonight and charging",
            "configuration": ["engine": "arasan", "depth": 24, "nodesPerCandidate": 100_000, "memoryMB": 32,
                              "secondsPerPosition": 15, "topMoves": 2, "searchNodeLimit": 5_000_000, "engineThreads": 1]]
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
        XCTAssertTrue(app.staticTexts["game.match"].label.contains("You vs Aster"))
        XCTAssertTrue(app.staticTexts["game.match"].label.contains("won"))
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
        let originalY = saved.frame.minY
        let originalGap = originalY - app.buttons["games.addAnalysis"].frame.maxY
        XCTAssertGreaterThan(saved.frame.minX, app.buttons["games.reviewed"].frame.maxX)
        saved.tap()
        XCTAssertEqual(saved.value as? String, "Selected")
        XCTAssertLessThan(saved.frame.minX, original - 70)
        XCTAssertTrue(saved.isHittable)
        XCTAssertTrue(app.buttons["game.open.demo-queue-a"].exists)
        let filtered = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["game.open.demo-queue-b"])
        wait(for: [filtered], timeout: 5)
        XCTAssertEqual(saved.frame.minY, originalY, accuracy: 2)
        XCTAssertEqual(saved.frame.minY - app.buttons["games.addAnalysis"].frame.maxY, originalGap, accuracy: 2)
        XCTAssertLessThan(originalGap, 40)
        XCTAssertTrue(app.buttons["games.reviewed"].isHittable)
        capture("Saved games control moves with its heart to the left")
        saved.tap()
        XCTAssertEqual(saved.value as? String, "Not selected")
        let returned = expectation(for: NSPredicate { _, _ in abs(saved.frame.minX - original) < 2 }, evaluatedWith: saved)
        wait(for: [returned], timeout: 5)
        XCTAssertTrue(app.buttons["game.open.demo-queue-b"].exists)
        XCTAssertEqual(saved.frame.minY, originalY, accuracy: 2)
        capture("Saved games control returns to the right")
        app.tabBars.buttons["Practice"].tap()
        XCTAssertEqual(app.staticTexts["app.title"].label, "Practice")
        XCTAssertFalse(app.staticTexts["chess-me"].exists)
    }

    func testReviewedFilterCombinesWithSavedAndKeepsPartialReviewsOut() throws {
        try launchQueueFixture(cachedReview: true)
        app.tabBars.buttons["Games"].tap()
        let reviewed = app.buttons["games.reviewed"]
        XCTAssertTrue(reviewed.isHittable)
        reviewed.tap()
        chooseMenuItem("games.reviewed.reviewed")
        XCTAssertEqual(reviewed.value as? String, "Reviewed")
        XCTAssertTrue(app.buttons["game.open.demo-queue-c"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["game.open.demo-queue-a"].exists, "A partial review is still pending")
        XCTAssertTrue(app.buttons["game.open.demo-queue-b"].exists)
        capture("Reviewed filter shows complete cached reviews")
        reviewed.tap()
        chooseMenuItem("games.reviewed.cloud")
        XCTAssertEqual(reviewed.value as? String, "Cloud reviewed")
        XCTAssertTrue(app.buttons["game.open.demo-queue-b"].exists)
        XCTAssertFalse(app.buttons["game.open.demo-queue-c"].exists)
        capture("Cloud reviews filter")
        reviewed.tap()
        chooseMenuItem("games.reviewed.local")
        XCTAssertEqual(reviewed.value as? String, "Local reviewed")
        XCTAssertTrue(app.buttons["game.open.demo-queue-c"].exists)
        XCTAssertFalse(app.buttons["game.open.demo-queue-b"].exists)
        XCTAssertFalse(app.buttons["game.open.demo-queue-a"].exists)
        capture("Local reviews filter excludes partial analysis")
        app.buttons["games.saved"].tap()
        XCTAssertTrue(app.buttons["game.open.demo-queue-c"].exists)
        XCTAssertFalse(app.buttons["game.open.demo-queue-a"].exists)
        reviewed.tap()
        chooseMenuItem("games.reviewed.clear")
        XCTAssertTrue(app.buttons["game.open.demo-queue-a"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["game.open.demo-queue-c"].exists)
        app.buttons["games.saved"].tap()
        XCTAssertTrue(app.buttons["game.open.demo-queue-b"].waitForExistence(timeout: 5))
        capture("Saved and Reviewed filters can be combined and cleared")
    }

    func testYearFilterAndLongOpponentKeepTheirControlsVisible() throws {
        try launchQueueFixture(window: "year", longOpponent: true)
        app.tabBars.buttons["Games"].tap()
        let period = app.buttons["games.period"]
        let title = period.staticTexts["365 days"]
        XCTAssertTrue(title.exists)
        XCTAssertTrue(period.frame.contains(title.frame), "365 days must fit inside its filter")
        XCTAssertTrue(app.buttons["games.saved"].isHittable)
        XCTAssertGreaterThan(app.buttons["games.saved"].frame.minX, app.buttons["games.reviewed"].frame.maxX)
        capture("365 days Reviewed and Saved filters fit on iPhone 15")
        app.buttons["game.open.demo-queue-a"].tap()
        let explore = app.buttons["game.explore"]
        XCTAssertTrue(explore.waitForExistence(timeout: 5))
        XCTAssertTrue(explore.isHittable)
        XCTAssertEqual(explore.label, "Explore game")
        XCTAssertGreaterThan(explore.frame.width, 45)
        XCTAssertTrue(app.staticTexts["game.match"].exists)
        capture("Long opponent name truncates while Explore stays fully visible")
        explore.tap()
        XCTAssertEqual(explore.label, "Return to review")
    }

    func testTodayShowsPerGameProgressAndOpensTheRunningAndNightGames() throws {
        try launchQueueFixture(pendingJobs: true)
        let scroll = app.scrollViews["main.scroll"]
        let running = app.descendants(matching: .any).matching(identifier: "today.analysis.open.demo-queue-b").firstMatch
        for _ in 0..<3 where !running.isHittable { scroll.swipeUp() }
        XCTAssertTrue(running.isHittable, app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["library.analysis.demo-queue-b"].label.contains("50 percent"))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "today.analysis.open.demo-queue-c").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "today.analysis.open.demo-queue-a").firstMatch.exists)
        capture("Today shows the running game and individual queued games")
        running.tap()
        XCTAssertTrue(app.staticTexts["game.match"].label.contains("You vs Birch"))
        XCTAssertTrue(app.buttons["game.explore"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        let more = app.descendants(matching: .any).matching(identifier: "today.analysisMore").firstMatch
        for _ in 0..<3 where !more.isHittable { scroll.swipeUp() }
        XCTAssertTrue(more.isHittable)
        more.tap()
        let night = app.descendants(matching: .any).matching(identifier: "today.analysis.open.demo-queue-e").firstMatch
        for _ in 0..<3 where !night.isHittable { scroll.swipeUp() }
        XCTAssertTrue(night.isHittable)
        capture("A longer Today queue expands to every queued game")
        night.tap()
        XCTAssertTrue(app.staticTexts["game.match"].label.contains("You vs Elm"))
    }

    private func launchQueueFixture(cachedReview: Bool = false, pendingJobs: Bool = false, window: String? = nil, longOpponent: Bool = false) throws {
        app.terminate()
        let now = Date().timeIntervalSinceReferenceDate
        let ids = ["demo-queue-a", "demo-queue-b", "demo-queue-c", "demo-queue-d", "demo-queue-e"]
        let results = ["1-0", "0-1", "1/2-1/2", "1-0", "0-1"]
        var names = pendingJobs ? ["Aster", "Birch", "Cedar", "Dahlia", "Elm"] : ["Aster", "Birch", "Cedar"]
        if longOpponent { names[0] = "ExtraordinarilyLongOpponentNameThatShouldNeverHideExplore" }
        let games = names.enumerated().map { index, name -> [String: Any] in
            let playedAt = now - Double(index + 1) * 60
            return ["id": ids[index], "username": "Learner", "white": "Learner", "black": name,
                    "playedAt": playedAt, "playerSide": "white", "moves": "e4 e5 Nf3 Nc6", "status": "resign",
                    "result": results[index], "speed": ["bullet", "blitz", "rapid", "classical", "rapid"][index]]
        }
        let review: [String: Any] = ["gameID": "demo-queue-c", "findings": [], "analyzedPlies": 2, "totalPlies": 2,
                                     "source": "cloud", "completedAt": now, "engineVersion": "ui-demonstration"]
        var fixture: [String: Any] = ["games": games, "analyses": [review], "practice": [], "isDemo": true,
                                     "favoriteGameIDs": ["demo-queue-a"], "skippedGames": 0]
        let configuration: [String: Any] = ["engine": "arasan", "depth": 24, "nodesPerCandidate": 100_000,
            "memoryMB": 32, "secondsPerPosition": 15, "topMoves": 2, "searchNodeLimit": 5_000_000, "engineThreads": 1]
        if cachedReview {
            var cached = review
            cached["source"] = "device"
            let partial: [String: Any] = ["gameID": ids[0], "findings": [], "analyzedPlies": 1, "totalPlies": 2,
                                         "source": "device", "completedAt": now, "engineVersion": "ui-demonstration"]
            let job: [String: Any] = ["id": "cached-complete", "gameID": ids[2], "level": "balanced", "nightOnly": true,
                "requiresPro": false, "createdAt": now - 60, "state": "completed", "checkpoint": cached, "configuration": configuration]
            var cloud = review
            cloud["gameID"] = ids[1]
            fixture["analyses"] = [partial, cloud]
            fixture["localAnalysisJobs"] = [job]
            fixture["favoriteGameIDs"] = [ids[0], ids[2]]
        }
        if pendingJobs {
            let jobs = ids.enumerated().map { index, id -> [String: Any] in
                var job: [String: Any] = ["id": "queue-\(index)", "gameID": id, "level": "balanced", "nightOnly": index != 1 && index != 2,
                    "requiresPro": true, "createdAt": now + Double(index), "state": index == 1 ? "running" : "queued", "configuration": configuration]
                if index == 1 {
                    job["checkpoint"] = ["gameID": id, "findings": [], "analyzedPlies": 1, "totalPlies": 2,
                        "source": "device", "completedAt": now, "engineVersion": "ui-demonstration"] as [String: Any]
                }
                return job
            }
            fixture["localAnalysisJobs"] = jobs
        }
        app.launchArguments = ["--ui-testing", "--reset-engine", "--reset-evaluation", "--reset-local-analysis"]
        app.launchEnvironment["CHESSME_UI_TEST_LIBRARY"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launchEnvironment["CHESSME_UI_TEST_WINDOW"] = window
        app.launch()
    }

    private func chooseAnalysisSchedule(_ identifier: String) {
        let choices = app.descendants(matching: .any).matching(identifier: identifier)
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 5))
        let item = choices.element(boundBy: choices.count - 1)
        XCTAssertLessThan(item.frame.minY, app.buttons["games.addAnalysis"].frame.maxY + 150,
                          "The schedule selector should open beside Add for analysis")
        capture("Analysis schedule menu is anchored to Add for analysis")
        chooseMenuItem(identifier)
        XCTAssertTrue(app.buttons["analysis.save"].waitForExistence(timeout: 5))
    }

    private func chooseMenuItem(_ identifier: String) {
        // iOS 27 exposes both a popup wrapper and its actionable menu item.
        let choices = app.descendants(matching: .any).matching(identifier: identifier)
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 5))
        choices.element(boundBy: choices.count - 1).tap()
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
