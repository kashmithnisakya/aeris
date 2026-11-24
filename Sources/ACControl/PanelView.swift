import SwiftUI

private let labels: [String: String] = [
    "cool": "Cool", "heat": "Heat", "dry": "Dry", "wind": "Fan", "fan": "Fan", "auto": "Auto", "aIComfort": "AI",
    "low": "Low", "medium": "Med", "high": "High", "turbo": "Turbo",
    "fixed": "Off", "all": "All", "vertical": "Up/Down", "horizontal": "Left/Right",
    "off": "Off", "sleep": "Sleep", "quiet": "Quiet", "smart": "Smart", "speed": "Speed", "windFree": "WindFree",
    "windFreeSleep": "WF Sleep", "longWind": "Long wind", "comfort": "Comfort", "twoStep": "2-step",
    "energySaving": "Eco",
]

private func pretty(_ v: String) -> String {
    if let l = labels[v] { return l }
    let spaced = v.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    return spaced.prefix(1).uppercased() + spaced.dropFirst()
}

struct PanelView: View {
    @EnvironmentObject var store: ACStore
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !store.hasToken || showSettings {
                SettingsView(done: { showSettings = false })
            } else {
                controls
            }
            if let err = store.error {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 300)
        .task { await store.refresh() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.online == true ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
                .help(store.online == true ? "Online" : "Offline or unknown")
            Text(store.deviceName).font(.headline).lineLimit(1)
            Spacer()
            if store.busy { ProgressView().controlSize(.small) }
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Refresh")
            Button { showSettings.toggle() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).help("Settings")
        }
    }

    @ViewBuilder private var controls: some View {
        // Power
        Button(action: store.togglePower) {
            HStack {
                Image(systemName: "power")
                Text(store.isOn ? "On" : "Off").fontWeight(.semibold)
                Spacer()
                if let t = store.roomTemp { Text("Room \(formatTemp(t))°").foregroundStyle(.secondary) }
                if let h = store.humidity { Text("\(Int(h))%").foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(store.isOn ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(store.isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])

        Group {
            if store.has("thermostatCoolingSetpoint") {
                HStack {
                    stepButton("minus") { store.nudgeSetpoint(-1) }
                    Spacer()
                    VStack(spacing: 0) {
                        Text(store.setpoint.map { "\(formatTemp($0))°" } ?? "--")
                            .font(.system(size: 40, weight: .light)).monospacedDigit()
                        Text("Target").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    stepButton("plus") { store.nudgeSetpoint(1) }
                }
                .padding(.horizontal, 8)
            }

            chipRow("Mode", cap: "airConditionerMode", current: "airConditionerMode",
                    list: "supportedAcModes", command: "setAirConditionerMode")
            chipRow("Fan", cap: "airConditionerFanMode", current: "fanMode",
                    list: "supportedAcFanModes", command: "setFanMode")
            chipRow("Swing", cap: "fanOscillationMode", current: "fanOscillationMode",
                    list: "supportedFanOscillationModes", command: "setFanOscillationMode")
            chipRow("Special", cap: "custom.airConditionerOptionalMode", current: "acOptionalMode",
                    list: "supportedAcOptionalMode", command: "setAcOptionalMode")
        }
        .disabled(!store.isOn)
        .opacity(store.isOn ? 1 : 0.45)

        Divider()
        HStack {
            Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin },
                                                    set: { store.setLaunchAtLogin($0) }))
                .toggleStyle(.checkbox).font(.caption)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless).font(.caption)
        }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3).frame(width: 36, height: 36)
                .background(Color.secondary.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func chipRow(_ title: String, cap: String, current: String, list: String, command: String) -> some View {
        if store.has(cap), let options: [String] = store.value(cap, list), !options.isEmpty {
            let selected: String? = store.value(cap, current)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                FlowLayout(spacing: 5) {
                    ForEach(options, id: \.self) { opt in
                        Button(pretty(opt)) {
                            store.send(cap, command, [opt], optimistic: (current, opt))
                        }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(opt == selected ? Color.accentColor : Color.secondary.opacity(0.15),
                                    in: Capsule())
                        .foregroundStyle(opt == selected ? Color.white : Color.primary)
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: ACStore
    var done: () -> Void
    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SmartThings token").font(.subheadline.weight(.semibold))
            SecureField(store.hasToken ? "Saved in Keychain — paste to replace" : "Paste personal access token",
                        text: $token)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Link("Get a token", destination: URL(string: "https://account.smartthings.com/tokens")!)
                    .font(.caption)
                Spacer()
                Button("Save", action: save).disabled(token.isEmpty)
            }
            Text("Tick the Devices permissions (list, see, control) when creating it.")
                .font(.caption).foregroundStyle(.secondary)

            if store.hasToken {
                Divider()
                Text("Device").font(.subheadline.weight(.semibold))
                if store.devices.isEmpty {
                    Button("Load devices") { Task { await store.loadDevices() } }
                } else {
                    Picker("Device", selection: Binding(
                        get: { store.deviceId ?? "" },
                        set: { id in if let d = store.devices.first(where: { $0.id == id }) { store.selectDevice(d) } }
                    )) {
                        ForEach(store.devices) { d in Text(d.label + (d.isAC ? " ❄︎" : "")).tag(d.id) }
                    }
                    .labelsHidden()
                }
                HStack {
                    Button("Remove token", role: .destructive) { store.signOut() }
                        .buttonStyle(.borderless).font(.caption)
                    Spacer()
                    Button("Done", action: done).keyboardShortcut(.defaultAction)
                }
            }
        }
        .task { if store.hasToken && store.devices.isEmpty { await store.loadDevices() } }
    }

    private func save() {
        store.saveToken(token)
        token = ""
        done()
    }
}

/// Simple wrapping layout for the option chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
