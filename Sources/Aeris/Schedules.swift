import Foundation

/// A recurring on/off time. Stored in SmartThings as a Rule named "Aeris: …", so it runs in the
/// cloud even when the Mac is asleep. A paused schedule has no rule and is remembered locally.
struct ACSchedule: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var ruleId: String?
    var turnOn: Bool
    var minutes: Int            // minutes after midnight, in the SmartThings location's time zone
    var days: [String]          // "Mon"…"Sun"; empty = every day
    var enabled: Bool { ruleId != nil }

    static let dayCodes = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var timeText: String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }   // used in rule names

    /// The time in the Mac's own clock format (12/24-hour).
    var displayTime: String {
        var c = DateComponents(); c.hour = minutes / 60; c.minute = minutes % 60
        let date = Calendar.current.date(from: c) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    var daysText: String {
        let set = Set(days)
        if set.isEmpty || set.count == 7 { return "Every day" }
        if set == ["Mon", "Tue", "Wed", "Thu", "Fri"] { return "Weekdays" }
        if set == ["Sat", "Sun"] { return "Weekends" }
        return Self.dayCodes.filter(set.contains).joined(separator: " ")
    }

    var ruleName: String { "Aeris: Turn \(turnOn ? "on" : "off") \(timeText) \(daysText)" }
}

/// The "turn off in …" timer: a one-day rule that Aeris deletes after it has fired.
struct SleepTimer: Codable, Equatable {
    var ruleId: String
    var fireDate: Date
}

enum RuleJSON {
    static let prefix = "Aeris: "
    static let timerPrefix = "Aeris: Timer"

    static func build(name: String, deviceId: String, turnOn: Bool, minutes: Int, days: [String]) -> [String: Any] {
        var specific: [String: Any] = [
            "reference": "Midnight",
            "offset": ["value": ["integer": minutes], "unit": "Minute"],
        ]
        if !days.isEmpty && days.count < 7 { specific["daysOfWeek"] = ACSchedule.dayCodes.filter(days.contains) }
        let command: [String: Any] = [
            "devices": [deviceId],
            "commands": [["component": "main", "capability": "switch", "command": turnOn ? "on" : "off", "arguments": []]],
        ]
        return ["name": name, "actions": [["every": ["specific": specific, "actions": [["command": command]]]]]]
    }

    /// Reads back an on/off rule Aeris created for this device; nil for anything else.
    static func parse(_ rule: [String: Any], deviceId: String) -> (turnOn: Bool, minutes: Int, days: [String])? {
        guard let name = rule["name"] as? String, name.hasPrefix(prefix),
              let every = ((rule["actions"] as? [[String: Any]])?.first?["every"]) as? [String: Any],
              let specific = every["specific"] as? [String: Any],
              (specific["reference"] as? String) == "Midnight",
              let minutes = (((specific["offset"] as? [String: Any])?["value"] as? [String: Any])?["integer"] as? NSNumber)?.intValue,
              let cmd = ((every["actions"] as? [[String: Any]])?.first?["command"]) as? [String: Any],
              (cmd["devices"] as? [String])?.contains(deviceId) == true,
              let first = (cmd["commands"] as? [[String: Any]])?.first,
              (first["capability"] as? String) == "switch",
              let verb = first["command"] as? String, verb == "on" || verb == "off" else { return nil }
        return (verb == "on", minutes, specific["daysOfWeek"] as? [String] ?? [])
    }
}

extension ACStore {
    private var pausedKey: String { "pausedSchedules.\(deviceId ?? "")" }
    private var timerKey: String { "sleepTimer.\(deviceId ?? "")" }

    private var pausedSchedules: [ACSchedule] {
        get {
            UserDefaults.standard.data(forKey: pausedKey)
                .flatMap { try? JSONDecoder().decode([ACSchedule].self, from: $0) } ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: pausedKey) }
    }

    private var storedTimer: SleepTimer? {
        get { UserDefaults.standard.data(forKey: timerKey).flatMap { try? JSONDecoder().decode(SleepTimer.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: timerKey) }
    }

    /// Location ID and time zone of the selected AC (cached).
    private func location() async throws -> (id: String, tz: TimeZone) {
        if let id = scheduleLocationId { return (id, scheduleTimeZone ?? .current) }
        guard let client, let deviceId else { throw STError(message: "Pick an air conditioner first.") }
        let id = try await client.locationId(deviceId: deviceId)
        let tz = await client.timeZone(locationId: id) ?? .current
        scheduleLocationId = id
        scheduleTimeZone = tz
        return (id, tz)
    }

    func loadSchedules() async {
        guard let client, let deviceId else { return }
        schedulesLoading = true
        defer { schedulesLoading = false }
        do {
            let loc = try await location()
            let rules = try await client.rules(locationId: loc.id)
            var active: [ACSchedule] = []
            var timerRuleIds: [String] = []
            for rule in rules {
                guard let id = rule["id"] as? String, let name = rule["name"] as? String,
                      let parsed = RuleJSON.parse(rule, deviceId: deviceId) else { continue }
                if name.hasPrefix(RuleJSON.timerPrefix) { timerRuleIds.append(id); continue }
                active.append(ACSchedule(ruleId: id, turnOn: parsed.turnOn, minutes: parsed.minutes, days: parsed.days))
            }
            // Timers are one-offs: drop ours once it has fired, and any leftovers.
            var timer = storedTimer
            if let t = timer, !timerRuleIds.contains(t.ruleId) || t.fireDate < Date().addingTimeInterval(-90) { timer = nil }
            for id in timerRuleIds where id != timer?.ruleId {
                try? await client.deleteRule(id: id, locationId: loc.id)
            }
            storedTimer = timer
            sleepTimer = timer
            schedules = (active + pausedSchedules).sorted { ($0.minutes, $0.turnOn ? 0 : 1) < ($1.minutes, $1.turnOn ? 0 : 1) }
            scheduleError = nil
        } catch {
            scheduleError = error.localizedDescription
        }
    }

    func addSchedule(turnOn: Bool, minutes: Int, days: [String]) async {
        guard let client, let deviceId else { return }
        do {
            let loc = try await location()
            var s = ACSchedule(turnOn: turnOn, minutes: minutes, days: days.count == 7 ? [] : days)
            s.ruleId = try await client.createRule(locationId: loc.id, RuleJSON.build(
                name: s.ruleName, deviceId: deviceId, turnOn: turnOn, minutes: s.minutes, days: s.days))
            await loadSchedules()
        } catch {
            scheduleError = error.localizedDescription
        }
    }

    func deleteSchedule(_ s: ACSchedule) async {
        guard let client else { return }
        do {
            if let rid = s.ruleId {
                let loc = try await location()
                do { try await client.deleteRule(id: rid, locationId: loc.id) }
                catch let e as STError where e.status == 404 {}
            }
            pausedSchedules.removeAll { $0.id == s.id }
            await loadSchedules()
        } catch {
            scheduleError = error.localizedDescription
        }
    }

    /// Pausing removes the SmartThings rule (rules can't be disabled) and remembers the schedule here.
    func setScheduleEnabled(_ s: ACSchedule, _ on: Bool) async {
        guard let client, let deviceId, s.enabled != on else { return }
        do {
            let loc = try await location()
            var updated = s
            if on {
                updated.ruleId = try await client.createRule(locationId: loc.id, RuleJSON.build(
                    name: s.ruleName, deviceId: deviceId, turnOn: s.turnOn, minutes: s.minutes, days: s.days))
                pausedSchedules.removeAll { $0.id == s.id }
            } else if let rid = s.ruleId {
                do { try await client.deleteRule(id: rid, locationId: loc.id) }
                catch let e as STError where e.status == 404 {}
                updated.ruleId = nil
                pausedSchedules.append(updated)
            }
            await loadSchedules()
        } catch {
            scheduleError = error.localizedDescription
        }
    }

    /// Turn the AC off after `minutes`. Runs in SmartThings, so it works with the Mac asleep.
    func startSleepTimer(minutes: Int) async {
        guard let client, let deviceId else { return }
        do {
            let loc = try await location()
            await cancelSleepTimer(reload: false)
            let fire = Date().addingTimeInterval(TimeInterval(minutes * 60))
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = loc.tz
            let c = cal.dateComponents([.hour, .minute, .weekday], from: fire)
            let minuteOfDay = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            let day = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][(c.weekday ?? 1) - 1]
            let name = "\(RuleJSON.timerPrefix) off \(String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60))"
            let id = try await client.createRule(locationId: loc.id, RuleJSON.build(
                name: name, deviceId: deviceId, turnOn: false, minutes: minuteOfDay, days: [day]))
            storedTimer = SleepTimer(ruleId: id, fireDate: fire)
            sleepTimer = storedTimer
            scheduleError = nil
        } catch {
            scheduleError = error.localizedDescription
        }
    }

    func cancelSleepTimer(reload: Bool = true) async {
        guard let client, let t = storedTimer ?? sleepTimer else { return }
        if let loc = try? await location() {
            do { try await client.deleteRule(id: t.ruleId, locationId: loc.id) }
            catch let e as STError where e.status == 404 {}
            catch { scheduleError = error.localizedDescription; return }
        }
        storedTimer = nil
        sleepTimer = nil
        if reload { await loadSchedules() }
    }
}
