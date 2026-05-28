import AppKit
import QuartzCore

@MainActor
final class AgentPointerOverlay {
    static let shared = AgentPointerOverlay()

    private let size = NSSize(width: 72, height: 72)
    private let pointerView = AgentPointerView(frame: NSRect(x: 0, y: 0, width: 72, height: 72))
    private var panel: NSPanel?
    private var hasPosition = false
    private var hideWorkItem: DispatchWorkItem?

    private init() {}

    func show(atAutomationX x: Double, y: Double, action: String) {
        let point = appKitPointFromAutomationCoordinates(x: x, y: y)
        let panel = ensurePanel()
        let origin = NSPoint(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2
        )

        pointerView.action = action
        pointerView.isClicking = Self.isClickAction(action)
        pointerView.needsDisplay = true

        panel.orderFrontRegardless()
        hideWorkItem?.cancel()

        if hasPosition {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrameOrigin(origin)
            }
        } else {
            panel.setFrameOrigin(origin)
            hasPosition = true
        }

        if Self.isClickAction(action) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
                self?.pointerView.isClicking = false
                self?.pointerView.needsDisplay = true
            }
        }

        let hide = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWorkItem = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: hide)
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panel?.orderOut(nil)
        hasPosition = false
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
        ]
        panel.contentView = pointerView
        self.panel = panel
        return panel
    }

    private func appKitPointFromAutomationCoordinates(x: Double, y: Double) -> NSPoint {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return NSPoint(x: x, y: y)
        }

        let minX = screens.map(\.frame.minX).min() ?? 0
        let maxY = screens.map(\.frame.maxY).max() ?? 0
        return NSPoint(x: minX + x, y: maxY - y)
    }

    private static func isClickAction(_ action: String) -> Bool {
        action == "click"
            || action == "double_click"
            || action == "click_element"
            || action == "double_click_element"
            || action == "press_element"
    }
}

private final class AgentPointerView: NSView {
    var action = ""
    var isClicking = false

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let target = CGPoint(x: bounds.midX, y: bounds.midY)
        drawPulse(at: target)
        drawPointer(tip: target)
    }

    private func drawPulse(at target: CGPoint) {
        let radius: CGFloat = isClicking ? 20 : 12
        let alpha: CGFloat = isClicking ? 0.34 : 0.16
        let rect = CGRect(
            x: target.x - radius,
            y: target.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        NSColor.systemBlue.withAlphaComponent(alpha).setFill()
        NSBezierPath(ovalIn: rect).fill()

        NSColor.systemBlue.withAlphaComponent(isClicking ? 0.72 : 0.4).setStroke()
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
        ring.lineWidth = isClicking ? 2.2 : 1.4
        ring.stroke()
    }

    private func drawPointer(tip: CGPoint) {
        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: CGPoint(x: tip.x + 4, y: tip.y + 28))
        path.line(to: CGPoint(x: tip.x + 11, y: tip.y + 21))
        path.line(to: CGPoint(x: tip.x + 17, y: tip.y + 35))
        path.line(to: CGPoint(x: tip.x + 23, y: tip.y + 32))
        path.line(to: CGPoint(x: tip.x + 17, y: tip.y + 18))
        path.line(to: CGPoint(x: tip.x + 27, y: tip.y + 18))
        path.close()

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: 1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        shadow.set()

        NSColor.white.withAlphaComponent(0.96).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.38).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
