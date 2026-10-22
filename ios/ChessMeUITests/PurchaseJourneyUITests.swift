import StoreKitTest
import XCTest

final class PurchaseJourneyUITests: XCTestCase {
    private var app: XCUIApplication!
    private var store: SKTestSession!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ChessMe", withExtension: "storekit"))
        store = try SKTestSession(contentsOf: url)
        store.resetToDefaultState(); store.clearTransactions(); store.disableDialogs = true
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--storekit-testing"]
        app.launch()
    }
    override func tearDownWithError() throws { app.terminate(); store.clearTransactions(); store = nil; app = nil }

    func testLockedWindowInsideImportSheetPresentsPlansAndReturnsToImport() {
        let connect = app.buttons["connect.start"]
        XCTAssertTrue(connect.waitForExistence(timeout: 8)); connect.tap()
        app.buttons["Other ways to import"].tap()
        app.buttons["connection.publicProfile"].tap()
        XCTAssertTrue(app.buttons["games.period"].waitForExistence(timeout: 5))
        app.buttons["games.period"].tap(); app.buttons["window.30d"].tap()
        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 8), "The purchase sheet must present over the import sheet.")
        app.buttons["paywall.close"].tap()
        XCTAssertTrue(app.textFields["connection.username"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["games.period"].label.contains("24"))
    }

    func testVerifiedPurchaseShowsWelcomeAndContinuesWithTheRequestedHistory() {
        app.tabBars.buttons["Games"].tap()
        app.buttons["games.period"].tap(); app.buttons["window.7d"].tap()
        let purchase = app.buttons["purchase.monthly"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 12)); purchase.tap()
        XCTAssertTrue(app.staticTexts["proWelcome.title"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["30 cloud reviews a month"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Pro welcome after verified purchase"; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = "Pro welcome accessibility"; tree.lifetime = .keepAlways; add(tree)
        let next = app.buttons["proWelcome.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(next.isHittable, "The next action stays fixed at the bottom.")
        next.tap()
        XCTAssertTrue(app.buttons["games.period"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["games.period"].label.contains("7"))
        XCTAssertFalse(app.staticTexts["proWelcome.title"].exists)
    }
}
