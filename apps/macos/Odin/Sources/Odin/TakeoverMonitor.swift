import AppKit

@MainActor
final class TakeoverMonitor {
    static let shared = TakeoverMonitor()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onTakeover: (() -> Void)?

    private init() {}

    func enable(onTakeover: @escaping () -> Void) {
        self.onTakeover = onTakeover
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
            return event
        }
    }

    func disable() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        onTakeover = nil
    }

    private func handle(_ event: NSEvent) {
        guard isTakeoverChord(event) else { return }
        onTakeover?()
    }

    private func isTakeoverChord(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let required: NSEvent.ModifierFlags = [.command, .shift]
        guard flags == required else { return false }
        if event.keyCode == 47 { return true }
        if let chars = event.charactersIgnoringModifiers, chars == "." {
            return true
        }
        return false
    }
}
