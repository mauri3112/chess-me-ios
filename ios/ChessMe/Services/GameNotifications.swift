import Combine
import Foundation
import UIKit
import UserNotifications

struct CloudNotificationRoute: Equatable, Sendable {
    let gameID: String
    let jobID: UUID
    let accountToken: UUID

    init?(userInfo: [AnyHashable: Any]) {
        guard let payload = userInfo["chessme"] as? [String: Any],
              let game = payload["game_id"] as? String, game.count == 8,
              game.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              let job = payload["job_id"] as? String, let jobID = UUID(uuidString: job),
              let account = payload["account_token"] as? String, let accountToken = UUID(uuidString: account),
              let kind = payload["kind"] as? String,
              ["queued", "completed", "partial", "failed"].contains(kind) else { return nil }
        self.gameID = game
        self.jobID = jobID
        self.accountToken = accountToken
    }
}

enum GameNotificationError: LocalizedError {
    case denied, unavailable
    var errorDescription: String? {
        switch self {
        case .denied: "Allow notifications for ChessMe in iPhone Settings, then try again."
        case .unavailable: "Apple could not register this device for notifications. Try again when connected."
        }
    }
}

@MainActor
final class GameNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = GameNotifications()
    @Published var pendingRoute: CloudNotificationRoute?
    @Published private(set) var deviceToken: String?
    private var registrationFailed = false
    private(set) var registrationRevision = 0

    init(installDelegate: Bool = true) {
        super.init()
        if installDelegate { UNUserNotificationCenter.current().delegate = self }
    }

    var environment: String {
        Bundle.main.object(forInfoDictionaryKey: "ChessMePushEnvironment") as? String == "development" ? "sandbox" : "production"
    }

    func register(requestPermission: Bool) async throws -> String {
        let center = UNUserNotificationCenter.current()
        if requestPermission {
            guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else { throw GameNotificationError.denied }
        }
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { throw GameNotificationError.denied }
        registrationFailed = false
        let revision = registrationRevision
        UIApplication.shared.registerForRemoteNotifications()
        return try await waitForRegistration(after: revision)
    }

    func waitForRegistration(after revision: Int) async throws -> String {
        for _ in 0..<150 {
            try Task.checkCancellation()
            if registrationRevision > revision {
                if registrationFailed { break }
                if let deviceToken { return deviceToken }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw GameNotificationError.unavailable
    }

    func registered(_ token: Data) {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        registrationFailed = false
        registrationRevision += 1
    }
    func failed() {
        registrationFailed = true
        registrationRevision += 1
    }

    func consume(_ route: CloudNotificationRoute) {
        if pendingRoute == route { pendingRoute = nil }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let route = CloudNotificationRoute(userInfo: response.notification.request.content.userInfo)
        Task { @MainActor in self.pendingRoute = route }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Account ownership is checked before navigating, even on a cold launch.
        completionHandler([.banner, .list, .sound])
    }
}

@MainActor
final class ChessMeAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = GameNotifications.shared
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        GameNotifications.shared.registered(deviceToken)
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        GameNotifications.shared.failed()
    }
}
