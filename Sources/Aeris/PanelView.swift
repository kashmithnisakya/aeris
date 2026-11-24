import SwiftUI

// MARK: - Labels and icons

private let labels: [String: String] = [
    "cool": "Cool", "heat": "Heat", "dry": "Dry", "wind": "Fan", "fan": "Fan", "auto": "Auto", "aIComfort": "AI",
    "low": "Low", "medium": "Med", "high": "High", "turbo": "Turbo",
    "fixed": "Off", "all": "All", "vertical": "Up/Down", "horizontal": "Left/Right", "left": "Left", "right": "Right",
    "off": "Off", "sleep": "Sleep", "quiet": "Quiet", "smart": "Smart", "speed": "Speed", "windFree": "WindFree",
    "windFreeSleep": "WF Sleep", "longWind": "Long", "comfort": "Comfort", "twoStep": "2-step", "energySaving": "Eco",
]

func pretty(_ v: String) -> String {
    if let l = labels[v] { return l }
    let spaced = v.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    return spaced.prefix(1).uppercased() + spaced.dropFirst()
}

private let modeIcons: [String: String] = [
    "cool": "snowflake", "dry": "drop", "wind": "fan", "fan": "fan", "auto": "arrow.triangle.2.circlepath",
    "heat": "flame", "aIComfort": "sparkles",
]

private let modeVerbs: [String: String] = [
    "cool": "Cooling", "dry": "Drying", "wind": "Fan only", "fan": "Fan only", "auto": "Auto", "heat": "Heating",
    "aIComfort": "AI comfort",
]

// MARK: - Panel

struct PanelView: View {
    @EnvironmentObject var store: ACStore
    @State private var showSettings = false
    @State private var showSchedules = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let err = store.error { ErrorBanner(text: err) }
            if !store.hasToken || showSettings {
                SettingsView(done: { showSettings = false })
            } else if showSchedules {
                SchedulesView(done: { showSchedules = false })
            } else {
                controls
            }
        }
        .padding(12)
        // Pin to the top and report the content's own height, so the menu bar window
        // resizes to each screen instead of centering a shorter one in leftover space.
        .frame(width: 320, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .task { await store.refresh() }
        .animation(.snappy(duration: 0.25), value: store.isOn)
    }

    // MARK: Header

    private var statusLine: String {
        guard store.hasToken else { return "Not signed in" }
        if store.online == false { return "Offline" }
        var parts: [String] = []
        if store.isOn {
            let mode: String? = store.value("airConditionerMode", "airConditionerMode")
            let verb = mode.flatMap { modeVerbs[$0] } ?? "On"
            if let sp = store.setpoint { parts.append("\(verb) to \(formatTemp(sp))°") } else { parts.append(verb) }
        } else {
            parts.append("Off")
        }
        if let t = store.roomTemp { parts.append("Room \(formatTemp(t))°") }
        // Humidity only while off, so the line never truncates.
        if !store.isOn, let h = store.humidity { parts.append("\(Int(h))% humidity") }
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(store.isOn ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.secondary.opacity(0.18)))
                Image(systemName: "air.conditioner.horizontal.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(store.isOn ? Color.white : Color.secondary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(store.deviceName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    if store.online == false {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                    }
                    Text(statusLine)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 4)
            if store.busy { ProgressView().controlSize(.mini) }
            if store.hasToken {
                CircleIconButton(icon: store.sleepTimer != nil || store.schedules.contains(where: \.enabled) ? "clock.fill" : "clock",
                                 active: showSchedules, help: "Schedules and timer") {
                    showSchedules.toggle(); showSettings = false
                }
            }
            CircleIconButton(icon: "gearshape.fill", active: showSettings, help: "Settings") {
                showSettings.toggle(); showSchedules = false
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        heroCard
        Group {
            climateCard
            if store.hasAirflow { AirflowCard() }
        }
        .disabled(!store.isOn)
        .opacity(store.isOn ? 1 : 0.5)
        .saturation(store.isOn ? 1 : 0)
        if !store.availableSwitches.isEmpty { switchesCard }
    }

    private var heroCard: some View {
        Card {
            HStack(spacing: 12) {
                Button(action: store.togglePower) {
                    ZStack {
                        Circle()
                            .fill(store.isOn ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.secondary.opacity(0.18)))
                        Image(systemName: "power")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(store.isOn ? Color.white : Color.primary)
                    }
                    .frame(width: 52, height: 52)
                    .shadow(color: store.isOn ? Color.accentColor.opacity(0.35) : .clear, radius: 8, y: 3)
                }
                .buttonStyle(PressableStyle())
                .keyboardShortcut(.space, modifiers: [])
                .help(store.isOn ? "Turn off" : "Turn on")
                .accessibilityLabel(store.isOn ? "Turn off" : "Turn on")

                Spacer(minLength: 0)

                if store.has("thermostatCoolingSetpoint") {
                    let canDown = (store.setpoint ?? 0) > store.setpointRange.lowerBound
                    let canUp = (store.setpoint ?? 0) < store.setpointRange.upperBound
                    StepCircle(icon: "minus", enabled: store.isOn && canDown) { store.nudgeSetpoint(-1) }
                    VStack(spacing: -2) {
                        Text(store.setpoint.map { formatTemp($0) } ?? "--")
                            .font(.system(size: 44, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.snappy, value: store.setpoint)
                            .overlay(alignment: .topTrailing) {
                                Text("°").font(.system(size: 22, weight: .light, design: .rounded)).offset(x: 12, y: 4)
                            }
                        Text("TARGET").font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 70)
                    .opacity(store.isOn ? 1 : 0.5)
                    StepCircle(icon: "plus", enabled: store.isOn && canUp) { store.nudgeSetpoint(1) }
                }
            }
        }
    }

    private var climateCard: some View {
        Card(spacing: 12) {
            let modes: [String] = store.has("airConditionerMode") ? (store.value("airConditionerMode", "supportedAcModes") ?? []) : []
            if !modes.isEmpty {
                let current: String? = store.value("airConditionerMode", "airConditionerMode")
                HStack(spacing: 6) {
                    ForEach(modes, id: \.self) { m in
                        ModeTile(icon: modeIcons[m] ?? "circle", title: pretty(m), selected: m == current) {
                            store.send("airConditionerMode", "setAirConditionerMode", [m], optimistic: ("airConditionerMode", m))
                        }
                    }
                }
            }
            segmentedRow("Fan speed", cap: "airConditionerFanMode", current: "fanMode",
                         list: "supportedAcFanModes", command: "setFanMode")
            segmentedRow("Swing", cap: "fanOscillationMode", current: "fanOscillationMode",
                         list: "supportedFanOscillationModes", command: "setFanOscillationMode")
            segmentedRow("Special mode", cap: "custom.airConditionerOptionalMode", current: "acOptionalMode",
                         list: "supportedAcOptionalMode", command: "setAcOptionalMode")
        }
    }

    @ViewBuilder
    private func segmentedRow(_ title: String, cap: String, current: String, list: String, command: String) -> some View {
        if store.has(cap), let options: [String] = store.value(cap, list), !options.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                SectionLabel(title)
                SegmentedControl(options: options, selected: store.value(cap, current), label: pretty) { v in
                    store.send(cap, command, [v], optimistic: (current, v))
                }
            }
        }
    }

    private var switchesCard: some View {
        Card(spacing: 0) {
            ForEach(Array(store.availableSwitches.enumerated()), id: \.element.id) { i, sw in
                if i > 0 { Divider().padding(.leading, 34) }
                HStack(spacing: 10) {
                    Image(systemName: sw.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(store.isSwitchOn(sw) ? Color.accentColor : Color.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(sw.name).font(.system(size: 13))
                    Spacer()
                    MiniSwitch(isOn: store.isSwitchOn(sw)) { store.toggle(sw) }
                        .accessibilityLabel(sw.name)
                }
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - Airflow

private struct AirflowCard: View {
    @EnvironmentObject var store: ACStore
    @AppStorage("airflowExpanded") private var expanded = false

    private func summary(_ a: ACStore.Axis) -> String {
        store.airflowSwinging(a) ? "Swing" : (store.airflowStep(a).map { "Angle \($0)" } ?? "–")
    }

    var body: some View {
        Card(spacing: 10) {
            Button { withAnimation(.snappy(duration: 0.25)) { expanded.toggle() } } label: {
                HStack {
                    SectionLabel("Airflow")
                    Spacer()
                    if !expanded {
                        Text("↕ \(summary(.vertical))   ↔ \(summary(.horizontal))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Hide airflow controls" : "Show airflow controls")

            if expanded {
                axisRow(.vertical, title: "Up/Down", start: "arrow.up", end: "arrow.down")
                axisRow(.horizontal, title: "Left/Right", start: "arrow.left", end: "arrow.right")
                if store.airflowSwinging(.horizontal), store.swingRanges.count > 1 {
                    HStack(spacing: 8) {
                        Text("Range").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
                        SegmentedControl(options: store.swingRanges, selected: store.swingRange, label: pretty) {
                            store.setSwingRange($0)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func axisRow(_ axis: ACStore.Axis, title: String, start: String, end: String) -> some View {
        let steps = store.airflowSteps(axis)
        if !steps.isEmpty || store.airflowCanSwing(axis) {
            let swinging = store.airflowSwinging(axis)
            HStack(spacing: 8) {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
                if store.airflowCanSwing(axis) {
                    PillToggle(title: "Swing", icon: "wave.3.right", isOn: swinging) { store.setAirflowSwing(axis) }
                }
                if !steps.isEmpty {
                    StepSlider(steps: steps, selected: store.airflowStep(axis), active: !swinging,
                               startIcon: start, endIcon: end, label: "\(title) angle") { step in
                        store.setAirflowAngle(axis, step: step)
                    }
                }
            }
        }
    }
}

// MARK: - Building blocks

/// A rounded, softly filled container like a Control Center module.
struct Card<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
    }
}

/// Mode button: icon in a circle with a label underneath.
private struct ModeTile: View {
    let icon: String
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(selected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .frame(width: 38, height: 38)
                Text(title).font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A segmented control with a sliding selection, sized to fill the row.
struct SegmentedControl: View {
    let options: [String]
    let selected: String?
    var label: (String) -> String = { $0 }
    let onSelect: (String) -> Void
    @Namespace private var ns
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                let isSel = o == selected
                Button { onSelect(o) } label: {
                    Text(label(o))
                        .font(.system(size: 11.5, weight: isSel ? .semibold : .regular))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(isSel ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background {
                            if isSel {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(scheme == .dark ? Color.white.opacity(0.2) : Color.white)
                                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "sel", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSel ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(.snappy(duration: 0.22), value: selected)
    }
}

/// Small on/off switch drawn in SwiftUI.
struct MiniSwitch: View {
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.15)))
                .frame(width: 32, height: 19)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white).shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                        .frame(width: 15, height: 15).padding(2)
                }
                .animation(.snappy(duration: 0.2), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// Compact capsule toggle with an icon (e.g. Swing).
private struct PillToggle: View {
    let title: String
    let icon: String
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(isOn ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)),
                            in: Capsule())
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct StepCircle: View {
    let icon: String
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(icon == "plus" ? "Warmer" : "Cooler")
    }
}

struct CircleIconButton: View {
    let icon: String
    var active = false
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.secondary)
                .frame(width: 26, height: 26)
                .background(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.08)), in: Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct ErrorBanner: View {
    let text: String
    var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) }
              icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            .font(.system(size: 11.5))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Slight shrink on press, like system controls.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
