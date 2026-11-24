import SwiftUI

/// Recurring on/off schedules and the "turn off in…" timer.
struct SchedulesView: View {
    @EnvironmentObject var store: ACStore
    var done: () -> Void

    @State private var turnOn = true
    @State private var time = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var days: Set<String> = Set(ACSchedule.dayCodes)
    @State private var adding = false
    @State private var working = false

    private let timerOptions = [(30, "30 min"), (60, "1 h"), (120, "2 h"), (240, "4 h")]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Schedules").font(.headline)
                Spacer()
                if store.schedulesLoading || working { ProgressView().controlSize(.small) }
                Button("Done", action: done).buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }

            timerSection
            Divider()
            scheduleList
            if adding { addForm } else {
                Button { adding = true } label: { Label("Add schedule", systemImage: "plus.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }

            if let err = store.scheduleError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Schedules run in SmartThings, so they work even when your Mac is asleep. Times use your SmartThings location's time zone\(store.scheduleTimeZone.map { " (\($0.identifier))" } ?? "").")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { await store.loadSchedules() }
    }

    // MARK: Timer

    @ViewBuilder private var timerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Turn off in").font(.caption).foregroundStyle(.secondary)
            if let t = store.sleepTimer, t.fireDate > Date() {
                HStack {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(Color.accentColor)
                    Text("Turns off at \(t.fireDate.formatted(date: .omitted, time: .shortened))").font(.callout)
                    Spacer()
                    Button("Cancel") { run { await store.cancelSleepTimer() } }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 5) {
                    ForEach(timerOptions, id: \.0) { mins, label in
                        Button(label) { run { await store.startSleepTimer(minutes: mins) } }
                            .buttonStyle(.plain).font(.callout)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
                .disabled(!store.isOn)
                .opacity(store.isOn ? 1 : 0.45)
                .help(store.isOn ? "" : "Turn the AC on to start a timer")
            }
        }
    }

    // MARK: List

    @ViewBuilder private var scheduleList: some View {
        if store.schedules.isEmpty && !store.schedulesLoading {
            Text("No schedules yet. Add one to turn the AC on or off automatically.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(store.schedules) { s in
            HStack(spacing: 8) {
                Image(systemName: s.turnOn ? "power.circle.fill" : "power.circle")
                    .foregroundStyle(s.turnOn ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(s.turnOn ? "On" : "Off") at \(s.displayTime)").font(.callout.weight(.medium)).monospacedDigit()
                    Text(s.daysText + (s.enabled ? "" : " · paused")).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button { run { await store.setScheduleEnabled(s, !s.enabled) } } label: {
                    Image(systemName: s.enabled ? "pause.circle" : "play.circle")
                }
                .buttonStyle(.plain).help(s.enabled ? "Pause" : "Resume")
                Button { run { await store.deleteSchedule(s) } } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete")
            }
            .opacity(s.enabled ? 1 : 0.55)
        }
    }

    // MARK: Add

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                toggleChip("Turn on", selected: turnOn) { turnOn = true }
                toggleChip("Turn off", selected: !turnOn) { turnOn = false }
                Spacer()
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .frame(width: 80)
            }
            HStack(spacing: 4) {
                ForEach(ACSchedule.dayCodes, id: \.self) { d in
                    toggleChip(String(d.prefix(2)), selected: days.contains(d), compact: true) {
                        if days.contains(d) { if days.count > 1 { days.remove(d) } } else { days.insert(d) }
                    }
                }
            }
            HStack(spacing: 6) {
                Button("Weekdays") { days = ["Mon", "Tue", "Wed", "Thu", "Fri"] }
                Button("Every day") { days = Set(ACSchedule.dayCodes) }
                Spacer()
                Button("Cancel") { adding = false }.foregroundStyle(.secondary)
                Button("Add") {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                    let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                    run {
                        await store.addSchedule(turnOn: turnOn, minutes: minutes, days: ACSchedule.dayCodes.filter(days.contains))
                        if store.scheduleError == nil { adding = false }
                    }
                }
                .foregroundStyle(Color.accentColor).fontWeight(.semibold)
            }
            .buttonStyle(.plain).font(.caption)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func toggleChip(_ title: String, selected: Bool, compact: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(compact ? .caption : .callout)
                .padding(.horizontal, compact ? 0 : 10).padding(.vertical, 4)
                .frame(minWidth: compact ? 30 : nil)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func run(_ work: @escaping () async -> Void) {
        working = true
        Task { await work(); working = false }
    }
}
