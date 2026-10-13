import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var authentication: LichessAuthentication
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    private var allowCloud: Bool { model.hasCloudConsent }
    @State private var purchasing = false
    @State private var error: String?
    private var cloudAccount: CloudAccount? { model.cloudAccount }
    @State private var showPrivacy = false

    private var isStoreKitTesting: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--storekit-testing")
        #else
        return false
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    Eyebrow(text: "chess-me Pro")
                    Text("Learn from more of your games").font(ChessMeStyle.title(30)).foregroundStyle(ChessMeStyle.ink)
                    VStack(alignment: .leading, spacing: 12) {
                        Label("7, 30 and 365 days of game history", systemImage: "calendar")
                        Label("30 cloud reviews per UTC month", systemImage: "cloud")
                    }.font(.subheadline)
                    if model.cloud.usesSandbox {
                        Label("TestFlight · Apple Sandbox", systemImage: "testtube.2").font(.caption).foregroundStyle(ChessMeStyle.muted)
                    }
                    if !isStoreKitTesting && !subscriptions.isPro {
                        if model.isDemo {
                            Text("Connect your own games before subscribing.").font(.subheadline)
                            PrimaryButton(title: "Exit sample review", symbol: "arrow.right") { model.exitDemo() }.disabled(model.isBusy)
                        } else if !model.cloud.isConfigured {
                            Text("Subscriptions need an updated cloud-enabled build. Free device reviews are available now.").font(.subheadline)
                        } else if authentication.account == nil {
                            Text("First, connect the Lichess account your purchase will belong to.").font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                            PrimaryButton(title: authentication.isConnecting ? "Connecting…" : "Connect Lichess before subscribing", symbol: "link") {
                                Task { do { try await authentication.connect() } catch { self.error = error.localizedDescription } }
                            }.disabled(authentication.isConnecting || purchasing)
                        } else if !allowCloud {
                            Text("Allow ChessMe to identify you and fetch selected games using your Lichess read token. The server does not store your token.")
                                .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                            PrimaryButton(title: "Allow cloud connection", symbol: "cloud") { Task { await model.allowCloudConnection() } }
                                .disabled(model.cloudIsConnecting || purchasing)
                        } else if cloudAccount == nil || model.cloudAccountID != authentication.account?.username.lowercased() {
                            PrimaryButton(title: model.cloudIsConnecting ? "Connecting…" : "Check cloud connection", symbol: "arrow.clockwise") { Task { await model.connectCloudAccount() } }
                                .disabled(model.cloudIsConnecting || purchasing)
                        } else {
                            Label("Purchase for \(authentication.account?.username ?? "your Lichess account")", systemImage: "checkmark.circle")
                                .font(.caption).foregroundStyle(ChessMeStyle.green)
                        }
                    }
                    if subscriptions.isPro {
                        PaperCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Your Pro subscription is active", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold))
                                if let expiry = subscriptions.expirationDate { Text("Current access through \(expiry.formatted(date: .abbreviated, time: .omitted))").font(.caption) }
                            }
                        }
                        NavigationLink("Set up cloud reviews & view queue") { CloudSetupView() }
                        PrimaryButton(title: "Continue to my review", symbol: "arrow.right") { dismiss() }
                    } else if subscriptions.isLoading { ProgressView("Loading subscription options…") }
                    else if isStoreKitTesting || (!model.isDemo && allowCloud && authentication.account != nil && cloudAccount != nil && model.cloudAccountID == authentication.account?.username.lowercased()) {
                        ForEach(subscriptions.products, id: \.id) { product in
                            Button { Task { await purchase(product) } } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(product.displayName).font(.subheadline.weight(.semibold))
                                        Text(product.id.hasSuffix("yearly") ? "Billed annually" : "Billed monthly").font(.caption).foregroundStyle(ChessMeStyle.muted)
                                    }
                                    Spacer()
                                    Text(product.displayPrice).font(ChessMeStyle.title(24))
                                }
                                .padding(19).background(.white, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(ChessMeStyle.green.opacity(0.35)))
                            }
                            .buttonStyle(.plain)
                            .disabled(purchasing || model.cloudIsConnecting || (!isStoreKitTesting && (!model.cloud.isConfigured || !allowCloud || authentication.account == nil || model.cloudAccount == nil || model.cloudAccountID != authentication.account?.username.lowercased())))
                            .accessibilityIdentifier("purchase.\(product.id.hasSuffix("yearly") ? "yearly" : "monthly")")
                        }
                    }
                    if model.cloudIsConnecting { ProgressView("Connecting cloud account…") }
                    if isStoreKitTesting { Text("Local StoreKit fixtures do not authorize cloud reviews.").font(.caption).foregroundStyle(ChessMeStyle.muted) }
                    if let message = model.cloudSetupError {
                        Text(message).font(.footnote)
                        Button("Retry cloud connection") { Task { await model.connectCloudAccount() } }
                    }
                    if let error = error ?? subscriptions.lastError ?? subscriptions.statusMessage {
                        Text(error).font(.footnote).foregroundStyle(ChessMeStyle.muted)
                    }
                    Button("Restore purchases") {
                        Task { do { try await subscriptions.restore(); await model.connectCloudAccount() } catch { self.error = error.localizedDescription } }
                    }.font(.subheadline.weight(.medium)).disabled(purchasing)
                    Text("Subscriptions renew automatically unless canceled through the App Store. Payment is charged to your Apple account. The review window describes which games are included, not the subscription duration.")
                        .font(.caption2).foregroundStyle(ChessMeStyle.muted).lineSpacing(3)
                    HStack {
                        Button("Privacy") { showPrivacy = true }
                        Spacer()
                        Link("Terms of use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    }.font(.caption)
                }.padding(24)
            }.background(ChessMeStyle.paper)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() }.accessibilityIdentifier("paywall.close") } }
                .task { await subscriptions.load(); await loadCloudAccount() }

                .onChange(of: authentication.account) { _, _ in if allowCloud { Task { await loadCloudAccount() } } }
                .sheet(isPresented: $showPrivacy) { PrivacyView() }
        }
    }

    private func loadCloudAccount() async {
        guard allowCloud, authentication.account != nil else { return }
        await model.connectCloudAccount()
    }

    private func purchase(_ product: Product) async {
        purchasing = true
        error = nil
        defer { purchasing = false }
        do {
            let token: UUID?
            if isStoreKitTesting && !model.cloud.isConfigured { token = nil }
            else {
                guard allowCloud else { throw CloudError.consentRequired }
                let account = try await model.cloud.account(lichessToken: authentication.accessToken(), consented: true)
                guard allowCloud else { throw CloudError.consentRequired }
                model.cloudAccount = account
                model.cloudAccountID = authentication.account?.username.lowercased()
                token = account.accountToken
            }
            let result = try await subscriptions.purchase(product, appAccountToken: token)
            if case .purchased = result { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}
