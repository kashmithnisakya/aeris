import Foundation

/// Uses the official SmartThings CLI (`brew install smartthingscommunity/smartthings/smartthings`)
/// for sign-in. The CLI logs in through the browser once and keeps its own refresh token. Aeris only
/// reads the CLI's current access token, and asks the CLI to renew it by running a cheap command.
/// Aeris never uses or stores the CLI's refresh token, so the two never race to rotate it.
enum SmartThingsCLI {
    struct Token { let value: String; let expires: Date }

    /// Where the CLI is installed, if it is.
    static var executable: URL? {
        let env = ProcessInfo.processInfo.environment
        let candidates = [env["AERIS_ST_CLI"], "/opt/homebrew/bin/smartthings", "/usr/local/bin/smartthings"]
        return candidates.compactMap { $0 }.map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var isInstalled: Bool { executable != nil }

    static var credentialsFile: URL {
        if let p = ProcessInfo.processInfo.environment["AERIS_ST_CREDENTIALS"] { return URL(fileURLWithPath: p) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/@smartthings/cli/credentials.json")
    }

    /// The CLI's current access token for the default profile, if it has one.
    static func currentToken() -> Token? {
        guard let data = try? Data(contentsOf: credentialsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let entry = (json["default:api.smartthings.com"] as? [String: Any])
            ?? json.first(where: { $0.key.hasPrefix("default:") })?.value as? [String: Any]
        guard let token = entry?["accessToken"] as? String, !token.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expires = (entry?["expires"] as? String).flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
        return Token(value: token, expires: expires ?? .distantPast)
    }

    /// Runs a read-only CLI command. If the CLI's token has expired it renews it; if the CLI isn't
    /// logged in it opens the browser for SmartThings sign-in and waits (up to `timeout`).
    static func ensureLoggedIn(timeout: TimeInterval) async throws {
        guard let exe = executable else {
            throw STError(message: "Install the SmartThings CLI first: brew install smartthingscommunity/smartthings/smartthings")
        }
        let status: Int32 = try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = exe
            p.arguments = ["locations", "--json"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            p.environment = env
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { cont.resume(throwing: error); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if p.isRunning { p.terminate() }
            }
        }
        guard status == 0 else {
            throw STError(message: "SmartThings sign-in didn't finish. Click Sign in with SmartThings to try again.")
        }
    }
}
