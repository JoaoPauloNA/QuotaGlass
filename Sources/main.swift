import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var hosting: NSHostingController<QuotaSurface>!
    private var store = AccountStore()
    private var desktopPanel: DesktopQuotaPanel?
    private var timer: Timer?
    private var panelHeight: CGFloat = 340
    private var chromeHeight: CGFloat = 24
    private var screenObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "Cotas das assinaturas")
            button.target = self; button.action = #selector(toggle)
            button.toolTip = "Cotas das suas assinaturas"
        }
        let content = QuotaView(store: store, close: { [weak self] in self?.closePanel() },
                    onHeight: { [weak self] height in
                        DispatchQueue.main.async { self?.resizePanel(height) }
                    })
        hosting = NSHostingController(rootView: QuotaSurface(content: content, store: store))
        hosting.sizingOptions = []
        if #available(macOS 13.3, *) { hosting.safeAreaRegions = [] }
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 386, height: panelHeight)
        popover.behavior = .transient
        popover.animates = true
        // Inherit the system appearance, including changes while the app is open.
        popover.appearance = nil
        popover.delegate = self
        for name in [NSApplication.didChangeScreenParametersNotification, NSWindow.didChangeScreenNotification] {
            screenObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateScreenLimit() }
            })
        }
        store.onChange = { [weak self] in self?.updateStatus() }
        desktopPanel = DesktopQuotaPanel(store: store) { [weak self] in
            self?.store.showingSettings = false
            self?.showPanel()
        }
        store.repositionDesktopPanel = { [weak self] in
            self?.desktopPanel?.reposition()
            self?.closePanel()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.store.checkWidgetUsage()
                if self?.popover.isShown == true || self?.store.widgetInUse == true || self?.store.desktopPanelVisible == true {
                    self?.store.refresh()
                }
            }
        }
        store.start()
        store.checkWidgetUsage()
        if !CommandLine.arguments.contains("--background") { showPanel() }
    }

    @objc private func toggle() {
        if popover.isShown { closePanel() } else { showPanel() }
    }

    private func showPanel() {
        guard !popover.isShown, let button = item.button else { return }
        updateScreenLimit()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        store.refreshIfNeeded()
    }

    private func closePanel() { popover.performClose(nil) }

    private func resizePanel(_ height: CGFloat) {
        let next = ceil(height)
        guard next > 100, abs(next - panelHeight) > 1 else { return }
        panelHeight = next
        popover.contentSize = NSSize(width: 386, height: min(next, store.maximumPanelHeight))
    }

    private func updateScreenLimit() {
        guard let screen = item.button?.window?.screen ?? NSScreen.main else { return }
        store.maximumPanelHeight = PanelSizing.maximumContentHeight(screenHeight: screen.frame.height,
            availableHeight: screen.visibleFrame.height, chromeHeight: chromeHeight)
        popover.contentSize = NSSize(width: 386, height: min(panelHeight, store.maximumPanelHeight))
    }

    func popoverDidShow(_ notification: Notification) {
        hosting.view.window?.title = "Cotas das assinaturas"
        if let window = hosting.view.window {
            chromeHeight = max(0, window.frame.height - popover.contentSize.height)
            updateScreenLimit()
        }
    }

    private func updateStatus() {
        let available = store.results.flatMap(\.accounts).filter { !$0.hidden && $0.status == "ready" }.count
        item.button?.toolTip = available > 0 ? "Cotas · \(available) contas disponíveis" : "Cotas · clique para consultar"
        if store.state == .ready && store.wantsPanelAfterLogin {
            store.wantsPanelAfterLogin = false
            showPanel()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "quotaglass" && $0.host == "panel" }) else { return }
        store.showingSettings = false
        showPanel()
    }
    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        desktopPanel?.stop()
        timer?.invalidate()
        screenObservers.forEach(NotificationCenter.default.removeObserver)
    }
}

@main enum QuotaGlassApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
