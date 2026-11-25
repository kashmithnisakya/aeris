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
        VStack(alignment: .leading, spacing: 10) {
            if store.hasToken { ScreenHeader(title: "Settings", done: done) }

            Card(spacing: 10) {
                SectionLabel("SmartThings account")
                account
                if let err = auth.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if store.hasToken {
                Card(spacing: 0) {
                    SectionLabel("Air conditioner").padding(.bottom, 4)
                    if store.devices.isEmpty {
                        Text("Looking for devices…").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 6)
                    }
                    let acs = store.devices.filter(\.isAC)
                    ForEach(Array((acs.isEmpty ? store.devices : acs).enumerated()), id: \.element.id) { i, d in
                        if i > 0 { Divider().padding(.leading, 34) }
                        Button { store.selectDevice(d) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "air.conditioner.horizontal")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(d.id == store.deviceId ? Color.white : Color.secondary)
                                    .frame(width: 24, height: 24)
                                    .background(d.id == store.deviceId ? AnyShapeStyle(Color.accentColor.gradient)
                                                                       : AnyShapeStyle(Color.secondary.opacity(0.12)),
                                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                Text(d.label).font(.system(size: 13)).lineLimit(1)
                                Spacer()
                                if d.id == store.deviceId {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(d.id == store.deviceId ? .isSelected : [])
                    }
                }
            }

            Card(spacing: 0) {
                SettingsRow(icon: "power", title: "Launch at login") {
                    MiniSwitch(isOn: store.launchAtLogin) { store.setLaunchAtLogin(!store.launchAtLogin) }
                        .accessibilityLabel("Launch at login")
                        .disabled(!ACStore.canLaunchAtLogin)
                        .opacity(ACStore.canLaunchAtLogin ? 1 : 0.4)
                        .help(ACStore.canLaunchAtLogin ? "" : "Only available in the installed app")
                }
                Divider().padding(.leading, 34)
                SettingsRow(icon: "info.circle", title: "Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Divider().padding(.leading, 34)
                SettingsRow(icon: "xmark.circle", title: "Quit Aeris") {
                    Button("Quit") { NSApp.terminate(nil) }
                        .buttonStyle(SecondaryButtonStyle()).keyboardShortcut("q")
                }
            }

            Card(spacing: 0) {
                ExpandRow(title: "Personal access token", subtitle: "Expires every 24 hours", expanded: $showToken) {
                    VStack(alignment: .leading, spacing: 6) {
                        SecureField("Paste personal access token", text: $token)
                            .textFieldStyle(.roundedBorder).onSubmit(saveToken)
                        HStack {
                            Link("Get a token", destination: URL(string: "https://account.smartthings.com/tokens")!).font(.caption)
                            Spacer()
                            Button("Use token", action: saveToken).buttonStyle(SecondaryButtonStyle()).disabled(token.isEmpty)
                        }
                    }
                }
                if !auth.hasBuiltInClient {
                    Divider()
                    ExpandRow(title: "Your own SmartThings app", subtitle: "Needs a developer plan", expanded: $showClient) {
                        VStack(alignment: .leading, spacing: 6) {
                            if let c = auth.customClient {
                                HStack {
                                    Text("Client ID \(c.id.prefix(8))… saved").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Remove") { auth.removeCustomClient() }.buttonStyle(SecondaryButtonStyle())
                                }
                            }
                            TextField("Client ID", text: $clientID).textFieldStyle(.roundedBorder)
                            SecureField("Client Secret", text: $clientSecret).textFieldStyle(.roundedBorder)
                            HStack {
                                Link("How to create one", destination: URL(string: "https://github.com/kashmithnisakya/aeris#set-up")!)
                                    .font(.caption)
                                Spacer()
                                Button("Save") {
                                    auth.saveCustomClient(id: clientID, secret: clientSecret)
                                    clientID = ""; clientSecret = ""
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(clientID.isEmpty || clientSecret.isEmpty)
                            }
                        }
                    }
                }
            }
        }
        .task { if store.hasToken && store.devices.isEmpty { await store.loadDevices() } }
    }

    @ViewBuilder private var account: some View {
        if auth.signingIn {
            HStack(spacing: 10) {
                Image(systemName: "safari").font(.system(size: 16)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Finish signing in in your browser").font(.system(size: 13, weight: .medium))
                    Text("Aeris continues automatically.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { auth.cancelSignIn() }.buttonStyle(SecondaryButtonStyle())
            }
        } else if let c = auth.credentials, c.kind != .pat {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 18)).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Signed in").font(.system(size: 13, weight: .medium))
                    Text("Access renews automatically").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sign out") { store.signOut() }.buttonStyle(SecondaryButtonStyle())
            }
        } else {
            if auth.credentials?.kind == .pat {
                Text("Using a personal access token, which SmartThings expires after 24 hours. Sign in so Aeris can renew access by itself.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Sign in once. Aeris keeps access renewed for you.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Button { auth.beginSignIn() } label: {
                Label("Sign in with SmartThings", systemImage: "person.crop.circle.badge.checkmark")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(auth.client == nil && !cliInstalled)
            if auth.client == nil && !cliInstalled { installCLI }
        }
    }

    private var cliInstalled: Bool { SmartThingsCLI.isInstalled }

    /// Shown when sign-in needs the SmartThings CLI and it isn't installed.
    private var installCLI: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sign-in uses SmartThings' official command-line tool. Install it once in Terminal:")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(Self.installCommand)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled).lineLimit(2)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.installCommand, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.plain).help("Copy")
            }
            .padding(8)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Button("I've installed it") { auth.objectWillChange.send() }.buttonStyle(SecondaryButtonStyle())
        }
    }

    static let installCommand = "brew install smartthingscommunity/smartthings/smartthings"

    private func saveToken() {
        store.saveToken(token)
        token = ""
        done()
    }
}

// MARK: - Shared screen pieces

/// Title row for a secondary screen (Settings, Schedules) with a Done button.
struct ScreenHeader: View {
    let title: String
    let done: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button(action: done) {
                Label("Back", systemImage: "chevron.left").labelStyle(.iconOnly)
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut(.cancelAction)
            .help("Back")
            .accessibilityLabel("Back")
            Text(title).font(.system(size: 15, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

struct SettingsRow<Accessory: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var accessory: Accessory
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title).font(.system(size: 13))
            Spacer()
            accessory
        }
        .padding(.vertical, 6)
    }
}

/// A row that expands to show more options (drawn in SwiftUI, unlike DisclosureGroup).
struct ExpandRow<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @Binding var expanded: Bool
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy(duration: 0.25)) { expanded.toggle() } } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 12.5))
                        if let subtitle { Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded { content }
        }
        .padding(.vertical, 6)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(enabled ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.secondary.opacity(0.3)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.08), in: Capsule())
            .foregroundStyle(enabled ? Color.primary : Color.secondary)
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
