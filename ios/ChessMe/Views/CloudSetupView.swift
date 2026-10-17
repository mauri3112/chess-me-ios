import SwiftUI
import ChessMeCore

struct CloudSetupView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var authentication: LichessAuthentication
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var showPlans = false
    @State private var chooseGames = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(model.cloudIsReady ? "Cloud reviews are ready" : "Set up deeper reviews")
                        .font(ChessMeStyle.title(30))
                    Text("Stockfish reviews games you choose. Saved results work offline.")
                        .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                    if model.cloud.usesSandbox {
                        Label("TestFlight · Apple Sandbox", systemImage: "testtube.2")
                            .font(.caption.weight(.semibold)).foregroundStyle(ChessMeStyle.green)
                    }
                    if model.cloudIsReady {
                        if let account = model.cloudAccount {
                            Text("\(account.quotaRemaining) of \(account.monthlyGameLimit) reviews left")
                                .font(ChessMeStyle.title(25)).accessibilityIdentifier("cloud.allowance")
                            Text("Resets \(account.quotaResetsAt.formatted(date: .abbreviated, time: .omitted)) · UTC")
                                .font(.caption).foregroundStyle(ChessMeStyle.muted)
                        }
                        PrimaryButton(title: "Choose games", symbol: "checklist") { chooseGames = true }
                            .disabled(model.isBusy || model.cloudAccount?.quotaRemaining == 0).accessibilityIdentifier("cloud.chooseGames")
                        if model.cloudCandidateGames.isEmpty {
                            Text("No new games in this period.").font(.caption).foregroundStyle(ChessMeStyle.muted)
                        }
                        DisclosureGroup("Import more games") {
                            ReviewPeriodMenu().padding(.vertical, 8)
                            Button("Import completed games") { Task { _ = await model.importGames() } }.disabled(model.isBusy)
                            if let coverage = model.library.coverageNote { Text(coverage).font(.caption) }
                        }.font(.subheadline)
                    } else {
                        PaperCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Next step").font(.caption.weight(.semibold)).foregroundStyle(ChessMeStyle.green)
                                nextStep
                            }
                        }
                    }
                    if let message = error ?? model.cloudSetupError {
                        Text(message).font(.footnote).foregroundStyle(ChessMeStyle.ink).accessibilityIdentifier("cloud.error")
                    }
                    if let status = subscriptions.statusMessage { Text(status).font(.footnote).foregroundStyle(ChessMeStyle.muted) }
                    if model.cloudBatchSubmitting {
                        ProgressView(model.cloudBatchMessage ?? "Submitting…")
                        Button("Stop submitting more games") { model.cloudBatchTask?.cancel() }
                    } else if let message = model.cloudBatchMessage { Text(message).font(.footnote) }
                    if !model.cloudBatchSubmitting && !model.cloudBatchRemaining.isEmpty {
                        Text("\(model.cloudBatchRemaining.count) games left in your last batch.").font(.caption)
                        Button("Resume remaining submissions") { model.startCloudBatch(gameIDs: model.cloudBatchRemaining, resuming: true) }
                            .disabled(!model.cloudIsReady || model.isBusy || model.cloudBatchRemaining.count > (model.cloudAccount?.quotaRemaining ?? 0))
                    }
                    if model.cloudIsReady || !model.displayedCloudReviews.isEmpty { activity }
                    DisclosureGroup("Connection & review details") {
                        VStack(alignment: .leading, spacing: 16) {
                            if let account = authentication.account { Text("Lichess · \(account.username)").font(.subheadline) }
                            if model.hasCloudConsent {
                                Toggle("Allow cloud account connection", isOn: Binding(get: { model.hasCloudConsent }, set: { if !$0 { model.revokeCloudConnection() } }))
                                    .accessibilityIdentifier("cloud.consent")
                                Button("Check cloud connection") { Task { await model.connectCloudAccount() } }
                                    .disabled(model.cloudIsConnecting).accessibilityIdentifier("cloud.checkConnection")
                            }
                            if model.cloudAccessVerified && subscriptions.isPro {
                                Toggle("Use Stockfish cloud reviews", isOn: Binding(get: { model.cloudEnabled }, set: model.setCloudEnabled))
                                    .accessibilityIdentifier("cloud.enable")
                            }
                            Button("Restore purchases") { restore() }.disabled(model.cloudIsConnecting).accessibilityIdentifier("cloud.restore")
                            NavigationLink("Analysis engine settings") { EngineSettingsView() }
                            Text("Pro includes 30 reviews per UTC month. Queued reviews reserve allowance; cancellation before work starts and failed reviews restore it. Coverage is shown on each review.")
                            Text("The server retains a completed review until this iPhone saves it, then for 24 hours. Keep the connection on for automatic downloads. Local reviews stay on this iPhone.")
                        }.font(.caption).foregroundStyle(ChessMeStyle.muted).padding(.top, 12)
                    }.font(.subheadline)
                }.padding(24)
            }.background(ChessMeStyle.paper).accessibilityIdentifier("cloud.scroll")
                .navigationTitle("Cloud reviews").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.accessibilityIdentifier("cloud.done") } }
                .sheet(isPresented: $showPlans) { PaywallView() }
                .sheet(isPresented: $chooseGames) { CloudGamePicker() }
                .task {
                    guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
                    await model.connectCloudAccount()
                    await model.refreshCloudReviews()
                }
                .onChange(of: showPlans) { _, showing in if !showing { Task { await model.connectCloudAccount() } } }
        }.disclosureGroupStyle(FullRowDisclosureStyle())
    }

    @ViewBuilder private var nextStep: some View {
        if !model.cloud.isConfigured {
            Text("Cloud reviews need an updated build.").font(ChessMeStyle.title(23)).accessibilityIdentifier("cloud.nextStep")
            Text("Device reviews are available now.").font(.subheadline)
        } else if !model.canSaveLibrary {
            Text("Recover your saved library").font(ChessMeStyle.title(23)).accessibilityIdentifier("cloud.nextStep")
            Text("Open Settings to recover or delete unreadable local data before connecting cloud reviews.").font(.subheadline)
        } else if model.isDemo {
            Text("Connect your own games").font(ChessMeStyle.title(23)).accessibilityIdentifier("cloud.nextStep")
            Text("Leave sample mode to connect Lichess.").font(.subheadline)
            PrimaryButton(title: "Exit sample review", symbol: "arrow.right") { model.exitDemo() }.disabled(model.isBusy)
        } else if authentication.account == nil {
            Text("Connect Lichess").font(ChessMeStyle.title(23)).accessibilityIdentifier("cloud.nextStep")
            Text("Cloud reviews use your own finished games.").font(.subheadline).foregroundStyle(ChessMeStyle.muted)
            PrimaryButton(title: authentication.isConnecting ? "Connecting…" : "Connect Lichess", symbol: "link") {
                Task { do { try await authentication.connect() } catch { self.error = error.localizedDescription } }
            }.disabled(authentication.isConnecting).accessibilityIdentifier("cloud.connectLichess")
        } else if !model.hasCloudConsent {
            Text("Allow cloud connection").font(ChessMeStyle.title(23)).accessibilityIdentifier("cloud.nextStep")
            Text("ChessMe sends your Lichess read token to its server to identify you and fetch games you select. The server does not store your token.")
                .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
            PrimaryButton(title: "Allow cloud connection", symbol: "cloud") { Task { await model.allowCloudConnection() } }
                .disabled(model.cloudIsConnecting).accessibilityIdentifier("cloud.allowConnection")
        } else if model.cloudAccount == nil || model.cloudAccountID != authentication.account?.username.lowercased() {
            Text("Check your connection").font(ChessMeStyle.title(23)).accessibilityIdentifier("cloud.nextStep")
            PrimaryButton(title: model.cloudIsConnecting ? "Connecting…" : "Retry connection", symbol: "arrow.clockwise") { Task { await model.connectCloudAccount() } }
                .disabled(model.cloudIsConnecting).accessibilityIdentifier("cloud.checkConnection")
        } else if !subscriptions.isPro {
            Text("Choose Pro").font(ChessMeStyle.title(23)).accessibilityIdentifier("cloud.nextStep")
            Text("30 cloud reviews a month, plus 7, 30 and 365 days of game history.").font(.subheadline).foregroundStyle(ChessMeStyle.muted)
            if let expiry = subscriptions.lastProExpiration, expiry <= Date() {
                Text("Previous access ended \(expiry.formatted(date: .abbreviated, time: .omitted)).").font(.caption)
            }
            PrimaryButton(title: "See Pro options", symbol: "sparkles") { showPlans = true }.accessibilityIdentifier("cloud.proOptions")
            Button("Restore purchases") { restore() }.disabled(model.cloudIsConnecting).accessibilityIdentifier("cloud.restorePrimary")
        } else if !model.cloudAccessVerified {
            Text("Verify Pro for this account").font(ChessMeStyle.title(23)).accessibilityIdentifier("cloud.nextStep")
            PrimaryButton(title: model.cloudIsConnecting ? "Checking access…" : "Link purchase and check access", symbol: "checkmark.seal") { Task { await model.connectCloudAccount() } }
                .disabled(model.cloudIsConnecting).accessibilityIdentifier("cloud.linkPurchase")
        } else {
            Text("Enable cloud reviews").font(ChessMeStyle.title(23)).accessibilityIdentifier("cloud.nextStep")
            Text("You choose every game or batch. Reviews continue when you close the app.").font(.subheadline).foregroundStyle(ChessMeStyle.muted)
            PrimaryButton(title: "Enable cloud reviews", symbol: "cloud") { model.setCloudEnabled(true) }.accessibilityIdentifier("cloud.enablePrimary")
        }
    }

    private func restore() {
        Task {
            do { try await subscriptions.restore(); if model.hasCloudConsent { await model.connectCloudAccount() } }
            catch { self.error = error.localizedDescription }
        }
    }
    private var activity: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Queue & saved reviews").font(ChessMeStyle.title(25))
                Spacer()
                if model.cloudIsRefreshing { ProgressView() }
                else {
                    Button { Task { await model.refreshCloudReviews() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(!model.hasCloudConsent).accessibilityLabel("Download cloud reviews")
                        .accessibilityIdentifier("cloud.refresh")
                }
            }
            if let failure = model.cloudDownloadError { Text(failure).font(.footnote).accessibilityIdentifier("cloud.downloadError") }
            if let refreshed = model.cloudLastRefreshed { Text("Last checked \(refreshed.formatted(date: .omitted, time: .shortened))").font(.caption) }
            if model.displayedCloudReviews.isEmpty {
                Text("Your queued and saved cloud reviews will appear here. Check for reviews from another device after connecting your cloud account.")
                    .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
            }
            ForEach(model.displayedCloudReviews) { review in
                PaperCard {
                    VStack(alignment: .leading, spacing: 8) {
                        if let game = model.library.games.first(where: { $0.id == review.gameID }) {
                            NavigationLink { GameDetailView(game: game) } label: {
                                HStack { Text(game.label).font(.subheadline.weight(.semibold)); Spacer(); Image(systemName: "chevron.right") }
                            }
                        } else { Text("Lichess game \(review.gameID)").font(.subheadline.weight(.semibold)) }
                        Text(review.statusText).font(.caption)
                        if authentication.account == nil { Text("Saved for \(review.accountID)").font(.caption) }
                        if review.isPending {
                            if let place = review.queuePosition { Text("Queue position \(place)").font(.caption) }
                            if let estimate = review.estimatedCompletionAt { Text("Estimated \(estimate.formatted(date: .omitted, time: .shortened))").font(.caption) }
                            if review.state == "queued" {
                                Button("Cancel queued review", role: .destructive) { Task { await model.cancelCloudReview(gameID: review.gameID) } }
                                    .disabled(!model.hasCloudConsent)
                            } else { Text("Work has started. This review continues on the server.").font(.caption) }
                        } else if ["failed", "cancelled"].contains(review.state), let game = model.library.games.first(where: { $0.id == review.gameID }) {
                            Button("Retry cloud review") { Task { await model.enhanceInCloud(game: game) } }
                                .disabled(!model.cloudIsReady || model.isBusy || model.cloudAccount?.quotaRemaining == 0)
                        }
                        if let analysis = model.library.analyses.first(where: { $0.gameID == review.gameID && $0.source == "cloud" }) {
                            Text("Saved on this iPhone · \(analysis.analyzedPlies)/\(analysis.totalPlies) decisions reviewed").font(.caption)
                            if let finding = analysis.findings.first(where: \.isPuzzle) {
                                Button("Practice this game's mistakes") { dismiss(); model.openLesson(finding) }
                            }
                        }
                    }
                }
            }
            if !model.displayedCloudReviews.isEmpty { NavigationLink("Opening coaching from saved games") { OpeningCoachView() } }
        }
    }
}

private struct CloudGamePicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []
    @State private var confirm = false
    @State private var speedFilter: GameSpeedFilter = .all
    private var candidates: [ChessGame] { model.cloudCandidateGames.filter { speedFilter.includes($0) } }
    private var limit: Int { model.cloudAccount?.quotaRemaining ?? 0 }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(selection.count) selected · \(limit) reviews left").font(.headline)
                    Text("One allowance per new review. Existing saved and pending reviews are excluded. Games are submitted newest first.").font(.caption)
                    GameSpeedMenu(selection: $speedFilter, identifier: "cloud.speed")
                    Button("Select newest \(min(limit, candidates.count)) games") {
                        selection = Set(candidates.prefix(limit).map(\.id))
                    }.disabled(limit == 0)
                    Button("Clear selection") { selection = [] }.disabled(selection.isEmpty)
                }
                ForEach(candidates) { game in
                    Button {
                        if selection.contains(game.id) { selection.remove(game.id) }
                        else if selection.count < limit { selection.insert(game.id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(game.label).font(.subheadline)
                                Text(game.playedAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(ChessMeStyle.muted)
                            }
                            Spacer()
                            Image(systemName: selection.contains(game.id) ? "checkmark.circle.fill" : "circle")
                        }
                    }.accessibilityValue(selection.contains(game.id) ? "Selected" : "Not selected")
                }
                if candidates.isEmpty { Text("No new games in this period. Import more games in Cloud reviews.") }
            }
            .onChange(of: speedFilter) { _, _ in selection.formIntersection(Set(candidates.map(\.id))) }
            .navigationTitle("Choose games").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Queue \(selection.count)") { confirm = true }.disabled(selection.isEmpty || selection.count > limit || model.isBusy) }
            }
            .confirmationDialog("Queue \(selection.count) cloud reviews?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Queue selected games") { model.startCloudBatch(gameIDs: selection); dismiss() }
            } message: { Text("This reserves \(selection.count) of your remaining \(limit) reviews. Stop submitting at any time. Already queued reviews continue after closing the app and can be cancelled before work starts.") }
        }
    }
}
