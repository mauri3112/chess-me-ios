import Foundation
import ChessMeCore
import CryptoKit

extension AppModel {
    var hasCloudConsent: Bool {
        guard let id = authentication.account?.username.lowercased(), !isDemo else { return false }
        return library.cloudReviewAccounts?.contains(id) == true
    }
    var cloudEnabled: Bool {
        guard let id = authentication.account?.username.lowercased(), !isDemo else { return false }
        return library.cloudEnabledAccounts?.contains(id) == true
    }
    var cloudIsReady: Bool {
        cloud.isConfigured && hasCloudConsent && cloudEnabled && cloudAccessVerified && subscriptions.isPro &&
        cloudAccount != nil && cloudAccountID == authentication.account?.username.lowercased() && canSaveLibrary
    }
    var currentCloudReviews: [CloudReviewRecord] {
        guard let id = authentication.account?.username.lowercased(), !isDemo else { return [] }
        return (library.cloudReviews ?? []).filter { $0.accountID == id }.reversed()
    }
    var displayedCloudReviews: [CloudReviewRecord] {
        if authentication.account != nil { return currentCloudReviews }
        guard !isDemo else { return [] }
        let saved = Set(library.analyses.filter { $0.source == "cloud" }.map(\.gameID))
        return (library.cloudReviews ?? []).filter { saved.contains($0.gameID) && ["completed", "partial"].contains($0.state) }.reversed()
    }
    var cloudBatchRemaining: Set<String> {
        guard let batch = library.cloudBatch, batch.accountID == authentication.account?.username.lowercased() else { return [] }
        let known = Set(currentCloudReviews.filter { $0.isPending || ["completed", "partial"].contains($0.state) }.map(\.gameID))
        return Set(batch.gameIDs).subtracting(batch.submittedGameIDs).subtracting(known)
    }
    var cloudCandidateGames: [ChessGame] {
        guard let id = authentication.account?.username.lowercased(), !isDemo else { return [] }
        let excluded = Set(currentCloudReviews.filter { $0.isPending || ["completed", "partial"].contains($0.state) }.map(\.gameID))
        let saved = Set(library.analyses.filter { $0.source == "cloud" }.map(\.gameID))
        return Self.cloudCandidates(windowGames, username: id, excluding: excluded.union(saved))
    }
    static func cloudCandidates(_ games: [ChessGame], username: String, excluding: Set<String>) -> [ChessGame] {
        var seen: Set<String> = []
        return games.filter { game in
            let player = game.playerSide == .white ? game.white : game.black
            return game.isFinished && !game.id.hasPrefix("demo-") && !game.id.hasPrefix("pgn-") &&
                player.lowercased() == username.lowercased() && !excluding.contains(game.id) && seen.insert(game.id).inserted
        }.sorted { $0.playedAt > $1.playedAt }
    }
    var cloudNextStep: String {
        if !cloud.isConfigured { return "Update ChessMe to a build with cloud reviews." }
        if isDemo { return "Exit the sample review to connect your own account." }
        if authentication.account == nil { return "Connect Lichess to review your own finished games." }
        if !hasCloudConsent { return "Allow the cloud account connection." }
        if cloudAccount == nil || cloudAccountID != authentication.account?.username.lowercased() { return "Connect your cloud account." }
        if !subscriptions.isPro { return "Choose Pro or restore an existing purchase." }
        if !cloudAccessVerified { return "Check access to link and verify your Pro purchase." }
        if !cloudEnabled { return "Enable cloud reviews, then choose your games." }
        if cloudAccount?.quotaRemaining == 0 { return "Your allowance is used. Saved reviews remain available." }
        return "Choose finished games for deeper Stockfish review."
    }
    func resetCloudAccess() {
        cloudMonitoring = nil
        monitoringAccountID = nil
        monitoringRefreshAt = .distantPast
        notificationGame = nil
        cloudBatchTask?.cancel()
        cloudAccount = nil
        cloudAccountID = nil
        cloudAccessVerified = false
        cloudSetupError = nil
        cloudDownloadError = nil
        cloudPollingSchedule = CloudPollingSchedule()
    }
    func allowCloudConnection() async {
        guard let id = authentication.account?.username.lowercased(), !isDemo, canSaveLibrary else { return }
        updateLibrary { snapshot in
            var accounts = snapshot.cloudReviewAccounts ?? []
            if !accounts.contains(id) { accounts.append(id) }
            snapshot.cloudReviewAccounts = accounts
        }
        guard persist() else { return }
        await connectCloudAccount()
    }
    func revokeCloudConnection() async {
        guard let id = authentication.account?.username.lowercased() else { return }
        guard await stopAutomaticCloudReviews() else { return }
        updateLibrary { snapshot in
            snapshot.cloudReviewAccounts?.removeAll { $0 == id }
            snapshot.cloudEnabledAccounts?.removeAll { $0 == id }
        }
        resetCloudAccess()
        _ = persist()
    }
    func setCloudEnabled(_ enabled: Bool) {
        guard hasCloudConsent, let id = authentication.account?.username.lowercased() else { return }
        updateLibrary { snapshot in
            var accounts = snapshot.cloudEnabledAccounts ?? []
            accounts.removeAll { $0 == id }
            if enabled { accounts.append(id) }
            snapshot.cloudEnabledAccounts = accounts
        }
        _ = persist()
        if !enabled { cloudBatchTask?.cancel() }
    }
    func connectCloudAccount() async {
        guard cloud.isConfigured, hasCloudConsent, !cloudIsConnecting,
              let id = authentication.account?.username.lowercased() else { return }
        cloudPollingSchedule = CloudPollingSchedule()
        cloudIsConnecting = true
        cloudSetupError = nil
        cloudAccessVerified = false
        defer { cloudIsConnecting = false }
        do {
            let token = try authentication.accessToken()
            let account = try await cloud.account(lichessToken: token, consented: true)
            guard authentication.account?.username.lowercased() == id, hasCloudConsent else { return }
            cloudAccount = account
            cloudAccountID = id
            if subscriptions.isPro {
                let body = try await subscriptions.connectionRequest(accountToken: account.accountToken)
                try await cloud.connectSubscription(body, lichessToken: token, consented: hasCloudConsent)
                guard authentication.account?.username.lowercased() == id, hasCloudConsent else { return }
                cloudAccessVerified = true
            }
        } catch {
            if authentication.account?.username.lowercased() == id && hasCloudConsent { cloudSetupError = error.localizedDescription }
        }
    }
    func submitCloudReview(game: ChessGame) async throws {
        guard cloudIsReady, let id = authentication.account?.username.lowercased(), let account = cloudAccount else {
            throw CloudError.consentRequired
        }
        guard Self.cloudCandidates([game], username: id, excluding: []).count == 1 else { throw CloudError.unfinishedGame }
        if cloudReview(for: game.id)?.isPending == true { return }
        let credential = try await subscriptions.cloudCredential()
        guard authentication.account?.username.lowercased() == id, cloudIsReady else { throw CancellationError() }
        let options = try JSONEncoder().encode(cloudEngineConfiguration)
        let digest = SHA256.hash(data: options + Data((game.pgn ?? game.id).utf8)).map { String(format: "%02x", $0) }.joined()
        let key = "\(id):\(game.id):\(digest)"
        var keys = library.cloudSubmissionKeys ?? [:]
        let requestID = keys[key] ?? UUID()
        keys[key] = requestID
        updateLibrary { $0.cloudSubmissionKeys = keys }
        guard persist() else { throw CocoaError(.fileWriteUnknown) }
        // Apple's old JWS may remain cached after legacy linking. The server
        // checks the permanent claim and requires fresh, correctly bound status.
        let bound = CloudSubscriptionCredential(signedTransaction: credential.signedTransaction, appAccountToken: account.accountToken)
        let job = try await cloud.enqueue(game: game, credential: bound, lichessToken: authentication.accessToken(),
                                          consented: hasCloudConsent, idempotencyKey: requestID, configuration: cloudEngineConfiguration)
        guard authentication.account?.username.lowercased() == id, !isDemo else { return }
        try receiveCloudJob(job, accountID: id)
        guard persist() else { throw CocoaError(.fileWriteUnknown) }
        notice = "\(job.state == "queued" ? "Cloud review queued" : "Cloud review updated"). \(job.quota_remaining) reviews remain this month."
        cloudAccount = try await cloud.account(lichessToken: authentication.accessToken(), consented: hasCloudConsent)
        await acknowledgeSavedCloudReviews(accountID: id)
    }
    func startCloudBatch(gameIDs: Set<String>, resuming: Bool = false) {
        guard cloudIsReady, !isBusy, !gameIDs.isEmpty else { return }
        let available = resuming ? Self.cloudCandidates(library.games, username: authentication.account?.username ?? "", excluding: Set(currentCloudReviews.filter { $0.isPending || ["completed", "partial"].contains($0.state) }.map(\.gameID))) : cloudCandidateGames
        let games = available.filter { gameIDs.contains($0.id) }
        guard games.count == gameIDs.count, games.count <= (cloudAccount?.quotaRemaining ?? 0) else {
            cloudSetupError = "Choose no more than your remaining allowance, then try again."
            return
        }
        if !resuming {
            updateLibrary { $0.cloudBatch = CloudBatchRecord(accountID: authentication.account?.username.lowercased() ?? "", gameIDs: games.map(\.id), submittedGameIDs: [], startedAt: Date()) }
        }
        guard persist() else { return }
        cloudBatchSubmitting = true
        cloudBatchTask = Task {
            defer { cloudBatchSubmitting = false }
            var submitted = 0
            do {
                for game in games {
                    try Task.checkCancellation()
                    guard cloudIsReady else { throw CloudError.consentRequired }
                    cloudBatchMessage = "Submitting \(submitted + 1) of \(games.count)…"
                    try await submitCloudReview(game: game)
                    submitted += 1
                    updateLibrary { $0.cloudBatch?.submittedGameIDs.append(game.id) }
                    guard persist() else { throw CocoaError(.fileWriteUnknown) }
                }
                cloudBatchMessage = "\(submitted) reviews submitted. They continue after you close the app."
            } catch is CancellationError {
                cloudBatchMessage = "Stopped submitting. \(submitted) reviews were sent. Refresh to check any interrupted request."
            } catch {
                cloudBatchMessage = "Stopped after \(submitted) submissions. Refresh before trying again."
                cloudSetupError = error.localizedDescription
            }
            await refreshCloudReviews()
        }
    }
}
