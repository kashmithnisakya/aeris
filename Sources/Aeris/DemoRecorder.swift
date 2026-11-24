#if DEBUG
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders README media (screenshots + animated GIF frames) from fake device state.
/// Run via `scripts/make-demo.sh`; never touches the network. Debug builds only.
@MainActor
enum DemoRecorder {
    static func startIfRequested() {
        guard let out = ProcessInfo.processInfo.environment["AC_DEMO_OUT"] else { return }
        Task { @MainActor in
            await record(to: URL(fileURLWithPath: out, isDirectory: true))
            exit(0)
        }
    }

    private static func demoStore() -> ACStore {
        let s = ACStore()
        s.demoMode = true
        s.hasToken = true
        s.deviceId = "demo"
        s.deviceName = "Living room AC"
        s.online = true
        s.error = nil
        s.status = [
            "switch": ["switch": "off"],
            "temperatureMeasurement": ["temperature": NSNumber(value: 29)],
            "relativeHumidityMeasurement": ["humidity": NSNumber(value: 62)],
            "thermostatCoolingSetpoint": ["coolingSetpoint": NSNumber(value: 24)],
            "custom.thermostatSetpointControl": ["minimumSetpoint": NSNumber(value: 16), "maximumSetpoint": NSNumber(value: 30)],
            "airConditionerMode": ["airConditionerMode": "cool", "supportedAcModes": ["cool", "dry", "wind", "auto", "heat"]],
            "airConditionerFanMode": ["fanMode": "auto", "supportedAcFanModes": ["auto", "low", "medium", "high", "turbo"]],
            "fanOscillationMode": ["fanOscillationMode": "fixed", "supportedFanOscillationModes": ["fixed", "all", "vertical", "horizontal"]],
            "custom.airConditionerOptionalMode": ["acOptionalMode": "off", "supportedAcOptionalMode": ["off", "sleep", "quiet", "speed", "windFree"]],
        ]
        return s
    }

    struct Frame { let open: Bool; let caption: String; let seconds: Double; let change: (ACStore) -> Void }

    static func record(to dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = demoStore()
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Static screenshots of the panel (AC on), light and dark.
        store.status["switch"]?["switch"] = "on"
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .dark ? "panel-dark.png" : "panel-light.png"
            let view = PanelView().environmentObject(store)
                .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.97))
                .environment(\.colorScheme, scheme)
            writePNG(render(view, scale: 2), to: dir.appendingPathComponent(name))
        }
        store.status["switch"]?["switch"] = "off"

        let set: (String, String, Any) -> (ACStore) -> Void = { cap, attr, v in { $0.status[cap]?[attr] = v } }
        let frames: [Frame] = [
            Frame(open: false, caption: "Aeris lives in your menu bar", seconds: 1.6) { _ in },
            Frame(open: true, caption: "Click the icon to open the panel", seconds: 1.4) { _ in },
            Frame(open: true, caption: "One click to turn it on", seconds: 1.6, change: set("switch", "switch", "on")),
            Frame(open: true, caption: "Set the temperature", seconds: 0.6, change: set("thermostatCoolingSetpoint", "coolingSetpoint", NSNumber(value: 25))),
            Frame(open: true, caption: "Set the temperature", seconds: 1.2, change: set("thermostatCoolingSetpoint", "coolingSetpoint", NSNumber(value: 26))),
            Frame(open: true, caption: "Pick a mode", seconds: 1.3, change: set("airConditionerMode", "airConditionerMode", "dry")),
            Frame(open: true, caption: "Change fan speed", seconds: 1.3, change: set("airConditionerFanMode", "fanMode", "high")),
            Frame(open: true, caption: "Swing and special modes", seconds: 1.1, change: set("fanOscillationMode", "fanOscillationMode", "all")),
            Frame(open: true, caption: "Swing and special modes", seconds: 1.3, change: set("custom.airConditionerOptionalMode", "acOptionalMode", "windFree")),
            Frame(open: false, caption: "The menu bar shows the target while it's on", seconds: 2.0) { _ in },
            Frame(open: true, caption: "One click to turn it off", seconds: 1.8, change: set("switch", "switch", "off")),
        ]

        var images: [(CGImage, Double)] = []
        for (i, f) in frames.enumerated() {
            f.change(store)
            let img = render(Scene(store: store, open: f.open, caption: f.caption), scale: 1.5)
            writePNG(img, to: dir.appendingPathComponent(String(format: "frame-%02d.png", i)))
            images.append((img, f.seconds))
        }
        writeGIF(images, to: dir.appendingPathComponent("demo.gif"))
        // Durations for ffmpeg's concat demuxer (MP4).
        var concat = ""
        for (i, f) in frames.enumerated() { concat += String(format: "file 'frame-%02d.png'\nduration %.2f\n", i, f.seconds) }
        concat += String(format: "file 'frame-%02d.png'\n", frames.count - 1)
        try? concat.write(to: dir.appendingPathComponent("frames.txt"), atomically: true, encoding: .utf8)
    }

    /// A fake desktop: wallpaper, menu bar with our item, and the open panel under it.
    struct Scene: View {
        @ObservedObject var store: ACStore
        let open: Bool
        let caption: String

        var body: some View {
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.42, green: 0.45, blue: 0.75), Color(red: 0.16, green: 0.42, blue: 0.70)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 0) {
                    menuBar
                    HStack(alignment: .top) {
                        Spacer()
                        if open {
                            PanelView().environmentObject(store)
                                .background(Color(white: 0.14).opacity(0.97))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12)))
                                .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
                                .padding(.trailing, 150)
                                .padding(.top, 6)
                        }
                    }
                    Spacer()
                }
                VStack {
                    Spacer()
                    Text(caption)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(Color.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, 22)
                }
            }
            .frame(width: 760, height: 640)
            .environment(\.colorScheme, .dark)
        }

        private var menuBar: some View {
            HStack(spacing: 18) {
                Image(systemName: "apple.logo")
                Text("Finder").fontWeight(.bold)
                Text("File"); Text("Edit"); Text("View")
                Spacer()
                MenuBarLabel().environmentObject(store)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(open ? Color.white.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 5))
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text("Tue 24 Nov  1:33 PM")
            }
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(Color.black.opacity(0.35))
        }
    }

    private static func render<V: View>(_ view: V, scale: CGFloat) -> CGImage {
        let r = ImageRenderer(content: view)
        r.scale = scale
        return r.cgImage!
    }

    private static func writePNG(_ img: CGImage, to url: URL) {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(d, img, nil)
        CGImageDestinationFinalize(d)
    }

    private static func writeGIF(_ frames: [(CGImage, Double)], to url: URL) {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return }
        CGImageDestinationSetProperties(d, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (img, secs) in frames {
            CGImageDestinationAddImage(d, img, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: secs]] as CFDictionary)
        }
        CGImageDestinationFinalize(d)
    }
}
#endif
