import AppKit
import Combine
import CoreGraphics
import SwiftUI

/// A desktop-level AppKit panel, independent of WidgetKit's opaque full-color surface.
@MainActor final class DesktopQuotaPanel: NSObject, NSWindowDelegate {
    private static let size = NSSize(width: 344, height: 164)
    private static let positionKey = "desktopQuotaPanelFrame"
    private let store: AccountStore
    private let appearance = DesktopQuotaAppearance()
    private let panel: DesktopQuotaWindow
    private var subscriptions: Set<AnyCancellable> = []
    private var workspaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var appearanceTimer: Timer?
    private var restoringPosition = false

    init(store: AccountStore, openDetails: @escaping () -> Void) {
        self.store = store
        panel = DesktopQuotaWindow(contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "Cotas na Mesa"
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.appearance = nil
        panel.delegate = self

        let content = DesktopQuotaView(store: store, appearance: appearance)
        let host = NSHostingView(rootView: content)
        if #available(macOS 13.3, *) { host.safeAreaRegions = [] }
        let container = DesktopQuotaContainer(frame: NSRect(origin: .zero, size: Self.size))
        container.openDetails = openDetails
        container.hidePanel = { [weak store] in store?.desktopPanelVisible = false }
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        panel.contentView = container

        restorePosition()
        updateAppearance()
        store.$desktopPanelVisible.removeDuplicates().sink { [weak self] visible in
            guard let self else { return }
            if visible { self.panel.orderFrontRegardless() }
            else { self.panel.orderOut(nil) }
        }.store(in: &subscriptions)
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateAppearance() }
            }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.restorePosition() }
            }
        // Finder can switch between a folder and the desktop without activating another app.
        appearanceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard self?.store.desktopPanelVisible == true else { return }
                self?.updateAppearance()
            }
        }
    }

    func reposition() {
        UserDefaults.standard.removeObject(forKey: Self.positionKey)
        restorePosition()
        store.desktopPanelVisible = true
    }

    private func restorePosition() {
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        restoringPosition = true
        defer { restoringPosition = false }
        if let saved = UserDefaults.standard.string(forKey: Self.positionKey) {
            let frame = NSRectFromString(saved)
            if frame.origin.x.isFinite, frame.origin.y.isFinite,
               let matching = NSScreen.screens.first(where: { $0.visibleFrame.contains(frame.origin) }) {
                panel.setFrame(clamped(NSRect(origin: frame.origin, size: Self.size), to: matching.visibleFrame), display: true)
                return
            }
        }
        let visible = screen.visibleFrame
        panel.setFrame(NSRect(x: visible.maxX - Self.size.width - 24,
            y: visible.maxY - Self.size.height - 24, width: Self.size.width, height: Self.size.height), display: true)
    }

    private func clamped(_ frame: NSRect, to visible: NSRect) -> NSRect {
        NSRect(x: max(visible.minX, min(visible.maxX - frame.width, frame.minX)),
               y: max(visible.minY, min(visible.maxY - frame.height, frame.minY)),
               width: frame.width, height: frame.height)
    }

    func windowDidMove(_ notification: Notification) {
        guard !restoringPosition else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.positionKey)
    }

    private func updateAppearance() {
        let now = Date()
        if now.timeIntervalSince(appearance.now) >= 60 { appearance.now = now }
        let frontmost = NSWorkspace.shared.frontmostApplication
        var desktopActive = frontmost?.bundleIdentifier == "com.apple.finder"
        if desktopActive, let pid = frontmost?.processIdentifier,
           let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            // Only owner, layer and size are needed; no titles, screenshots or Accessibility access.
            desktopActive = !windows.contains { info in
                guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                      (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                      let bounds = info[kCGWindowBounds as String] as? [String: NSNumber] else { return false }
                return (bounds["Width"]?.doubleValue ?? 0) > 100 && (bounds["Height"]?.doubleValue ?? 0) > 100
            }
        }
        if appearance.desktopActive != desktopActive { appearance.desktopActive = desktopActive }
    }

    func stop() {
        appearanceTimer?.invalidate()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        subscriptions.removeAll()
        panel.orderOut(nil)
    }
}

private final class DesktopQuotaWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Drag anywhere, double-click for details; the panel never takes keyboard focus.
private final class DesktopQuotaContainer: NSView {
    var openDetails: (() -> Void)?
    var hidePanel: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { openDetails?() }
        else { window?.performDrag(with: event) }
    }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let details = NSMenuItem(title: "Abrir cotas", action: #selector(showDetails), keyEquivalent: "")
        details.target = self; menu.addItem(details)
        let hide = NSMenuItem(title: "Ocultar painel na Mesa", action: #selector(hideDesktopPanel), keyEquivalent: "")
        hide.target = self; menu.addItem(hide)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func showDetails() { openDetails?() }
    @objc private func hideDesktopPanel() { hidePanel?() }
}

@MainActor private final class DesktopQuotaAppearance: ObservableObject {
    @Published var desktopActive = false
    @Published var now = Date()
}

private struct DesktopQuotaView: View {
    @ObservedObject var store: AccountStore
    @ObservedObject var appearance: DesktopQuotaAppearance
    private let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    private var accounts: [WidgetAccount] {
        guard store.state == .ready else { return [] }
        return WidgetSelection.selected(store.widgetAccountIDs, from: store.results.flatMap(\.accounts)).map(WidgetAccount.init)
    }
    private var stale: Bool { appearance.now.timeIntervalSince(store.lastAttempt ?? .distantPast) > 900 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<WidgetSelection.maximumAccounts, id: \.self) { index in
                let account = index < accounts.count ? accounts[index] : nil
                VStack(spacing: 14) {
                    ZStack {
                        ring(account?.windows.first?.remaining)
                        if let account { logo(account.providerID).frame(width: 27, height: 27) }
                    }
                    VStack(spacing: 6) {
                        Text(account.map { percentage($0.windows.first?.remaining) } ?? " ")
                            .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.75)
                        ResetIndicators(count: account?.availableResets, style: store.resetIndicatorStyle, showsOutline: appearance.desktopActive)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(account.map { account in
                    ([account.label, account.title] + account.windows.map { "\($0.label), \(percentage($0.remaining)) livre" } + (account.availableResets.map { ["\($0) resets disponíveis"] } ?? [])).joined(separator: ". ")
                } ?? "Posição sem conta")
            }
        }
        .padding(.horizontal, 20)
        .frame(width: 344, height: 164)
        .foregroundStyle(.white.opacity(appearance.desktopActive ? 0.95 : 0.72))
        .background {
            if #available(macOS 26.0, *) {
                shape.fill(.clear).glassEffect(.clear, in: shape)
            } else { DesktopLegacyGlass().clipShape(shape) }
        }
        .overlay { shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.6) }
    }

    private func ring(_ remaining: Double?) -> some View {
        ZStack {
            Circle().strokeBorder(.white.opacity(0.14), lineWidth: 6)
            if let remaining {
                Circle().inset(by: 3).trim(from: 0, to: max(0, min(100, remaining)) / 100)
                    .stroke(ringColor(remaining), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }.frame(width: 64, height: 64)
    }

    private func ringColor(_ remaining: Double) -> Color {
        guard appearance.desktopActive, !stale else { return .white.opacity(0.72) }
        return remaining <= 10 ? .red : remaining <= 25 ? .orange : .green
    }

    @ViewBuilder private func logo(_ provider: String) -> some View {
        let name = provider == "codex" ? "openai-black" : provider == "claude" ? "claude" : "gemini-vector"
        if let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "brands"),
           let artwork = NSImage(contentsOf: url) {
            Image(nsImage: artwork).resizable().renderingMode(.template).scaledToFit()
        } else { Image(systemName: "circle.grid.2x2") }
    }

    private func percentage(_ value: Double?) -> String {
        value.map { $0.formatted(.number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(0...1))) + "%" } ?? "—"
    }
}

private struct DesktopLegacyGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
