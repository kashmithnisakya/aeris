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

    private let timerOptions = [(30, "30 min"), (60, "1 hr"), (120, "2 hr"), (240, "4 hr")]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(title: "Schedules", done: done)
                .overlay(alignment: .trailing) {
                    if store.schedulesLoading || working { ProgressView().controlSize(.mini).padding(.trailing, 4) }
                }

            timerCard
            schedulesCard
            if adding { addCard }

            if let err = store.scheduleError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Schedules run in SmartThings, so they work even when your Mac is asleep. Times use your SmartThings location's time zone\(store.scheduleTimeZone.map { " (\($0.identifier))" } ?? "").")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .task { await store.loadSchedules() }
    }

    // MARK: Timer

    private var timerCard: some View {
        Card(spacing: 8) {
            SectionLabel("Sleep timer")
            if let t = store.sleepTimer, t.fireDate > Date() {
                HStack(spacing: 10) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 14)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.indigo.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Turns off at \(t.fireDate.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 13, weight: .medium))
                        Text(t.fireDate, style: .relative).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cancel") { run { await store.cancelSleepTimer() } }.buttonStyle(SecondaryButtonStyle())
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(timerOptions, id: \.0) { mins, label in
                        Button { run { await store.startSleepTimer(minutes: mins) } } label: {
                            Text(label).font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .disabled(!store.isOn)
                .opacity(store.isOn ? 1 : 0.45)
                if !store.isOn {
                    Text("Turn the AC on to start a timer.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: List

    private var schedulesCard: some View {
        Card(spacing: 0) {
            SectionLabel("On / off schedules").padding(.bottom, 6)
            if store.schedules.isEmpty && !store.schedulesLoading {
                Text("No schedules yet.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 6)
            }
            ForEach(store.schedules) { s in
                HStack(spacing: 10) {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(s.turnOn ? Color.white : Color.secondary)
                        .frame(width: 28, height: 28)
                        .background(s.turnOn ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(Color.primary.opacity(0.1)), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.displayTime).font(.system(size: 17, weight: .regular, design: .rounded)).monospacedDigit()
                        Text("\(s.turnOn ? "Turn on" : "Turn off") · \(s.daysText)")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { run { await store.deleteSchedule(s) } } label: {
                        Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).help("Delete")
                    MiniSwitch(isOn: s.enabled) { run { await store.setScheduleEnabled(s, !s.enabled) } }
                        .help(s.enabled ? "Pause" : "Resume")
                        .accessibilityLabel("\(s.turnOn ? "On" : "Off") at \(s.displayTime)")
                }
                .padding(.vertical, 7)
                .opacity(s.enabled ? 1 : 0.55)
                Divider().padding(.leading, 38)
            }
            if !adding {
                Button { withAnimation(.snappy(duration: 0.25)) { adding = true } } label: {
                    Label("Add schedule", systemImage: "plus").font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Add

    private var addCard: some View {
        Card(spacing: 10) {
            SectionLabel("New schedule")
            HStack(spacing: 10) {
                SegmentedControl(options: ["on", "off"], selected: turnOn ? "on" : "off",
                                 label: { $0 == "on" ? "Turn on" : "Turn off" }) { turnOn = $0 == "on" }
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden().datePickerStyle(.field).frame(width: 84)
            }
            HStack(spacing: 4) {
                ForEach(ACSchedule.dayCodes, id: \.self) { d in
                    let on = days.contains(d)
                    Button {
                        if on { if days.count > 1 { days.remove(d) } } else { days.insert(d) }
                    } label: {
                        Text(String(d.prefix(1)))
                            .font(.system(size: 11.5, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(on ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)), in: Circle())
                            .foregroundStyle(on ? Color.white : Color.secondary)
                    }
                    .buttonStyle(PressableStyle())
                    .help(d)
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 6) {
                Button("Weekdays") { days = ["Mon", "Tue", "Wed", "Thu", "Fri"] }.buttonStyle(SecondaryButtonStyle())
                Button("Every day") { days = Set(ACSchedule.dayCodes) }.buttonStyle(SecondaryButtonStyle())
                Spacer()
            }
            HStack(spacing: 8) {
                Button("Cancel") { withAnimation(.snappy(duration: 0.25)) { adding = false } }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Add schedule") {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                    let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                    run {
                        await store.addSchedule(turnOn: turnOn, minutes: minutes, days: ACSchedule.dayCodes.filter(days.contains))
                        if store.scheduleError == nil { withAnimation { adding = false } }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        working = true
        Task { await work(); working = false }
    }
}
