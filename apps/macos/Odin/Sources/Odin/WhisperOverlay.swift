import AppKit
import SwiftUI

/// A small cursor-tracking tooltip that briefly shows what Odin is
/// currently doing. Complement to the in-panel WhisperLog — this is
/// the ephemeral version, the log is the persistent version.
@MainActor
final class WhisperOverlay {
    static let shared = WhisperOverlay()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<WhisperLabel>?
    private var trackingTimer: Timer?
    private var currentText: String = ""
    private var fadeWorkItem: DispatchWorkItem?

    private init() {}

    func show(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { hide(); return }
        if trimmed == currentText, panel?.isVisible == true {
            scheduleFade(); return
        }
        currentText = trimmed

        let panel = ensurePanel()
        let view = ensureHostingView()
        view.rootView = WhisperLabel(text: trimmed)
        view.layoutSubtreeIfNeeded()

        let fitting = view.fittingSize
        let size = NSSize(
            width: max(140, ceil(fitting.width)),
            height: max(28, ceil(fitting.height))
        )
        view.setFrameSize(size)
        panel.setContentSize(size)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        repositionToCursor()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0.95
        }
        startTracking()
        scheduleFade()
    }

    func hide() {
        fadeWorkItem?.cancel()
        fadeWorkItem = nil
        stopTracking()
        currentText = ""
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor [weak self] in
                self?.panel?.orderOut(nil)
            }
        }
    }

    private func scheduleFade() {
        fadeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        fadeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: work)
    }

    private func startTracking() {
        stopTracking()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.repositionToCursor() }
        }
        RunLoop.current.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    private func repositionToCursor() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        let screen = NSScreen.screens.first { NSPointInRect(mouse, $0.frame) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin = NSPoint(x: mouse.x + 14, y: mouse.y - size.height - 14)
        if origin.x + size.width > visible.maxX - 8 {
            origin.x = mouse.x - size.width - 14
        }
        if origin.y < visible.minY + 8 {
            origin.y = mouse.y + 18
        }
        if origin.x < visible.minX + 8 {
            origin.x = visible.minX + 8
        }
        panel.setFrameOrigin(origin)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]
        self.panel = panel
        return panel
    }

    private func ensureHostingView() -> NSHostingView<WhisperLabel> {
        if let hostingView {
            panel?.contentView = hostingView
            return hostingView
        }
        let view = NSHostingView(rootView: WhisperLabel(text: ""))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = 14
        view.layer?.masksToBounds = true
        panel?.contentView = view
        hostingView = view
        return view
    }
}

private struct WhisperLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: OdinTokens.Space.s8) {
            Circle()
                .fill(OdinTokens.Color.amber)
                .frame(width: 6, height: 6)
            Text(text)
                .font(OdinTokens.Font.caption)
                .foregroundStyle(OdinTokens.Color.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, OdinTokens.Space.s12)
        .padding(.vertical, OdinTokens.Space.s6)
        .background(
            Capsule()
                .fill(OdinTokens.Color.surface)
        )
        .overlay(
            Capsule()
                .stroke(OdinTokens.Color.amberLine.opacity(0.6), lineWidth: 0.5)
        )
        .fixedSize()
    }
}
