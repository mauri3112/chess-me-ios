import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import UIKit

@MainActor
final class LichessAuthentication: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    // Lichess requires a reverse-domain scheme for native OAuth callbacks.
    nonisolated static let defaultRedirectURI = URL(string: "com.chessme.app://oauth/callback")!
    @Published private(set) var account: LichessAccount?
    @Published private(set) var isConnecting = false
    @Published private(set) var lastError: String?

    private struct StoredCredential: Codable {
        let accessToken: String
        let account: LichessAccount
        let expiresAt: Date
    }
    private struct TokenResponse: Decodable {
        let access_token: String
        let token_type: String
        let expires_in: Int
    }

    private let keychain: KeychainStore
    private let client: LichessHTTPClient
    private let clientID: String
    private let redirectURI: URL
    private let credentialKey = "lichess.credentials"
    private var webSession: ASWebAuthenticationSession?
    private var credential: StoredCredential?
    private var anchor: ASPresentationAnchor?
    private var connectionID = UUID()

    init(keychain: KeychainStore = KeychainStore(), client: LichessHTTPClient = .shared,
         clientID: String = Bundle.main.object(forInfoDictionaryKey: "ChessMeLichessClientID") as? String ?? "chess-me-ios",
         redirectURI: URL = LichessAuthentication.defaultRedirectURI) {
        self.keychain = keychain
        self.client = client
        self.clientID = clientID
        self.redirectURI = redirectURI
        super.init()
        do {
            if let data = try keychain.data(for: credentialKey) {
                let saved = try JSONDecoder().decode(StoredCredential.self, from: data)
                if saved.expiresAt > Date() { credential = saved; account = saved.account }
                else { try keychain.delete(credentialKey) }
            }
        } catch { lastError = error.localizedDescription }
    }

    /// Validate a saved connection without discarding it merely because the phone is offline.
    func restore() async {
        guard let token = try? accessToken() else { return }
        do {
            let profile = try await fetchAccount(token: token)
            guard credential?.accessToken == token else { return }
            if let credential {
                let refreshed = StoredCredential(accessToken: token, account: profile, expiresAt: credential.expiresAt)
                try keychain.save(JSONEncoder().encode(refreshed), for: credentialKey)
                self.credential = refreshed
            }
            account = profile
            lastError = nil
        } catch LichessError.http(let status) where status == 401 || status == 403 {
            guard credential?.accessToken == token else { return }
            try? keychain.delete(credentialKey)
            credential = nil
            account = nil
            lastError = LichessError.notConnected.localizedDescription
        } catch is CancellationError {
        } catch { lastError = error.localizedDescription }
    }

    func accessToken() throws -> String {
        guard let credential, credential.expiresAt > Date() else { throw LichessError.notConnected }
        return credential.accessToken
    }

    func connect() async throws {
        guard !isConnecting else { throw LichessError.busy }
        try Task.checkCancellation()
        isConnecting = true
        lastError = nil
        let attemptID = UUID()
        connectionID = attemptID
        defer { isConnecting = false; webSession = nil; anchor = nil }
        do {
            guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow) else { throw LichessError.invalidResponse }
            anchor = window
            let verifier = try Self.randomURLSafeString(byteCount: 48)
            let state = try Self.randomURLSafeString(byteCount: 32)
            let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
            var authorization = URLComponents(string: "https://lichess.org/oauth")!
            // Empty scope is sufficient for account identity and completed public game exports.
            authorization.queryItems = [
                .init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
                .init(name: "redirect_uri", value: redirectURI.absoluteString),
                .init(name: "code_challenge_method", value: "S256"), .init(name: "code_challenge", value: challenge),
                .init(name: "state", value: state)
            ]
            let callback = try await authenticate(at: authorization.url!)
            try Task.checkCancellation()
            let code = try Self.validateCallback(callback, redirectURI: redirectURI, state: state)
            var request = LichessHTTPClient.request(URL(string: "https://lichess.org/api/token")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = Self.formBody([
                "grant_type": "authorization_code", "code": code, "code_verifier": verifier,
                "redirect_uri": redirectURI.absoluteString, "client_id": clientID
            ])
            let response = try JSONDecoder().decode(TokenResponse.self, from: await client.data(for: request))
            guard response.token_type.lowercased() == "bearer", !response.access_token.isEmpty,
                  response.expires_in > 0 else { throw LichessError.invalidResponse }
            do {
                let profile = try await fetchAccount(token: response.access_token)
                try Task.checkCancellation()
                guard connectionID == attemptID else { throw CancellationError() }
                let saved = StoredCredential(accessToken: response.access_token, account: profile,
                                             expiresAt: Date().addingTimeInterval(Double(response.expires_in)))
                try keychain.save(JSONEncoder().encode(saved), for: credentialKey)
                credential = saved
                account = profile
            } catch {
                // Do not leave an issued token active if storing or confirming the connection failed.
                await revoke(token: response.access_token)
                throw error
            }
        } catch is CancellationError { throw CancellationError() }
        catch { lastError = error.localizedDescription; throw error }
    }

    /// Remove the local credential before attempting online revocation.
    func disconnect() async {
        connectionID = UUID()
        webSession?.cancel()
        let token = credential?.accessToken
        do { try keychain.delete(credentialKey) }
        catch { lastError = error.localizedDescription; return }
        credential = nil
        account = nil
        lastError = nil
        if let token { await revoke(token: token) }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }

    private func authenticate(at url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: redirectURI.scheme) { callback, error in
                    if let callback { continuation.resume(returning: callback) }
                    else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                        continuation.resume(throwing: CancellationError())
                    } else { continuation.resume(throwing: error ?? LichessError.invalidCallback) }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = true
                webSession = session
                if !session.start() { continuation.resume(throwing: LichessError.invalidResponse) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.webSession?.cancel() }
        }
    }

    private func fetchAccount(token: String) async throws -> LichessAccount {
        var request = LichessHTTPClient.request(URL(string: "https://lichess.org/api/account")!, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let account = try JSONDecoder().decode(LichessAccount.self, from: await client.data(for: request))
        guard !account.id.isEmpty, LichessService.isValidUsername(account.username) else { throw LichessError.invalidResponse }
        return account
    }

    private func revoke(token: String) async {
        var request = LichessHTTPClient.request(URL(string: "https://lichess.org/api/token")!, token: token)
        request.httpMethod = "DELETE"
        do { _ = try await client.data(for: request) }
        catch {
            lastError = "The account was removed from this iPhone. Lichess could not confirm token revocation. Revoke chess-me under Lichess account permissions when you are online."
        }
    }

    static func validateCallback(_ callback: URL, redirectURI: URL, state: String) throws -> String {
        guard callback.scheme == redirectURI.scheme, callback.host == redirectURI.host,
              callback.path == redirectURI.path, callback.user == nil, callback.password == nil,
              callback.port == redirectURI.port, callback.fragment == nil,
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else {
            throw LichessError.invalidCallback
        }
        let query = components.queryItems ?? []
        let states = query.filter { $0.name == "state" }
        guard states.count == 1, states[0].value == state else { throw LichessError.invalidCallback }
        if query.contains(where: { $0.name == "error" }) { throw LichessError.denied }
        let codes = query.filter { $0.name == "code" }
        guard codes.count == 1, let code = codes[0].value,
              code.range(of: "^[A-Za-z0-9_]{1,1024}$", options: .regularExpression) != nil else {
            throw LichessError.invalidCallback
        }
        return code
    }

    static func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw LichessError.invalidResponse
        }
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func formBody(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let text = fields.sorted(by: { $0.key < $1.key }).map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&")
        return Data(text.utf8)
    }
}
