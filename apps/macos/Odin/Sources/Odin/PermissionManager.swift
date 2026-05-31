import AppKit
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    @Published var hasAccessibility: Bool = false
    @Published var hasScreenRecording: Bool = false

    var allGranted: Bool {
        hasAccessibility && hasScreenRecording
    }

    private var timer: Timer?

    init() {
        refresh()
    }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        hasAccessibility = Self.checkAccessibility()
        hasScreenRecording = Self.checkScreenRecording()
    }


    static func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }


    static func checkScreenRecording() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    static func requestScreenRecording() {
        if #available(macOS 10.15, *) {
            CGRequestScreenCaptureAccess()
        }
    }

    static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
