import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var authentication: LichessAuthentication
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ChessBoardDesign.preferenceKey) private var storedDesign = ChessBoardDesign.classic.rawValue
    @AppStorage("analysis.showEvaluationBar") private var showEvaluationBar = true
    @State private var deleteLocal = false
    @State private var deleteCloud = false
    @State private var disconnect = false
    @State private var privacy = false
    @State private var cloudSetup = false
    @State private var connection = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Connections") {
                    Button { connection = true } label: {
                        LabeledContent("Lichess & imports", value: authentication.account?.username ?? "Not connected")
                    }.accessibilityIdentifier("settings.connection")
                    Button("Cloud reviews & queue") { cloudSetup = true }.accessibilityIdentifier("settings.cloudSetup")
                    if authentication.account != nil {
                        Button("Disconnect Lichess", role: .destructive) { disconnect = true }.disabled(model.isBusy)
                    }
                }
                Section("Analysis") {
                    Toggle("Show evaluation bar", isOn: $showEvaluationBar)
                        .accessibilityIdentifier("settings.evaluationBar")
                    NavigationLink("On-device analysis") { LocalAnalysisSettingsView() }
                        .accessibilityIdentifier("settings.localAnalysis")
                    NavigationLink("Analysis engines") { EngineSettingsView() }
                        .accessibilityIdentifier("settings.engines")
                }
                Section {
                    Toggle("Match puzzles after game review", isOn: $model.automaticPuzzleMatching)
                        .accessibilityIdentifier("settings.puzzleMatching")
                    Toggle("Set my puzzle level automatically", isOn: $model.automaticPuzzleLevel)
                        .accessibilityIdentifier("settings.automaticPuzzleLevel")
                    if !model.automaticPuzzleLevel {
                        Stepper("Puzzle level: \(model.puzzleTargetRating)", value: $model.puzzleTargetRating, in: 400...3000, step: 100)
                            .accessibilityIdentifier("settings.puzzleLevel")
                    }
                } header: { Text("Puzzles") } footer: {
                    Text("Automatic level adjusts after unaided attempts.")
                }
                Section("Appearance") {
                    NavigationLink {
                        BoardDesignSettingsView()
                    } label: {
                        LabeledContent("Design", value: (ChessBoardDesign(rawValue: storedDesign) ?? .classic).title)
                    }
                    .accessibilityIdentifier("settings.design")
                }
                Section("Subscription") {
                    LabeledContent("Access", value: subscriptions.isPro ? "Pro" : "Free · 24 hours")
                    if model.cloud.usesSandbox {
                        Text("TestFlight · Apple Sandbox")
                            .font(.caption).foregroundStyle(ChessMeStyle.muted)
                            .accessibilityIdentifier("settings.cloudEnvironment")
                    }
                    Button(subscriptions.isPro ? "View Pro access" : "See Pro options") { dismiss(); model.showPaywall = true }
                    Button("Restore purchases") { Task { do { try await subscriptions.restore() } catch { self.error = error.localizedDescription } } }
                    if subscriptions.isPro {
                        Button("Manage subscription") {
                            Task {
                                do {
                                    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
                                    try await subscriptions.manage(in: scene)
                                } catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                }
                Section("Your library") {
                    LabeledContent("Saved games", value: "\(model.library.games.count)")
                    LabeledContent("Saved exercises", value: "\(model.allPuzzles.count)")
                    Button(model.isDemo ? "Clear sample games and practice" : "Delete local games and practice", role: .destructive) { deleteLocal = true }.disabled(model.isBusy)
                    if model.cloud.isConfigured && authentication.account != nil {
                        Button("Download cloud reviews") { if model.hasCloudConsent { Task { await model.refreshCloudReviews() } } else { cloudSetup = true } }.disabled(model.isBusy)
                        Button("Delete cloud review history", role: .destructive) { deleteCloud = true }.disabled(model.isBusy)
                    }
                }
                Section("About chess-me") {
                    Button("Privacy and data") { privacy = true }
                    NavigationLink("About analysis") { AnalysisInfoView() }
                    NavigationLink("Open Source Licenses") { OpenSourceLicensesView() }
                        .accessibilityIdentifier("settings.licenses")
                }
                if let error = error ?? authentication.lastError ?? model.notice { Section { Text(error).font(.footnote) } }
            }
            .scrollContentBackground(.hidden).background(ChessMeStyle.paper)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.accessibilityIdentifier("settings.done") } }
            .confirmationDialog(model.isDemo ? "Clear sample games?" : "Delete your local library?", isPresented: $deleteLocal, titleVisibility: .visible) {
                Button(model.isDemo ? "Clear samples and practice" : "Delete games and practice", role: .destructive) { model.deleteLocalData() }
            } message: { Text(model.isDemo ? "This clears the demonstration games and practice. Your saved library remains available when you leave sample mode." : "This erases imported games, device analysis and practice progress on this iPhone. It does not cancel your subscription or delete Lichess games.") }
            .confirmationDialog("Disconnect Lichess?", isPresented: $disconnect, titleVisibility: .visible) {
                Button("Disconnect and keep local lessons") { Task { await authentication.disconnect() } }
                if !model.isDemo && model.canSaveLibrary {
                    Button("Disconnect and delete this account's local games", role: .destructive) {
                        model.removeGamesForConnectedAccount()
                        Task { await authentication.disconnect() }
                    }
                }
            } message: { Text("The saved read token is removed and future sync stops. chess-me also attempts to revoke access at Lichess.") }
            .confirmationDialog("Delete cloud review history?", isPresented: $deleteCloud, titleVisibility: .visible) {
                Button("Delete cloud history", role: .destructive) {
                    Task {
                        do {
                            guard let accountID = authentication.account?.username else { return }
                            try await model.cloud.deleteAccount(lichessToken: authentication.accessToken())
                            model.clearCloudReviewReferences(accountID: accountID)
                            error = "Cloud results and queued inputs were deleted. Unstarted reviews were refunded; already-started reviews keep their charge until rollover."
                        }
                        catch { self.error = error.localizedDescription }
                    }
                }
            } message: { Text("Saved cloud results and queued inputs are erased. Work that has not started is refunded. Already-started compute stays in current-month usage. Local lessons remain on this iPhone.") }
            .sheet(isPresented: $privacy) { PrivacyView() }
            .sheet(isPresented: $connection) { ConnectionView() }
            .sheet(isPresented: $cloudSetup) { CloudSetupView() }
        }
    }
}

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Your games,\nyour choice.").font(ChessMeStyle.title(36)).foregroundStyle(ChessMeStyle.ink)
                    paragraph("On your device", "chess-me stores imported completed games, analysis and practice progress in the app's local storage. Your Lichess read token is kept in Keychain. Device backups follow your iPhone's settings.")
                    paragraph("Lichess connection", "Connecting opens Lichess authorization. The app reads your identity and completed public standard games. Public username import does not verify account ownership. You can disconnect and delete local records in Settings.")
                    paragraph("Optional cloud review", "You choose whether to connect the cloud account and request deeper reviews. The service receives your Lichess read token for that request, verifies subscription access and fetches the selected completed game. It does not store your token. Completed reviews stay on the server until the app confirms they were saved on this iPhone, then remain available for 24 hours. Anonymous search results from public games may be reused to speed up other reviews. You can delete your cloud reviews in Settings.")
                    paragraph("Related puzzles", "After a game review, chess-me can send estimated tactical themes, a target puzzle level and public puzzle IDs to its server. Your game moves, player names and Lichess token are not sent for matching. The server returns public Lichess puzzles. Matches and attempts are saved on this iPhone. Turn automatic matching off in Settings or delete the local library to clear them.")
                    paragraph("Subscription and usage", "Apple processes purchases. The cloud service retains limited account and purchase-binding information and usage totals to enforce the monthly allowance and prevent duplicate charges. Deleting review history does not reset current-month usage or cancel your subscription.")
                    paragraph("This first version", "The app has no advertising or third-party analytics. The developer must publish the production operator's contact details and final privacy policy before public release.")
                }.padding(24)
            }.background(ChessMeStyle.paper)
                .navigationTitle("Privacy").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
    private func paragraph(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(ChessMeStyle.title(22)).foregroundStyle(ChessMeStyle.ink)
            Text(text).font(.subheadline).foregroundStyle(ChessMeStyle.muted).lineSpacing(4)
        }
    }
}
