import Foundation

struct STError: LocalizedError {
    let message: String
    var unauthorized = false
    var status = 0
    var errorDescription: String? { message }
}

struct STCommand {
    let capability: String
    let command: String
    let arguments: [Any]
    init(_ capability: String, _ command: String, _ arguments: [Any] = []) {
        self.capability = capability; self.command = command; self.arguments = arguments
    }
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

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Any? = nil) async throws -> Any {
        do {
            return try await send(method, path, query: query, body: body, token: try await token(false))
        } catch let e as STError where e.unauthorized {
            // Expired or revoked token: renew once and retry.
            return try await send(method, path, query: query, body: body, token: try await token(true))
        }
    }

    private func send(_ method: String, _ path: String, query: [URLQueryItem], body: Any?, token: String) async throws -> Any {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
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
        case 403: throw STError(message: path.hasPrefix("rules") ? "SmartThings didn't allow Aeris to manage schedules. Try signing in again."
                                                                 : "Aeris doesn't have permission for this device. Sign in again and allow device access.", status: 403)
        case 404: throw STError(message: path.hasPrefix("rules") ? "That schedule no longer exists in SmartThings."
                                                                 : "Device not found. Pick it again in Settings.", status: 404)
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
        try await commands(deviceId: deviceId, [STCommand(capability, command, arguments)])
    }

    func locationId(deviceId: String) async throws -> String {
        let json = try await request("GET", "devices/\(deviceId)") as? [String: Any]
        guard let loc = json?["locationId"] as? String else { throw STError(message: "SmartThings didn't say where this AC is.") }
        return loc
    }

    func timeZone(locationId: String) async -> TimeZone? {
        let json = try? await request("GET", "locations/\(locationId)") as? [String: Any]
        return (json?["timeZoneId"] as? String).flatMap(TimeZone.init(identifier:))
    }

    // MARK: Rules (used for schedules)

    func rules(locationId: String) async throws -> [[String: Any]] {
        let json = try await request("GET", "rules", query: [.init(name: "locationId", value: locationId)])
        if let list = json as? [[String: Any]] { return list }
        return (json as? [String: Any])?["items"] as? [[String: Any]] ?? []
    }

    func createRule(locationId: String, _ rule: [String: Any]) async throws -> String {
        let json = try await request("POST", "rules", query: [.init(name: "locationId", value: locationId)], body: rule)
        guard let id = (json as? [String: Any])?["id"] as? String else { throw STError(message: "SmartThings didn't create the schedule.") }
        return id
    }

    func deleteRule(id: String, locationId: String) async throws {
        _ = try await request("DELETE", "rules/\(id)", query: [.init(name: "locationId", value: locationId)])
    }

    /// Sends several commands in one request; SmartThings applies them in order.
    func commands(deviceId: String, _ list: [STCommand]) async throws {
        let body: [String: Any] = ["commands": list.map {
            ["component": "main", "capability": $0.capability, "command": $0.command, "arguments": $0.arguments]
        }]
        _ = try await request("POST", "devices/\(deviceId)/commands", body: body)
    }
}
