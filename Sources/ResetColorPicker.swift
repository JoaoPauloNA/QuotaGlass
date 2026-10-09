import AppKit
import SwiftUI

// Own the panel-opening action so its location is anchored to this control.
struct ResetColorPicker: NSViewRepresentable {
    @Binding var color: Color

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Escolher cor", target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.bezelStyle = .rounded
        button.setAccessibilityLabel("Escolher cor do emoji")
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        let swatch = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3).fill()
            return true
        }
        button.image = swatch
        button.imagePosition = .imageLeading
    }
    static func dismantleNSView(_ button: NSButton, coordinator: Coordinator) {
        guard NSColorPanel.sharedColorPanelExists else { return }
        let panel = NSColorPanel.shared
        if Coordinator.active === coordinator {
            Coordinator.active = nil
            panel.setTarget(nil)
            panel.setAction(nil)
            panel.orderOut(nil)
        }
    }

    @MainActor final class Coordinator: NSObject {
        static weak var active: Coordinator?
        var parent: ResetColorPicker
        init(_ parent: ResetColorPicker) { self.parent = parent }
        @objc func open(_ sender: NSButton) {
            guard let window = sender.window else { return }
            let panel = NSColorPanel.shared
            panel.setTarget(nil)
            panel.color = NSColor(parent.color)
            panel.showsAlpha = false
            panel.isContinuous = true
            Self.active = self
            panel.setTarget(self)
            panel.setAction(#selector(changed(_:)))
            panel.orderFront(nil)
            let anchor = window.convertToScreen(sender.convert(sender.bounds, to: nil))
            let screen = window.screen ?? NSScreen.main
            guard let visible = screen?.visibleFrame else { return }
            let size = panel.frame.size
            let gap: CGFloat = 10
            var x = window.frame.maxX + gap
            if x + size.width > visible.maxX { x = window.frame.minX - gap - size.width }
            x = max(visible.minX, min(x, visible.maxX - size.width))
            let y = max(visible.minY, min(anchor.maxY - size.height, visible.maxY - size.height))
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        @objc func changed(_ panel: NSColorPanel) { parent.color = Color(nsColor: panel.color) }
    }
}
