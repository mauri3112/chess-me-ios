import XCTest

final class FundamentalsResetUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-design", "--reduce-motion"]
        app.launchEnvironment["CHESSME_UI_TEST_LIBRARY"] = "{\"games\":[],\"analyses\":[],\"practice\":[],\"isDemo\":true,\"skippedGames\":0}"
        app.launch()
    }

    override func tearDownWithError() throws { app.terminate(); app = nil }

    func testClearingSamplePracticeRemovesMountedFundamentalsCompletions() {
        openFundamentals()
        tap("fundamentals.lesson.back-rank")
        tap("fundamentals.start")
        tap("board.square.a1"); tap("board.square.a8")
        XCTAssertEqual(app.staticTexts["fundamentals.feedback"].label, "Solved independently.")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.images["fundamentals.completed.back-rank"].exists)

        clearSamplesFromAnotherTab()
        app.tabBars.buttons["Practice"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "fundamentals.list").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.images["fundamentals.completed.back-rank"].exists)
    }

    func testClearingSamplePracticeRestartsMountedExercise() {
        openFundamentals()
        tap("fundamentals.lesson.back-rank")
        tap("fundamentals.start")
        tap("board.square.a1")
        XCTAssertTrue(app.staticTexts["fundamentals.feedback"].exists)

        clearSamplesFromAnotherTab()
        app.tabBars.buttons["Practice"].tap()
        XCTAssertTrue(app.buttons["fundamentals.start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["fundamentals.feedback"].exists)
        tap("fundamentals.start")
        tap("board.square.a1"); tap("board.square.a8")
        XCTAssertEqual(app.staticTexts["fundamentals.feedback"].label, "Solved independently.")
    }

    private func openFundamentals() {
        app.tabBars.buttons["Practice"].tap()
        tap("practice.fundamentals")
    }

    private func clearSamplesFromAnotherTab() {
        app.tabBars.buttons["Today"].tap()
        tap("app.settings")
        tap("Clear sample games and practice")
        tap("Clear samples and practice")
        tap("settings.done")
    }

    private func tap(_ identifier: String) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        for _ in 0..<10 {
            if element.exists && element.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing \(identifier)")
        element.tap()
    }
}
