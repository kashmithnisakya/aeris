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
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Refresh")
            Button { showSettings.toggle() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Settings")
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
            Button { store.setLaunchAtLogin(!store.launchAtLogin) } label: {
                Label("Launch at login", systemImage: store.launchAtLogin ? "checkmark.square.fill" : "square")
            }
            .buttonStyle(.plain).font(.caption)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
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
    @ObservedObject private var auth = AuthManager.shared
    var done: () -> Void
    @State private var token = ""
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var showClient = false
    @State private var showToken = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SmartThings account").font(.subheadline.weight(.semibold))
            account

            if let err = auth.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !auth.hasBuiltInClient { ownApp }
            advancedToken

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
                    Spacer()
                    Button("Done", action: done).keyboardShortcut(.defaultAction)
                }
            }
        }
        .task { if store.hasToken && store.devices.isEmpty { await store.loadDevices() } }
    }

    @ViewBuilder private var account: some View {
        if auth.signingIn {
            HStack {
                ProgressView().controlSize(.small)
                Text("Finish signing in in your browser…").font(.callout)
                Spacer()
                Button("Cancel") { auth.cancelSignIn() }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
        } else if let c = auth.credentials, c.kind == .oauth {
            HStack {
                Label("Signed in — access renews automatically", systemImage: "checkmark.seal.fill")
                    .font(.callout).foregroundStyle(.green)
                Spacer()
                Button("Sign out") { store.signOut() }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
        } else {
            if auth.credentials?.kind == .pat {
                Text("Using a personal access token. SmartThings makes these expire after 24 hours.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { auth.beginSignIn() } label: {
                Label("Sign in with SmartThings", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(auth.client == nil ? Color.secondary.opacity(0.3) : Color.accentColor,
                                in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(auth.client == nil)
            if auth.client == nil {
                Text("Add your SmartThings app below to enable sign-in.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var ownApp: some View {
        DisclosureGroup(isExpanded: $showClient) {
            VStack(alignment: .leading, spacing: 6) {
                if let c = auth.customClient {
                    HStack {
                        Text("Client ID \(c.id.prefix(8))… saved").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove") { auth.removeCustomClient() }.buttonStyle(.plain).font(.caption)
                    }
                }
                TextField("Client ID", text: $clientID).textFieldStyle(.roundedBorder)
                SecureField("Client Secret", text: $clientSecret).textFieldStyle(.roundedBorder)
                HStack {
                    Link("How to create one", destination: URL(string: "https://github.com/kashmithnisakya/aeris#use-your-own-smartthings-app")!)
                        .font(.caption)
                    Spacer()
                    Button("Save") {
                        auth.saveCustomClient(id: clientID, secret: clientSecret)
                        clientID = ""; clientSecret = ""
                    }
                    .disabled(clientID.isEmpty || clientSecret.isEmpty)
                }
            }
            .padding(.top, 4)
        } label: {
            Text("Your SmartThings app").font(.caption)
        }
        .onAppear { if auth.customClient == nil { showClient = true } }
    }

    private var advancedToken: some View {
        DisclosureGroup(isExpanded: $showToken) {
            VStack(alignment: .leading, spacing: 6) {
                SecureField("Paste personal access token", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveToken)
                HStack {
                    Link("Get a token", destination: URL(string: "https://account.smartthings.com/tokens")!).font(.caption)
                    Spacer()
                    Button("Use token", action: saveToken).disabled(token.isEmpty)
                }
                Text("Expires after 24 hours. Tick the Devices permissions when creating it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        } label: {
            Text("Advanced: personal access token").font(.caption)
        }
    }

    private func saveToken() {
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
