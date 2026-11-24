import Foundation
import ServiceManagement
import SwiftUI

/// App state: the selected AC, its latest status, and the actions that change it.
@MainActor
final class ACStore: ObservableObject {
    @Published var hasToken = Keychain.read() != nil
    @Published var deviceId: String? = UserDefaults.standard.string(forKey: "deviceId")
    @Published var deviceName = UserDefaults.standard.string(forKey: "deviceName") ?? "Air conditioner"
    @Published var status: [String: [String: Any]] = [:]
    @Published var online: Bool?
    @Published var error: String?
    @Published var busy = false
    @Published var devices: [STDevice] = []
    @Published var pendingSetpoint: Double?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var timer: Timer?
    private var setpointTask: Task<Void, Never>?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    private var client: SmartThingsClient? {
        Keychain.read().map { SmartThingsClient(token: $0) }
    }

    // MARK: - Reading status

    func value<T>(_ cap: String, _ attr: String) -> T? { status[cap]?[attr] as? T }

    var disabledCaps: [String] { value("custom.disabledCapabilities", "disabledCapabilities") ?? [] }
    func has(_ cap: String) -> Bool { status[cap] != nil && !disabledCaps.contains(cap) }

    var isOn: Bool { (value("switch", "switch") as String?) == "on" }
    var roomTemp: Double? { (value("temperatureMeasurement", "temperature") as NSNumber?)?.doubleValue }
    var humidity: Double? { (value("relativeHumidityMeasurement", "humidity") as NSNumber?)?.doubleValue }
    var setpoint: Double? {
        pendingSetpoint ?? (value("thermostatCoolingSetpoint", "coolingSetpoint") as NSNumber?)?.doubleValue
    }
    var setpointRange: ClosedRange<Double> {
        let lo = (value("custom.thermostatSetpointControl", "minimumSetpoint") as NSNumber?)?.doubleValue ?? 16
        let hi = (value("custom.thermostatSetpointControl", "maximumSetpoint") as NSNumber?)?.doubleValue ?? 30
        return lo...max(lo, hi)
    }

    // MARK: - Network

    func refresh() async {
        guard let client else { hasToken = false; return }
        hasToken = true
        if deviceId == nil {
            do {
                let list = try await client.devices()
                devices = list
                if let ac = list.first(where: { $0.isAC }) { selectDevice(ac) } else {
                    error = "No air conditioner found on this SmartThings account."
                    return
                }
            } catch { self.error = error.localizedDescription; return }
        }
        guard let id = deviceId else { return }
        do {
            async let s = client.status(deviceId: id)
            async let h = client.health(deviceId: id)
            let (newStatus, health) = try await (s, h)
            status = newStatus
            online = health.map { $0 == "ONLINE" }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func send(_ cap: String, _ cmd: String, _ args: [Any] = [], optimistic: (String, Any)? = nil) {
        guard let client, let id = deviceId else { return }
        if let (attr, v) = optimistic { status[cap, default: [:]][attr] = v }
        Task {
            busy = true
            defer { busy = false }
            do {
                try await client.command(deviceId: id, capability: cap, command: cmd, arguments: args)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                self.error = error.localizedDescription
            }
            await refresh()
        }
    }

    func togglePower() {
        let next = isOn ? "off" : "on"
        send("switch", next, optimistic: ("switch", next))
    }

    /// Debounced so several quick taps send only one command.
    func nudgeSetpoint(_ delta: Double) {
        guard let current = setpoint else { return }
        let r = setpointRange
        pendingSetpoint = min(r.upperBound, max(r.lowerBound, current + delta))
        setpointTask?.cancel()
        setpointTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, let v = pendingSetpoint else { return }
            status["thermostatCoolingSetpoint", default: [:]]["coolingSetpoint"] = NSNumber(value: v)
            pendingSetpoint = nil
            let arg: Any = v.rounded() == v ? Int(v) : v
            send("thermostatCoolingSetpoint", "setCoolingSetpoint", [arg])
        }
    }

    // MARK: - Settings

    func saveToken(_ token: String) {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        Keychain.save(t)
        hasToken = true
        error = nil
        Task { await refresh() }
    }

    func signOut() {
        Keychain.delete()
        hasToken = false
        status = [:]
        devices = []
        deviceId = nil
        UserDefaults.standard.removeObject(forKey: "deviceId")
    }

    func loadDevices() async {
        guard let client else { return }
        do { devices = try await client.devices().sorted { $0.isAC && !$1.isAC } }
        catch { self.error = error.localizedDescription }
    }

    func selectDevice(_ d: STDevice) {
        deviceId = d.id
        deviceName = d.label
        UserDefaults.standard.set(d.id, forKey: "deviceId")
        UserDefaults.standard.set(d.label, forKey: "deviceName")
        status = [:]
        Task { await refresh() }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = "Couldn't change Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
