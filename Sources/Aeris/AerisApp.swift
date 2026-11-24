import SwiftUI

@main
struct AerisApp: App {
    @StateObject private var store = ACStore()

    init() {
        #if DEBUG
        DemoRecorder.startIfRequested()
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(store)
        } label: {
            MenuBarLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)
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
