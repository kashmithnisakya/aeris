import AppKit
import Foundation

/// What Aeris uses to call the SmartThings API.
struct Credentials: Codable, Equatable {
    /// oauth: Aeris's own SmartThings app; cli: the SmartThings CLI's login; pat: personal access token.
    enum Kind: String, Codable { case oauth, cli, pat }
    var kind: Kind
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
}

/// A SmartThings OAuth app (client ID + secret).
struct OAuthClient: Codable, Equatable {
    var id: String
    var secret: String
}

enum AuthConfig {
    static let redirectURI = "https://kashmithnisakya.github.io/aeris/callback/"
    static let callbackScheme = "aeris"
    static let scopes = ["r:devices:*", "x:devices:*", "r:locations:*"]
    static var apiBase: URL {
        URL(string: ProcessInfo.processInfo.environment["AERIS_API"] ?? "https://api.smartthings.com/v1")!
    }

    /// Client baked into release builds (from Info.plist), or supplied via env for development.
    static var builtInClient: OAuthClient? {
        let env = ProcessInfo.processInfo.environment
        let info = Bundle.main.infoDictionary ?? [:]
        let id = env["AERIS_CLIENT_ID"] ?? info["AerisClientID"] as? String ?? ""
        let secret = env["AERIS_CLIENT_SECRET"] ?? info["AerisClientSecret"] as? String ?? ""
        return id.isEmpty || secret.isEmpty ? nil : OAuthClient(id: id, secret: secret)
    }
}

/// Signs in with SmartThings (OAuth authorization code flow), stores tokens in the Keychain and
/// renews the 24-hour access token with the refresh token. Refresh tokens are single-use, so
/// renewals are serialized and the new pair is saved immediately.
@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var credentials: Credentials?
    @Published private(set) var customClient: OAuthClient?
    @Published private(set) var signingIn = false
    @Published var lastError: String?

    private var pendingState: String?
    private var refreshTask: Task<String, Error>?

    var client: OAuthClient? { AuthConfig.builtInClient ?? customClient }
    var hasBuiltInClient: Bool { AuthConfig.builtInClient != nil }
    var isSignedIn: Bool { credentials != nil }

    #if DEBUG
    /// README demo rendering only.
    func setDemoState(credentials: Credentials?, signingIn: Bool) {
        self.credentials = credentials
        self.signingIn = signingIn
        self.lastError = nil
    }
    #endif

    private init() {
        customClient = Keychain.get(OAuthClient.self, .oauthClient)
        if let env = ProcessInfo.processInfo.environment["AERIS_TOKEN"], !env.isEmpty {
            // Development only: use a token without touching the Keychain.
            credentials = Credentials(kind: .pat, accessToken: env)
        } else if let saved = Keychain.get(Credentials.self, .credentials) {
            credentials = saved
        } else if let legacy = Keychain.data(.legacyToken).flatMap({ String(data: $0, encoding: .utf8) }) {
            // Migrate a personal access token saved by Aeris 1.x.
            store(Credentials(kind: .pat, accessToken: legacy))
            Keychain.delete(.legacyToken)
        }
    }

    // MARK: - Sign in

    /// Opens the SmartThings sign-in page. Tests can pass their own opener.
    func beginSignIn(open: (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        guard let client else { return beginCLISignIn() }
        let state = UUID().uuidString
        pendingState = state
        signingIn = true
        lastError = nil
        open(authorizeURL(client: client, state: state))
    }

    /// Sign in through the SmartThings CLI: it opens the browser if it isn't logged in yet.
    func beginCLISignIn() {
        guard SmartThingsCLI.isInstalled else {
            lastError = "Install the SmartThings CLI first (see below), then click Sign in again."
            return
        }
        signingIn = true
        lastError = nil
        Task {
            defer { signingIn = false }
            do {
                try await SmartThingsCLI.ensureLoggedIn(timeout: 600)
                guard SmartThingsCLI.currentToken() != nil else {
                    throw STError(message: "The SmartThings CLI didn't save a login. Try again.")
                }
                guard signingIn else { return }   // cancelled meanwhile
                store(Credentials(kind: .cli, accessToken: ""))
            } catch {
                if signingIn { lastError = error.localizedDescription }
            }
        }
    }

    func cancelSignIn() {
        pendingState = nil
        signingIn = false
    }

    func authorizeURL(client: OAuthClient, state: String) -> URL {
        var c = URLComponents(url: AuthConfig.apiBase.appendingPathComponent("oauth/authorize"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "client_id", value: client.id),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: AuthConfig.redirectURI),
            .init(name: "scope", value: AuthConfig.scopes.joined(separator: " ")),
            .init(name: "state", value: state),
        ]
        return c.url!
    }

    /// Handles aeris://oauth/callback?code=…&state=… (or ?error=…).
    func handleCallback(_ url: URL) async {
        guard url.scheme == AuthConfig.callbackScheme else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let q = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        defer { signingIn = false }

        guard let expected = pendingState, q["state"] == expected else {
            lastError = "That sign-in link didn't come from this Aeris window. Please try again."
            return
        }
        pendingState = nil
        if let err = q["error"] {
            lastError = err == "access_denied" ? "Sign-in was cancelled." : "SmartThings sign-in failed: \(err)"
            return
        }
        guard let code = q["code"], !code.isEmpty, let client else {
            lastError = "SmartThings didn't return a sign-in code."
            return
        }
        do {
            let creds = try await tokenRequest(client: client, params: [
                "grant_type": "authorization_code",
                "code": code,
                "client_id": client.id,
                "redirect_uri": AuthConfig.redirectURI,
            ])
            store(creds)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Tokens

    /// A valid access token, renewing it first if it's about to expire (or if `forceRefresh`).
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let creds = credentials else { throw STError(message: "Sign in with SmartThings to continue.") }
        if creds.kind == .cli { return try await cliAccessToken(forceRefresh: forceRefresh) }
        guard creds.kind == .oauth else {
            if forceRefresh {
                throw STError(message: "Your personal access token expired. Sign in with SmartThings so Aeris can renew access by itself.")
            }
            return creds.accessToken
        }
        let expiresSoon = (creds.expiresAt ?? .distantPast) < Date().addingTimeInterval(5 * 60)
        if !forceRefresh && !expiresSoon { return creds.accessToken }

        if let running = refreshTask { return try await running.value }
        let task = Task { () throws -> String in
            defer { refreshTask = nil }
            return try await renew(creds)
        }
        refreshTask = task
        return try await task.value
    }

    /// Reads the CLI's token; when it's close to expiry (or rejected) asks the CLI to renew it.
    private func cliAccessToken(forceRefresh: Bool) async throws -> String {
        let soon = Date().addingTimeInterval(5 * 60)
        if !forceRefresh, let t = SmartThingsCLI.currentToken(), t.expires > soon { return t.value }
        if let running = refreshTask { return try await running.value }
        let before = SmartThingsCLI.currentToken()?.value
        let task = Task { () throws -> String in
            defer { refreshTask = nil }
            try await SmartThingsCLI.ensureLoggedIn(timeout: 180)
            guard let t = SmartThingsCLI.currentToken(), t.expires > Date(),
                  !(forceRefresh && t.value == before && t.expires <= soon) else {
                throw STError(message: "SmartThings sign-in expired. Click Sign in with SmartThings in Settings.")
            }
            return t.value
        }
        refreshTask = task
        return try await task.value
    }

    private func renew(_ creds: Credentials) async throws -> String {
        guard let refresh = creds.refreshToken, let client else {
            signOut(keepClient: true)
            throw STError(message: "Your SmartThings sign-in expired. Sign in again.")
        }
        do {
            let new = try await tokenRequest(client: client, params: [
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": client.id,
            ])
            store(new)
            return new.accessToken
        } catch let e as TokenError where e.isRejected {
            signOut(keepClient: true)
            throw STError(message: "Your SmartThings sign-in expired. Sign in again.")
        }
    }

    private struct TokenError: LocalizedError {
        let status: Int
        let message: String
        var isRejected: Bool { status == 400 || status == 401 }
        var errorDescription: String? { message }
    }

    private func tokenRequest(client: OAuthClient, params: [String: String]) async throws -> Credentials {
        var req = URLRequest(url: AuthConfig.apiBase.appendingPathComponent("oauth/token"))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        let basic = Data("\(client.id):\(client.secret)".utf8).base64EncodedString()
        req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = Self.formEncode(params).data(using: .utf8)

        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw STError(message: "Can't reach SmartThings. Check your internet connection.") }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let detail = (json["error_description"] as? String) ?? (json["error"] as? String) ?? "HTTP \(status)"
            let hint = status == 401 ? " Check the Client ID and Secret." : ""
            throw TokenError(status: status, message: "SmartThings sign-in failed: \(detail).\(hint)")
        }
        guard let access = json["access_token"] as? String else {
            throw TokenError(status: status, message: "SmartThings sign-in failed: no access token in the response.")
        }
        let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? 86_000
        return Credentials(kind: .oauth,
                           accessToken: access,
                           refreshToken: json["refresh_token"] as? String,
                           expiresAt: Date().addingTimeInterval(expiresIn))
    }

    private static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }

    // MARK: - Settings

    func usePersonalAccessToken(_ token: String) {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        store(Credentials(kind: .pat, accessToken: t))
        lastError = nil
    }

    func saveCustomClient(id: String, secret: String) {
        let c = OAuthClient(id: id.trimmingCharacters(in: .whitespacesAndNewlines),
                            secret: secret.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !c.id.isEmpty, !c.secret.isEmpty else { return }
        Keychain.put(c, .oauthClient)
        customClient = c
    }

    func removeCustomClient() {
        Keychain.delete(.oauthClient)
        customClient = nil
    }

    func signOut(keepClient: Bool = true) {
        refreshTask?.cancel()
        refreshTask = nil
        credentials = nil
        Keychain.delete(.credentials)
        if !keepClient { removeCustomClient() }
    }

    private func store(_ creds: Credentials) {
        credentials = creds
        if ProcessInfo.processInfo.environment["AERIS_TOKEN"] == nil {
            Keychain.put(creds, .credentials)
        }
    }
}


#if DEBUG
/// Test hook: AERIS_TEST_SIGNIN=1 starts sign-in at launch and follows the authorize redirect itself
/// (instead of a browser), then opens the resulting aeris:// URL through macOS like the callback page does.
enum SignInTestHook {
    @MainActor static func startIfRequested() {
        guard ProcessInfo.processInfo.environment["AERIS_TEST_SIGNIN"] == "1" else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            AuthManager.shared.beginSignIn { url in
                Task {
                    let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
                    guard let (_, resp) = try? await session.data(from: url),
                          let loc = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"),
                          let callback = URL(string: loc) else { return }
                    _ = await MainActor.run { NSWorkspace.shared.open(callback) }
                }
            }
        }
    }
    final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }
}
#endif
