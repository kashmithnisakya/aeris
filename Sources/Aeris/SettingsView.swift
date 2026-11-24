import AppKit
import SwiftUI

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

            Divider()
            Text("General").font(.subheadline.weight(.semibold))
            HStack {
                Text("Launch at login").font(.callout)
                Spacer()
                MiniSwitch(isOn: store.launchAtLogin) { store.setLaunchAtLogin(!store.launchAtLogin) }
                    .accessibilityLabel("Launch at login")
            }
            HStack {
                Text("Aeris \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit Aeris") { NSApp.terminate(nil) }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    .keyboardShortcut("q")
            }

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
                Image(systemName: "safari").foregroundStyle(Color.accentColor)
                Text("Finish signing in in your browser…").font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Cancel") { auth.cancelSignIn() }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
        } else if let c = auth.credentials, c.kind != .pat {
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
                    .background(auth.client == nil && !cliInstalled ? Color.secondary.opacity(0.3) : Color.accentColor,
                                in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(auth.client == nil && !cliInstalled)
            if auth.client == nil && !cliInstalled { installCLI }
        }
    }

    private var cliInstalled: Bool { SmartThingsCLI.isInstalled }

    /// Shown when sign-in needs the SmartThings CLI and it isn't installed.
    private var installCLI: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sign-in uses SmartThings' official command-line tool. Install it once in Terminal:")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(Self.installCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.installCommand, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.plain).help("Copy")
            }
            .padding(6)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            Button("I've installed it") { auth.objectWillChange.send() }
                .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
        }
    }

    static let installCommand = "brew install smartthingscommunity/smartthings/smartthings"

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
            Text("Advanced: your own SmartThings app (developer plan)").font(.caption)
        }
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
