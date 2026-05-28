import AppKit
import Carbon.HIToolbox

@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    private var eventMonitor: Any?
    private var onToggle: (() -> Void)?

    private init() {}

    func register(handler: @escaping () -> Void) {
        onToggle = handler
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isHotkeyEvent(event) == true {
                self?.onToggle?()
                return nil
            }
            return event
        }
    }

    func unregister() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        onToggle = nil
    }

    private func handleEvent(_ event: NSEvent) {
        guard isHotkeyEvent(event) else { return }
        Task { @MainActor in
            onToggle?()
        }
    }

    private func isHotkeyEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == 49 && flags == .option
    }
}
