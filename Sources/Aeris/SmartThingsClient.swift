import Foundation

struct STError: LocalizedError {
    let message: String
    var unauthorized = false
    var errorDescription: String? { message }
}

struct STDevice: Identifiable, Hashable {
    let id: String
    let label: String
    let isAC: Bool
}

/// Minimal SmartThings REST client. Status payloads are kept as loose JSON
/// because every AC model reports a slightly different set of capabilities.
struct SmartThingsClient {
    var baseURL = AuthConfig.apiBase
    /// Returns an access token; `true` asks for a freshly renewed one after a 401.
    let token: (_ forceRefresh: Bool) async throws -> String

    private func request(_ method: String, _ path: String, body: Any? = nil) async throws -> Any {
        do {
            return try await send(method, path, body: body, token: try await token(false))
        } catch let e as STError where e.unauthorized {
            // Expired or revoked token: renew once and retry.
            return try await send(method, path, body: body, token: try await token(true))
        }
    }

    private func send(_ method: String, _ path: String, body: Any?, token: String) async throws -> Any {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw STError(message: "Can't reach SmartThings. Check your internet connection.")
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300: break
        case 401: throw STError(message: "SmartThings rejected the sign-in. Sign in again in Settings.", unauthorized: true)
        case 403: throw STError(message: "Aeris doesn't have permission for this device. Sign in again and allow device access.")
        case 404: throw STError(message: "Device not found. Pick it again in Settings.")
        default:
            let text = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw STError(message: "SmartThings error \(code): \(text)")
        }
        if data.isEmpty { return [String: Any]() }
        return try JSONSerialization.jsonObject(with: data)
    }

    func devices() async throws -> [STDevice] {
        let json = try await request("GET", "devices") as? [String: Any]
        let items = json?["items"] as? [[String: Any]] ?? []
        let acCaps: Set<String> = ["airConditionerMode", "thermostatCoolingSetpoint", "airConditionerFanMode"]
        return items.compactMap { d in
            guard let id = d["deviceId"] as? String else { return nil }
            let comps = d["components"] as? [[String: Any]] ?? []
            let caps = Set(comps.flatMap { ($0["capabilities"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String } })
            let label = (d["label"] as? String) ?? (d["name"] as? String) ?? id
            return STDevice(id: id, label: label, isAC: !caps.isDisjoint(with: acCaps))
        }
    }

    func label(deviceId: String) async throws -> String {
        let json = try await request("GET", "devices/\(deviceId)") as? [String: Any]
        return (json?["label"] as? String) ?? (json?["name"] as? String) ?? "Air conditioner"
    }

    /// Returns components["main"] as [capability: [attribute: value]].
    func status(deviceId: String) async throws -> [String: [String: Any]] {
        let json = try await request("GET", "devices/\(deviceId)/status") as? [String: Any]
        let main = (json?["components"] as? [String: Any])?["main"] as? [String: Any] ?? [:]
        var out: [String: [String: Any]] = [:]
        for (cap, attrs) in main {
            guard let attrs = attrs as? [String: Any] else { continue }
            var values: [String: Any] = [:]
            for (name, obj) in attrs {
                if let obj = obj as? [String: Any], let v = obj["value"], !(v is NSNull) { values[name] = v }
            }
            out[cap] = values
        }
        return out
    }

    func health(deviceId: String) async -> String? {
        let json = try? await request("GET", "devices/\(deviceId)/health") as? [String: Any]
        return json?["state"] as? String
    }

    func command(deviceId: String, capability: String, command: String, arguments: [Any] = []) async throws {
        let body: [String: Any] = ["commands": [[
            "component": "main", "capability": capability, "command": command, "arguments": arguments,
        ]]]
        _ = try await request("POST", "devices/\(deviceId)/commands", body: body)
    }
}
