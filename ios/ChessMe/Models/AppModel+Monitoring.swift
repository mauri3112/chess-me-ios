import Foundation
import ChessMeCore

extension AppModel {
    func refreshMonitoring(renew: Bool = false) async {
        guard hasCloudConsent, let accountID = authentication.account?.username.lowercased(),
              !isDemo, !monitoringBusy, !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        guard renew || monitoringRefreshAt < Date() else { return }
        monitoringRefreshAt = Date().addingTimeInterval(60)
        do {
            let status = try await cloud.monitoring(lichessToken: authentication.accessToken())
            guard authentication.account?.username.lowercased() == accountID, hasCloudConsent else { return }
            cloudMonitoring = status
            monitoringAccountID = accountID
            if status.enabled, renew {
                let notifications = GameNotifications.shared
                let token = try await notifications.register(requestPermission: false)
                guard authentication.account?.username.lowercased() == accountID, hasCloudConsent else { return }
                let installation = try KeychainStore().persistentUUID(for: "notifications.installation")
                // Refresh the current APNs token without enabling a previously disabled monitor.
                let updated = try await cloud.registerPushDevice(token: token, installation: installation,
                    environment: notifications.environment, lichessToken: authentication.accessToken())
                guard authentication.account?.username.lowercased() == accountID, hasCloudConsent else { return }
                cloudMonitoring = updated
            }
        } catch {
            guard authentication.account?.username.lowercased() == accountID else { return }
            monitoringError = error.localizedDescription
        }
    }

    func enableAutomaticCloudReviews() async {
        guard cloudIsReady, !monitoringBusy, let accountID = authentication.account?.username.lowercased() else { return }
        monitoringBusy = true
        monitoringError = nil
        defer { monitoringBusy = false }
        do {
            if !authentication.supportsGameEvents {
                try await authentication.connect(forMonitoring: true)
                guard authentication.account?.username.lowercased() == accountID else { throw SubscriptionError.differentAccount }
                // The account observer clears old access even for a refreshed connection.
                await connectCloudAccount()
            }
            let notifications = GameNotifications.shared
            let token = try await notifications.register(requestPermission: true)
            let credential = try await subscriptions.cloudCredential()
            guard authentication.account?.username.lowercased() == accountID, hasCloudConsent else { throw CancellationError() }
            let registration = CloudMonitoringRegistration(signed_transaction: credential.signedTransaction,
                installation_id: try KeychainStore().persistentUUID(for: "notifications.installation"),
                device_token: token, apns_environment: notifications.environment)
            let status = try await cloud.enableMonitoring(registration, lichessToken: authentication.accessToken())
            guard authentication.account?.username.lowercased() == accountID, hasCloudConsent else { return }
            cloudMonitoring = status
            monitoringAccountID = accountID
            monitoringRefreshAt = Date().addingTimeInterval(60)
        } catch is CancellationError { }
        catch { monitoringError = error.localizedDescription }
    }

    @discardableResult
    func stopAutomaticCloudReviews() async -> Bool {
        guard authentication.account != nil, hasCloudConsent else { return true }
        guard !monitoringBusy else { return false }
        monitoringBusy = true
        monitoringError = nil
        defer { monitoringBusy = false }
        do {
            let accountID = authentication.account?.username.lowercased()
            let status = try await cloud.disableMonitoring(lichessToken: authentication.accessToken())
            guard authentication.account?.username.lowercased() == accountID else { return false }
            cloudMonitoring = status
            monitoringAccountID = accountID
            return true
        } catch {
            monitoringError = "Automatic reviews could not be stopped. Keep this connection and try again. \(error.localizedDescription)"
            notice = monitoringError
            return false
        }
    }

    func disconnectLichess(deleteGames: Bool = false) async {
        guard await stopAutomaticCloudReviews() else { return }
        if deleteGames { removeGamesForConnectedAccount() }
        await authentication.disconnect()
        resetCloudAccess()
    }

    func openCloudNotification(_ route: CloudNotificationRoute) async {
        guard !Task.isCancelled else { return }
        guard !isDemo, hasCloudConsent, let accountID = authentication.account?.username.lowercased() else {
            notice = "Connect the Lichess account used for this review."
            return
        }
        // A newer alert may arrive while an older route or setup view is
        // connecting. Wait for that attempt instead of treating nil as a
        // different account and consuming the alert.
        do {
            while cloudIsConnecting {
                try await Task.sleep(for: .milliseconds(100))
            }
            try Task.checkCancellation()
        } catch { return }
        guard authentication.account?.username.lowercased() == accountID, hasCloudConsent else { return }
        await connectCloudAccount()
        guard !Task.isCancelled else { return }
        guard authentication.account?.username.lowercased() == accountID,
              cloudAccountID == accountID, cloudAccount?.accountToken == route.accountToken else {
            notice = "This notification belongs to a different cloud account."
            return
        }
        do {
            // The job ID and game ID must match the authenticated server listing.
            let jobs = try await cloud.jobs(lichessToken: authentication.accessToken())
            try Task.checkCancellation()
            guard jobs.contains(where: { $0.job_id == route.jobID && $0.game_id == route.gameID }) else {
                throw CloudError.invalidResponse
            }
            let game = try await lichessService.reviewedGame(gameID: route.gameID, username: accountID,
                accessToken: authentication.accessToken())
            try Task.checkCancellation()
            guard authentication.account?.username.lowercased() == accountID, !isDemo, hasCloudConsent, canSaveLibrary else { return }
            updateLibrary { if !$0.games.contains(where: { $0.id == game.id }) { $0.games.append(game) } }
            guard persist() else { return }
            await refreshCloudReviews()
            try Task.checkCancellation()
            guard authentication.account?.username.lowercased() == accountID, !isDemo, hasCloudConsent else { return }
            selectedTab = AppTab.games.rawValue
            notificationGame = game
        } catch {
            if !Task.isCancelled { notice = error.localizedDescription }
        }
    }
}
