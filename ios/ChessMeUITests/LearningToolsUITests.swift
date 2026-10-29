import XCTest

final class LearningToolsUITests: XCTestCase {
    private var app: XCUIApplication!
    private let initialFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-design", "--reset-engine", "--reset-local-analysis", "--reduce-motion"]
    }

    override func tearDownWithError() throws { app.terminate(); app = nil }

    func testPositionStudyNeedsNoImportAndPreservesBoardAfterInvalidFEN() {
        app.launch()
        app.tabBars.buttons["Practice"].tap()
        tap("practice.analysis")
        XCTAssertTrue(app.staticTexts["workspace.status"].waitForExistence(timeout: 5))
        move("e2", "e4")
        XCTAssertEqual(app.staticTexts["workspace.line"].label, "e4")
        tap("workspace.undo")
        XCTAssertEqual(app.staticTexts["workspace.status"].label, "White to move")
        tap("workspace.fenDisclosure")
        let input = app.textFields["workspace.fenInput"]
        reveal(input); input.tap(); input.typeText("invalid FEN")
        tap("workspace.loadFEN")
        XCTAssertTrue(app.staticTexts["workspace.error"].exists)
        XCTAssertEqual(app.staticTexts["workspace.status"].label, "White to move")
        capture("Position study rejects invalid input")
    }

    func testFundamentalMateAndGuidedRetryAreDistinct() {
        app.launch()
        app.tabBars.buttons["Practice"].tap()
        tap("practice.fundamentals")
        tap("fundamentals.lesson.back-rank")
        tap("fundamentals.start")
        tap("fundamentals.hint")
        move("a1", "a8")
        XCTAssertTrue(app.staticTexts["fundamentals.feedback"].label.contains("Guided"))
        tap("fundamentals.retry")
        move("a1", "a8")
        XCTAssertEqual(app.staticTexts["fundamentals.feedback"].label, "Solved independently.")
        capture("Original checkmate exercise complete")
    }

    func testPuzzleDiscoveryAndOfflineCollectionsAreAvailableWithoutGames() {
        app.launch()
        app.tabBars.buttons["Practice"].tap()
        tap("practice.puzzles")
        XCTAssertTrue(app.buttons["training.find"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["training.difficulty"].exists || app.steppers["training.difficulty"].exists)
        app.segmentedControls["training.collection"].buttons["Saved"].tap()
        XCTAssertTrue(app.staticTexts["Saved on this device for offline practice."].exists)
        app.segmentedControls["training.collection"].buttons["Retry"].tap()
        XCTAssertTrue(app.staticTexts["No failed puzzles are available in these collections."].exists)
        capture("Puzzle discovery with offline collections")
    }

    func testSavedLineRehearsalIncludesPacedReplyAndCleanResult() throws {
        try launchLibrary()
        app.tabBars.buttons["Games"].tap()
        tap("games.savedLines")
        tap("lines.open.tools-line")
        tap("lines.rehearse")
        XCTAssertTrue(app.staticTexts["rehearsal.progress"].waitForExistence(timeout: 5))
        move("e2", "e4")
        let reply = NSPredicate(format: "label == %@", "1 of 2 moves recalled")
        expectation(for: reply, evaluatedWith: app.staticTexts["rehearsal.progress"])
        waitForExpectations(timeout: 5)
        let f3 = app.buttons["board.square.f3"]
        let replySettled = NSPredicate { _, _ in
            !self.app.staticTexts["Showing the other side's saved reply…"].exists
        }
        expectation(for: replySettled, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        move("g1", "f3")
        XCTAssertTrue(f3.exists)
        XCTAssertEqual(app.staticTexts["rehearsal.result"].label, "Completed without help or retries")
        capture("Saved line recalled with automatic reply")
    }

    func testArchiveSearchAndMainlineExportUseTheOriginalGame() throws {
        try launchLibrary()
        app.tabBars.buttons["Games"].tap()
        let search = app.textFields["games.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("NoSuchOpponent\n")
        XCTAssertFalse(app.buttons["game.open.demo-tools-game"].exists)
        tap("games.clearFilters")
        tap("game.open.demo-tools-game")
        tap("review.options")
        tap("review.export")
        XCTAssertTrue(app.buttons["export.copy"].waitForExistence(timeout: 5))
        let notation = app.staticTexts["export.notation"].label
        XCTAssertTrue(notation.contains("1. e4 e5 2. Nf3 Nc6 1-0"))
        XCTAssertTrue(notation.contains("[Black \"Practice partner\"]"))
        capture("Mainline PGN ready to copy or save")
    }

    func testExternalPlayAndEmptyInsightsAreDiscoverable() {
        app.launch()
        app.tabBars.buttons["Games"].tap()
        tap("games.insights")
        XCTAssertTrue(app.staticTexts["No personal games yet"].waitForExistence(timeout: 5))
        capture("Insights explains its saved-game scope")
        app.tabBars.buttons["Today"].tap()
        let play = app.links["today.playLichess"]
        reveal(play)
        XCTAssertTrue(play.exists || app.buttons["today.playLichess"].exists)
        if play.exists { play.tap() } else { app.buttons["today.playLichess"].tap() }
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))
        let external = XCTAttachment(screenshot: safari.screenshot())
        external.name = "Play on Lichess opens the external browser"
        external.lifetime = .keepAlways
        add(external)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
    }

    func testSavedLinePGNHasStudyResultAndOpensFileExport() throws {
        try launchLibrary()
        app.tabBars.buttons["Games"].tap()
        tap("games.savedLines")
        tap("lines.open.tools-line")
        tap("lines.export")
        XCTAssertTrue(app.staticTexts["export.notation"].waitForExistence(timeout: 5))
        let notation = app.staticTexts["export.notation"].label
        XCTAssertTrue(notation.contains("[Result \"*\"]"))
        XCTAssertTrue(notation.contains("1. e4 e5 2. Nf3 *"))
        tap("export.file")
        let save = app.buttons["DOCPicker.actionButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertEqual(save.label, "Save")
        capture("Saved variation exports as a PGN study file")
        save.tap()
        let dismissed = NSPredicate(format: "exists == false")
        expectation(for: dismissed, evaluatedWith: save)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.staticTexts["export.notation"].exists)
    }

    func testOpeningExplorerExcludesSampleGameResults() throws {
        try launchLibrary()
        app.tabBars.buttons["Practice"].tap()
        tap("openings.open")
        tap("openings.explorer")
        XCTAssertTrue(app.staticTexts["Import completed games to explore your opening moves. Demonstration games do not count toward your personal results."].waitForExistence(timeout: 5))
        capture("Personal opening explorer excludes sample results")
    }

    func testPositionStudyControlsFitWithLargestAccessibilityText() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.tabBars.buttons["Practice"].tap()
        tap("practice.analysis")
        let flip = app.buttons["workspace.flip"]
        reveal(flip)
        XCTAssertTrue(flip.isHittable)
        XCTAssertLessThanOrEqual(flip.frame.maxX, app.frame.maxX)
        XCTAssertGreaterThanOrEqual(app.buttons["workspace.undo"].frame.minX, 0)
        for id in ["workspace.undo", "workspace.reset", "workspace.flip"] {
            XCTAssertLessThan(app.buttons[id].frame.height, 100, "A control label should not wrap by character")
        }
        capture("Position study with largest accessibility text")
    }

    private func launchLibrary() throws {
        let now = Date().timeIntervalSinceReferenceDate
        let game: [String: Any] = ["id": "demo-tools-game", "username": "Learner", "white": "Learner", "black": "Practice partner",
            "playedAt": now, "playerSide": "white", "moves": "e4 e5 Nf3 Nc6", "status": "resign", "result": "1-0", "speed": "rapid"]
        let line: [String: Any] = ["id": "tools-line", "gameID": "demo-tools-game", "gameLabel": "Learner vs Practice partner",
            "username": "Learner", "playerSide": "white", "initialFEN": initialFEN, "prefix": [],
            "moves": ["e2e4", "e7e5", "g1f3"], "positionFEN": initialFEN, "repetitionHistory": [],
            "openingFamily": "King's pawn", "savedAt": now, "title": "My center line"]
        let fixture: [String: Any] = ["games": [game], "analyses": [], "practice": [], "isDemo": true, "skippedGames": 0,
            "review": ["savedLines": [line]]]
        app.launchEnvironment["CHESSME_UI_TEST_LIBRARY"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launch()
    }

    private func move(_ from: String, _ to: String) {
        tap("board.square.\(from)"); tap("board.square.\(to)")
    }
    private func tap(_ id: String) {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        if !element.exists { reveal(element) }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing \(id)")
        reveal(element); element.tap()
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            guard app.scrollViews.firstMatch.exists else { return }
            app.scrollViews.firstMatch.swipeUp()
        }
    }
    private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = title; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
