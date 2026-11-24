import SwiftUI

/// Aeris is a pure menu bar app: no SwiftUI `App`/`Scene`, so macOS never opens a stray window
/// when the app activates to show its panel.
@main
enum AerisMain {
    @MainActor private static let delegate = AppDelegate()

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        #if DEBUG
        DemoRecorder.startIfRequested()
        SignInTestHook.startIfRequested()
        #endif
        app.run()
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

    /// Clicking the app in Finder/Spotlight while it runs opens the panel instead of a window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusPanel?.openFromReopen()
        return false
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
