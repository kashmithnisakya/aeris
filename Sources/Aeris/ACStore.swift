import Combine
import Foundation
import ServiceManagement
import SwiftUI

/// App state: the selected AC, its latest status, and the actions that change it.
@MainActor
final class ACStore: ObservableObject {
    @Published var hasToken = AuthManager.shared.isSignedIn
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
    private var authWatch: AnyCancellable?

    init() {
        // Follow sign-in state; load the AC as soon as a sign-in completes.
        authWatch = AuthManager.shared.$credentials
            .map { $0 != nil }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] signedIn in
                guard let self, !self.demoMode else { return }
                self.hasToken = signedIn
                if signedIn { self.error = nil; Task { await self.refresh() } }
            }
        let poll = Double(ProcessInfo.processInfo.environment["AERIS_POLL_SECONDS"] ?? "") ?? 30
        timer = Timer.scheduledTimer(withTimeInterval: poll, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    private var client: SmartThingsClient? {
        guard AuthManager.shared.isSignedIn else { return nil }
        return SmartThingsClient { force in try await AuthManager.shared.accessToken(forceRefresh: force) }
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

    /// When true (README demo rendering), never touch the network.
    var demoMode = false

    func refresh() async {
        if demoMode { return }
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

    /// Several commands in one request, with optimistic (capability, attribute, value) updates.
    func sendAll(_ cmds: [STCommand], optimistic: [(String, String, Any)] = []) {
        guard let client, let id = deviceId else { return }
        for (cap, attr, v) in optimistic { status[cap, default: [:]][attr] = v }
        Task {
            busy = true
            defer { busy = false }
            do {
                try await client.commands(deviceId: id, cmds)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                self.error = error.localizedDescription
            }
            await refresh()
        }
    }

    // MARK: - Airflow (samsungce.airConditionerAirFlowDirection)

    static let airflowCap = "samsungce.airConditionerAirFlowDirection"

    enum Axis { case vertical, horizontal
        var name: String { self == .vertical ? "Vertical" : "Horizontal" }
        var directionAttr: String { self == .vertical ? "verticalDirection" : "horizontalDirection" }
        var stepAttr: String { self == .vertical ? "verticalAngleStep" : "horizontalAngleStep" }
        var stepsAttr: String { self == .vertical ? "supportedVerticalAngleSteps" : "supportedHorizontalAngleSteps" }
        var directionsAttr: String { self == .vertical ? "supportedVerticalDirections" : "supportedHorizontalDirections" }
    }

    var hasAirflow: Bool { has(Self.airflowCap) }
    func airflowSteps(_ a: Axis) -> [String] { value(Self.airflowCap, a.stepsAttr) ?? [] }
    func airflowCanSwing(_ a: Axis) -> Bool { (value(Self.airflowCap, a.directionsAttr) as [String]?)?.contains("swing") ?? false }
    func airflowSwinging(_ a: Axis) -> Bool { (value(Self.airflowCap, a.directionAttr) as String?) == "swing" }
    func airflowStep(_ a: Axis) -> String? { value(Self.airflowCap, a.stepAttr) }
    var swingRanges: [String] { value(Self.airflowCap, "supportedHorizontalSwingRanges") ?? [] }
    var swingRange: String? { value(Self.airflowCap, "horizontalSwingRange") }

    func setAirflowSwing(_ a: Axis) {
        sendAll([STCommand(Self.airflowCap, "set\(a.name)Direction", ["swing"])],
                optimistic: [(Self.airflowCap, a.directionAttr, "swing")])
    }

    func setAirflowAngle(_ a: Axis, step: String) {
        sendAll([STCommand(Self.airflowCap, "set\(a.name)Direction", ["fixed"]),
                 STCommand(Self.airflowCap, "set\(a.name)AngleStep", [step])],
                optimistic: [(Self.airflowCap, a.directionAttr, "fixed"), (Self.airflowCap, a.stepAttr, step)])
    }

    func setSwingRange(_ range: String) {
        sendAll([STCommand(Self.airflowCap, "setHorizontalSwingRange", [range])],
                optimistic: [(Self.airflowCap, "horizontalSwingRange", range)])
    }

    // MARK: - Feature switches

    struct FeatureSwitch: Identifiable {
        let id: String          // capability
        let name: String
        let icon: String
        let attr: String
        let onCommand: STCommand
        let offCommand: STCommand
    }

    static let featureSwitches: [FeatureSwitch] = [
        FeatureSwitch(id: "samsungce.airConditionerLighting", name: "Display light", icon: "lightbulb", attr: "lighting",
                      onCommand: STCommand("samsungce.airConditionerLighting", "on"),
                      offCommand: STCommand("samsungce.airConditionerLighting", "off")),
        FeatureSwitch(id: "samsungce.airConditionerBeep", name: "Beep", icon: "speaker.wave.2", attr: "beep",
                      onCommand: STCommand("samsungce.airConditionerBeep", "on"),
                      offCommand: STCommand("samsungce.airConditionerBeep", "off")),
        FeatureSwitch(id: "custom.autoCleaningMode", name: "Auto clean", icon: "sparkles", attr: "autoCleaningMode",
                      onCommand: STCommand("custom.autoCleaningMode", "setAutoCleaningMode", ["on"]),
                      offCommand: STCommand("custom.autoCleaningMode", "setAutoCleaningMode", ["off"])),
    ]

    /// Switches this AC actually reports (and isn't marking unavailable).
    var availableSwitches: [FeatureSwitch] {
        let unavailable: [String] = value("samsungce.unavailableCapabilities", "unavailableCommands") ?? []
        return Self.featureSwitches.filter { sw in
            has(sw.id) && (value(sw.id, sw.attr) as String?).map { $0 == "on" || $0 == "off" } == true
                && !unavailable.contains("\(sw.id).\(sw.onCommand.command)")
        }
    }

    func isSwitchOn(_ sw: FeatureSwitch) -> Bool { (value(sw.id, sw.attr) as String?) == "on" }

    func toggle(_ sw: FeatureSwitch) {
        let on = !isSwitchOn(sw)
        sendAll([on ? sw.onCommand : sw.offCommand], optimistic: [(sw.id, sw.attr, on ? "on" : "off")])
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
        AuthManager.shared.usePersonalAccessToken(token)
        error = nil
        Task { await refresh() }
    }

    func signOut() {
        AuthManager.shared.signOut()
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
