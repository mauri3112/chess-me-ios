import XCTest

final class LearningToolsReviewUITests: XCTestCase {
    private var app: XCUIApplication!
    private let initialFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-design", "--reset-engine", "--reset-local-analysis", "--reduce-motion"]
    }

    override func tearDownWithError() throws { app.terminate(); app = nil }

    func testPopulatedInsightsAndOpeningTreeRespectPlayerAndMoveFilters() throws {
        try launchLibrary()
        app.tabBars.buttons["Games"].tap()
        tap("games.insights")
        XCTAssertTrue(app.staticTexts["3 unique finished games saved"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1 won · 1 drawn · 1 lost"].exists)
        tap("insights.player")
        app.buttons["OtherLearner"].tap()
        XCTAssertTrue(app.staticTexts["1 unique finished games saved"].waitForExistence(timeout: 10))
        capture("Populated insights after changing player")

        app.tabBars.buttons["Practice"].tap()
        tap("openings.open")
        tap("openings.explorer")
        let result = app.staticTexts["openingExplorer.results"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertEqual(result.label, "3 games · 1 W / 1 D / 1 L / 0 ?")
        tap("openingExplorer.move.e2e4")
        XCTAssertEqual(result.label, "2 games · 1 W / 1 D / 0 L / 0 ?")
        tap("openingExplorer.reset")
        XCTAssertEqual(result.label, "3 games · 1 W / 1 D / 1 L / 0 ?")
        reveal(app.segmentedControls["openingExplorer.color"])
        app.segmentedControls["openingExplorer.color"].buttons["Black"].tap()
        expectation(for: NSPredicate(format: "label == %@", "1 games · 0 W / 1 D / 0 L / 0 ?"), evaluatedWith: result)
        waitForExpectations(timeout: 10)
        capture("Personal opening tree filtered to Black")
    }

    func testPromotionExercisesAcceptQueenAndBlackRook() {
        app.launch()
        app.tabBars.buttons["Practice"].tap()
        tap("practice.fundamentals")
        tap("fundamentals.lesson.white-promotion")
        tap("fundamentals.start")
        move("c7", "c8")
        tap("fundamentals.promote.queen")
        XCTAssertEqual(app.staticTexts["fundamentals.feedback"].label, "Solved independently.")
        app.navigationBars.buttons.firstMatch.tap()
        tap("fundamentals.lesson.black-promotion")
        tap("fundamentals.start")
        move("f2", "f1")
        tap("fundamentals.promote.rook")
        XCTAssertEqual(app.staticTexts["fundamentals.feedback"].label, "Solved independently.")
        capture("Black promotion exercise complete")
    }

    func testSavedLineSurvivesBackgroundAndRestart() throws {
        try launchLibrary()
        openRehearsal()
        move("e2", "e4")
        XCUIDevice.shared.press(.home)
        app.activate()
        tap("rehearsal.restart")
        let progress = app.staticTexts["rehearsal.progress"]
        XCTAssertEqual(progress.label, "0 of 2 moves recalled")
        move("e2", "e4")
        let replySettled = NSPredicate { _, _ in
            !self.app.staticTexts["Showing the other side's saved reply…"].exists
        }
        expectation(for: replySettled, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        move("g1", "f3")
        XCTAssertEqual(app.staticTexts["rehearsal.result"].label, "Completed without help or retries")
        capture("Rehearsal after background and restart")
    }

    func testDeletedSavedLineIsUnavailableWhenReturningToItsTab() throws {
        try launchLibrary()
        openRehearsal()
        app.tabBars.buttons["Today"].tap()
        tap("app.settings")
        let clear = app.buttons["Clear sample games and practice"]
        reveal(clear); clear.tap()
        app.buttons["Clear samples and practice"].tap()
        tap("settings.done")
        app.tabBars.buttons["Games"].tap()
        XCTAssertFalse(app.otherElements["rehearsal.board"].exists)
        XCTAssertFalse(app.staticTexts["rehearsal.progress"].exists)
        capture("Deleted saved line no longer available")
    }

    func testFundamentalsPromotionControlsFitAccessibilityText() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.tabBars.buttons["Practice"].tap()
        tap("practice.fundamentals")
        tap("fundamentals.lesson.white-promotion")
        tap("fundamentals.start")
        move("c7", "c8")
        let queen = app.buttons["fundamentals.promote.queen"]
        reveal(queen)
        capture("Promotion choices at largest text size")
        for piece in ["queen", "rook", "bishop", "knight"] {
            let button = app.buttons["fundamentals.promote.\(piece)"]
            XCTAssertLessThan(button.frame.height, 100, "Promotion labels should not wrap by character")
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX)
        }
    }

    func testOpeningExplorerControlsFitAccessibilityText() throws {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        try launchLibrary()
        app.tabBars.buttons["Practice"].tap()
        tap("openings.open")
        tap("openings.explorer")
        reveal(app.buttons["openingExplorer.flip"])
        capture("Opening explorer at largest text size")
        for control in ["back", "reset", "flip"] {
            let button = app.buttons["openingExplorer.\(control)"]
            XCTAssertLessThan(button.frame.height, 100, "Control labels should not wrap by character")
            XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX)
        }
        let board = app.otherElements["openingExplorer.board"]
        XCTAssertTrue(board.exists)
        XCTAssertGreaterThan(board.frame.width, 250)
        XCTAssertGreaterThanOrEqual(board.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(board.frame.maxX, app.frame.maxX)
        reveal(board)
        capture("Opening board at largest text size")
    }

    private func openRehearsal() {
        app.tabBars.buttons["Games"].tap()
        tap("games.savedLines")
        tap("lines.open.review-line")
        tap("lines.rehearse")
        XCTAssertTrue(app.staticTexts["rehearsal.progress"].waitForExistence(timeout: 5))
    }

    private func launchLibrary() throws {
        let now = Date().timeIntervalSinceReferenceDate
        // Keep fixtures ephemeral using the existing demo-only injection gate.
        // Non-demo IDs exercise populated personal statistics without an account.
        let specifications = [
            ("personal-a", "Learner", "white", "1-0", "e4 e5 Nf3 Nc6"),
            ("personal-b", "Learner", "black", "1/2-1/2", "e4 e5 Nc3 Nc6"),
            ("personal-c", "Learner", "white", "0-1", "d4 d5 c4 e6"),
            ("personal-d", "OtherLearner", "white", "1-0", "c4 e5 Nc3 Nf6")
        ]
        let games: [[String: Any]] = specifications.enumerated().map { index, game in
            ["id": game.0, "username": game.1, "white": game.2 == "white" ? game.1 : "Partner",
             "black": game.2 == "black" ? game.1 : "Partner", "playedAt": now - Double(index),
             "playerSide": game.2, "moves": game.4, "status": game.3 == "1/2-1/2" ? "draw" : "resign",
             "result": game.3, "speed": "rapid"]
        }
        let line: [String: Any] = ["id": "review-line", "gameID": "personal-a", "gameLabel": "Learner vs Partner",
            "username": "Learner", "playerSide": "white", "initialFEN": initialFEN, "prefix": [],
            "moves": ["e2e4", "e7e5", "g1f3"], "positionFEN": initialFEN, "repetitionHistory": [],
            "openingFamily": "King's pawn", "savedAt": now, "title": "Recall the center"]
        let fixture: [String: Any] = ["games": games, "analyses": [], "practice": [], "isDemo": true,
            "skippedGames": 0, "review": ["savedLines": [line]]]
        app.launchEnvironment["CHESSME_UI_TEST_LIBRARY"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launch()
    }

    private func move(_ from: String, _ to: String) { tap("board.square.\(from)"); tap("board.square.\(to)") }

    private func tap(_ identifier: String) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        reveal(element)
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing \(identifier)")
        element.tap()
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            if element.exists && element.frame.maxY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
