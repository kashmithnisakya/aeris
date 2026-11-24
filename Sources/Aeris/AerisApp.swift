import SwiftUI

@main
struct AerisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        #if DEBUG
        DemoRecorder.startIfRequested()
        SignInTestHook.startIfRequested()
        #endif
    }

    // The menu bar item and panel are managed by StatusPanelController (see StatusPanel.swift).
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ACStore?
    private var statusPanel: StatusPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["AC_DEMO_OUT"] != nil { return }   // demo rendering only
        let store = ACStore()
        self.store = store
        statusPanel = StatusPanelController(store: store)
    }

    /// Receives aeris:// URLs from the sign-in callback page.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { @MainActor in await AuthManager.shared.handleCallback(url) }
        }
    }
}

/// What sits in the menu bar: an AC icon, plus the target temperature while it's on.
struct MenuBarLabel: View {
    @EnvironmentObject var store: ACStore

    var body: some View {
        if store.isOn, let sp = store.setpoint {
            HStack(spacing: 3) {
                Image(systemName: "air.conditioner.horizontal.fill")
                Text("\(formatTemp(sp))°")
            }
        } else {
            Image(systemName: "air.conditioner.horizontal")
        }
    }
}

func formatTemp(_ v: Double) -> String {
    v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
}
