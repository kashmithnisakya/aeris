import AppKit
import Combine
import SwiftUI

/// Aeris's own menu bar item and drop-down panel.
///
/// SwiftUI's `MenuBarExtra(.window)` never shrinks its window once it has grown, so shorter
/// screens (Schedules, Settings) floated in leftover space. This controller hosts the same SwiftUI
/// content in a borderless panel that is resized to the content's exact height on every change and
/// stays pinned under the status item.
@MainActor
final class StatusPanelController: NSObject {
    private let store: ACStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: DropdownPanel
    private var hostingView: NSHostingView<AnyView>!
    private var contentSize = CGSize(width: 344, height: 400)
    private var clickMonitor: Any?
    private var watch: AnyCancellable?

    init(store: ACStore) {
        self.store = store
        panel = DropdownPanel()
        super.init()
        panel.onCancel = { [weak self] in self?.closePanel() }

        // Content: the existing SwiftUI panel, reporting its size so the window can follow it.
        let root = PanelView()
            .environmentObject(store)
            .background(SizeReader { [weak self] size in self?.contentDidResize(size) })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        hostingView = NSHostingView(rootView: AnyView(root))
        // Frame-based layout: the hosting view always fills the panel, and the panel's height is
        // set from the measured SwiftUI size. (Its own intrinsic size went stale when content grew,
        // which clipped the top of the dashboard after returning from Schedules.)
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        panel.contentView = effect
        hostingView.frame = effect.bounds
        effect.addSubview(hostingView)

        // Status item: AC symbol, plus the target temperature while the AC is on.
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel("Aeris")
        }
        updateStatusItem()
        watch = store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
    }

    // MARK: Status item

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let on = store.isOn
        let symbol = on ? "air.conditioner.horizontal.fill" : "air.conditioner.horizontal"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Aeris")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        image?.isTemplate = true
        button.image = image
        let title = on ? store.setpoint.map { " \(formatTemp($0))°" } ?? "" : ""
        if button.title != title { button.title = title }
        button.toolTip = on ? "Aeris: AC on" : "Aeris: AC off"
    }

    // MARK: Panel

    @objc private func togglePanel() {
        panel.isVisible ? closePanel() : openPanel()
    }

    private func openPanel() {
        position()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        Task { await store.refresh() }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
    }

    func closePanel() {
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    private func contentDidResize(_ size: CGSize) {
        guard size.height > 0, abs(size.height - contentSize.height) > 0.5 || abs(size.width - contentSize.width) > 0.5 else { return }
        contentSize = size
        if panel.isVisible { position() }
    }

    /// Places the panel under the status item, top edge fixed, height = content height.
    private func position() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let width = max(contentSize.width, 1)
        let height = min(max(contentSize.height, 1), visible.height - 12)
        var x = buttonRect.midX - width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - width - 8)
        let top = buttonRect.minY - 6
        panel.setFrame(NSRect(x: x, y: top - height, width: width, height: height), display: true)
        if let effect = panel.contentView { hostingView.frame = effect.bounds }
    }
}

/// Borderless panel that can take keyboard focus (for text fields) without a title bar.
final class DropdownPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 344, height: 400),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow
    }
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc closes the panel when nothing inside handled it.
    override func cancelOperation(_ sender: Any?) { onCancel?() ?? orderOut(nil) }
}

/// Reports the SwiftUI content's size.
private struct SizeReader: View {
    let onChange: (CGSize) -> Void
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { onChange(geo.size) }
                .onChange(of: geo.size) { onChange($0) }
        }
    }
}
