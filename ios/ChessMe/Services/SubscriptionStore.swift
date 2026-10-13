import Combine
import Foundation
import StoreKit
import UIKit

struct CloudSubscriptionCredential: Sendable {
    let signedTransaction: String
    let appAccountToken: UUID
}

enum SubscriptionError: LocalizedError {
    case unverified, unavailable, subscriptionRequired, missingAccountToken, developmentPurchase, differentAccount
    var errorDescription: String? {
        switch self {
        case .unverified: return "The App Store could not verify this purchase. Try restoring purchases."
        case .unavailable: return "Subscriptions are not available yet. Check your App Store connection and try again."
        case .subscriptionRequired: return "An active chess-me Pro subscription is required."
        case .missingAccountToken: return "This purchase is not linked to a cloud account. Connect Lichess before starting a subscription with cloud access."
        case .differentAccount: return "This purchase belongs to another account. Reconnect the Lichess account used when buying Pro. If you bought before connecting, restore on the original iPhone and link your purchase in Cloud reviews."
        case .developmentPurchase: return "This is a local StoreKit test purchase. It unlocks device reviews but cannot authorize the cloud service."
        }
    }
}

@MainActor
final class SubscriptionStore: ObservableObject {
    enum PurchaseOutcome { case purchased, pending, cancelled }
    static let defaultProductIDs = ["com.chessme.pro.monthly", "com.chessme.pro.yearly"]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro = false
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var expirationDate: Date?
    @Published private(set) var lastProExpiration = UserDefaults.standard.object(forKey: "subscription.lastExpiration") as? Date

    private let productIDs: Set<String>
    private let keychain: KeychainStore
    private var activeEntitlement: VerificationResult<Transaction>?
    private var updatesTask: Task<Void, Never>?
    private var expirationTask: Task<Void, Never>?

    init(productIDs: [String]? = nil, keychain: KeychainStore = KeychainStore()) {
        self.productIDs = Set(productIDs ?? Bundle.main.object(forInfoDictionaryKey: "ChessMeSubscriptionProductIDs") as? [String] ?? Self.defaultProductIDs)
        self.keychain = keychain
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await self.refreshEntitlements()
                    if self.productIDs.contains(transaction.productID) { await transaction.finish() }
                } else { self.lastError = SubscriptionError.unverified.localizedDescription }
            }
        }
    }

    deinit { updatesTask?.cancel(); expirationTask?.cancel() }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await refreshEntitlements()
        do {
            products = try await Product.products(for: Array(productIDs))
                .filter { $0.type == .autoRenewable }.sorted { $0.price < $1.price }
            lastError = products.isEmpty ? SubscriptionError.unavailable.localizedDescription : nil
        } catch is CancellationError {
        } catch { lastError = error.localizedDescription }
    }

    /// A configured cloud deployment supplies its account token before purchase.
    /// With no cloud deployment, a durable device token supports device-only purchases.
    @discardableResult
    func purchase(_ product: Product, appAccountToken: UUID? = nil) async throws -> PurchaseOutcome {
        guard productIDs.contains(product.id), product.type == .autoRenewable else { throw SubscriptionError.unavailable }
        lastError = nil
        statusMessage = nil
        do {
            let token = try appAccountToken ?? keychain.persistentUUID(for: "storekit.device-account-token")
            let result = try await product.purchase(options: [.appAccountToken(token)])
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { throw SubscriptionError.unverified }
                await refreshEntitlements()
                await transaction.finish()
                statusMessage = "Your Pro subscription is active."
                return .purchased
            case .pending:
                statusMessage = "The App Store is waiting for purchase approval. Pro will unlock when approval arrives."
                return .pending
            case .userCancelled: return .cancelled
            @unknown default: throw SubscriptionError.unavailable
            }
        } catch is CancellationError { throw CancellationError() }
        catch { lastError = error.localizedDescription; throw error }
    }

    func restore() async throws {
        lastError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusMessage = isPro ? "Your Pro subscription was restored." : "No active Pro subscription was found."
        } catch { lastError = error.localizedDescription; throw error }
    }

    func manage(in scene: UIWindowScene) async throws {
        try await AppStore.showManageSubscriptions(in: scene)
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var selected: VerificationResult<Transaction>?
        var latestExpiration: Date?
        let now = Date()
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  productIDs.contains(transaction.productID), transaction.productType == .autoRenewable,
                  transaction.revocationDate == nil, !transaction.isUpgraded,
                  let expiration = transaction.expirationDate, expiration > now else { continue }
            if expiration > (latestExpiration ?? .distantPast) {
                selected = result
                latestExpiration = expiration
            }
        }
        activeEntitlement = selected
        expirationDate = latestExpiration
        if let latestExpiration {
            lastProExpiration = latestExpiration
            UserDefaults.standard.set(latestExpiration, forKey: "subscription.lastExpiration")
        }
        isPro = selected != nil
        expirationTask?.cancel()
        if let latestExpiration {
            expirationTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(max(1, latestExpiration.timeIntervalSinceNow)))
                    try Task.checkCancellation()
                    await self?.refreshEntitlements()
                } catch { }
            }
        }
    }

    func connectionRequest(accountToken: UUID) async throws -> CloudSubscriptionConnection {
        let credential = try await cloudCredential()
        var request = CloudSubscriptionConnection(signed_transaction: credential.signedTransaction)
        if credential.appAccountToken != accountToken {
            guard let data = try keychain.data(for: "storekit.device-account-token"),
                  let string = String(data: data, encoding: .utf8),
                  UUID(uuidString: string) == credential.appAccountToken else { throw SubscriptionError.differentAccount }
            let app = try await AppTransaction.shared
            guard case .verified = app else { throw SubscriptionError.unverified }
            request.signed_app_transaction = app.jwsRepresentation
            request.legacy_token = credential.appAccountToken
        }
        return request
    }

    func cloudCredential() async throws -> CloudSubscriptionCredential {
        await refreshEntitlements()
        guard let result = activeEntitlement, case .verified(let transaction) = result else {
            throw SubscriptionError.subscriptionRequired
        }
        guard transaction.environment != .xcode else { throw SubscriptionError.developmentPurchase }
        guard let token = transaction.appAccountToken else { throw SubscriptionError.missingAccountToken }
        // jsonRepresentation is decoded JSON, not a signed transaction. The server must receive the JWS.
        return CloudSubscriptionCredential(signedTransaction: result.jwsRepresentation, appAccountToken: token)
    }
}
