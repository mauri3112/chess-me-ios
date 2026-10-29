import XCTest
@testable import ChessMe

final class GameNotificationTests: XCTestCase {
    @MainActor
    func testRegistrationWaitsForFreshCallbackInsteadOfReturningCachedToken() async throws {
        let notifications = GameNotifications(installDelegate: false)
        notifications.registered(Data([0x01]))
        let revision = notifications.registrationRevision
        var completed = false
        let registration = Task {
            let token = try await notifications.waitForRegistration(after: revision)
            completed = true
            return token
        }
        await Task.yield()
        XCTAssertFalse(completed)
        notifications.registered(Data([0x02]))
        let token = try await registration.value
        XCTAssertEqual(token, "02")
    }

    @MainActor
    func testFinishingAnOlderRoutePreservesNewerNotification() throws {
        func route(_ game: String) throws -> CloudNotificationRoute {
            try XCTUnwrap(CloudNotificationRoute(userInfo: ["chessme": ["game_id": game,
                "job_id": UUID().uuidString, "account_token": UUID().uuidString, "kind": "queued"]]))
        }
        let notifications = GameNotifications(installDelegate: false)
        let first = try route("abcdefgh"), second = try route("ijklmnop")
        notifications.pendingRoute = first
        notifications.pendingRoute = second
        notifications.consume(first)
        XCTAssertEqual(notifications.pendingRoute, second)
        notifications.consume(second)
        XCTAssertNil(notifications.pendingRoute)
    }

    func testNotificationRequiresBoundAccountJobAndSafeGameIdentifier() {
        let job = UUID(), account = UUID()
        var payload: [String: Any] = ["game_id": "abcdefgh", "job_id": job.uuidString,
            "account_token": account.uuidString, "kind": "queued"]
        let route = CloudNotificationRoute(userInfo: ["chessme": payload])
        XCTAssertEqual(route?.gameID, "abcdefgh")
        XCTAssertEqual(route?.jobID, job)
        XCTAssertEqual(route?.accountToken, account)
        payload["game_id"] = "../admin"
        XCTAssertNil(CloudNotificationRoute(userInfo: ["chessme": payload]))
        payload["game_id"] = "abcdefgh"
        payload.removeValue(forKey: "account_token")
        XCTAssertNil(CloudNotificationRoute(userInfo: ["chessme": payload]))
        payload["account_token"] = account.uuidString
        payload["kind"] = "arbitrary-url"
        XCTAssertNil(CloudNotificationRoute(userInfo: ["chessme": payload]))
    }

    func testMonitoringStatusDoesNotPresentExhaustedAllowanceAsQueued() throws {
        let status = try JSONDecoder().decode(CloudMonitoringStatus.self, from: Data(#"{"available":true,"enabled":true,"state":"active","issue":"quota_exceeded","recovery_limited":true,"device_count":1,"expires_at":null}"#.utf8))
        XCTAssertTrue(status.recovery_limited)
        XCTAssertTrue(status.message.contains("allowance is used"))
        XCTAssertFalse(status.message.contains("queued"))
    }
}
