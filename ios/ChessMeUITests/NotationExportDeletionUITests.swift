import XCTest

final class NotationExportDeletionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-design", "--reset-engine", "--reset-local-analysis", "--reduce-motion"]
    }
    override func tearDownWithError() throws { app.terminate(); app = nil }

    func testPreparedGameExportIsRevokedAfterClearingLibraryOnAnotherTab() throws {
        try launchLibrary()
        app.tabBars.buttons["Games"].tap()
        tap("game.open.demo-export-game")
        tap("review.options")
        tap("review.export")
        clearLibraryAndAssertExportRevoked()
    }

    func testPreparedSavedLineExportIsRevokedAfterClearingLibraryOnAnotherTab() throws {
        try launchLibrary()
        openSavedLine()
        tap("lines.export")
        clearLibraryAndAssertExportRevoked()
    }

    func testPreparedSavedLineExplorationExportIsRevokedAfterClearingLibraryOnAnotherTab() throws {
        try launchLibrary()
        openSavedLine()
        tap("lines.explore")
        tap("game.options")
        tap("game.exportLine")
        clearLibraryAndAssertExportRevoked()
    }

    private func clearLibraryAndAssertExportRevoked() {
        XCTAssertTrue(app.staticTexts["export.notation"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["export.file"].exists)
        app.tabBars.buttons["Today"].tap()
        tap("app.settings")
        tap("Clear sample games and practice")
        tap("Clear samples and practice")
        tap("settings.done")
        app.tabBars.buttons["Games"].tap()
        let revoked = NSPredicate { _, _ in
            !self.app.staticTexts["export.notation"].exists &&
            !self.app.buttons["export.copy"].exists &&
            !self.app.buttons["export.share"].exists &&
            !self.app.buttons["export.file"].exists
        }
        expectation(for: revoked, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.buttons["DOCPicker.actionButton"].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Deleted source export revoked"; image.lifetime = .keepAlways; add(image)
    }

    private func openSavedLine() {
        app.tabBars.buttons["Games"].tap()
        tap("games.savedLines")
        tap("lines.open.export-line")
    }

    private func launchLibrary() throws {
        let now = Date().timeIntervalSinceReferenceDate
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let game: [String: Any] = ["id": "demo-export-game", "username": "Learner", "white": "Learner", "black": "Partner",
            "playedAt": now, "playerSide": "white", "moves": "e4 e5 Nf3 Nc6", "status": "resign", "result": "1-0", "speed": "rapid"]
        let line: [String: Any] = ["id": "export-line", "gameID": "demo-export-game", "gameLabel": "Learner vs Partner",
            "username": "Learner", "playerSide": "white", "initialFEN": fen, "prefix": [],
            "moves": ["e2e4", "e7e5", "g1f3"], "positionFEN": fen, "repetitionHistory": [],
            "openingFamily": "King's pawn", "savedAt": now, "title": "Export this line"]
        let fixture: [String: Any] = ["games": [game], "analyses": [], "practice": [], "isDemo": true,
                                    "skippedGames": 0, "review": ["savedLines": [line]]]
        app.launchEnvironment["CHESSME_UI_TEST_LIBRARY"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
        app.launch()
    }

    private func tap(_ identifier: String) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        for _ in 0..<12 {
            if element.exists && element.isHittable { break }
            if element.exists && element.frame.maxY < app.frame.midY { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing \(identifier)")
        element.tap()
    }
}
