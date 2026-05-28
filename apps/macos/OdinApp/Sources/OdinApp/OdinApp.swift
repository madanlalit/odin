import ServiceManagement
import SwiftUI
import AppKit

@main
struct OdinDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettings()
    @StateObject private var runner = AgentRunner()
    @StateObject private var permissions = PermissionManager()

    var body: some Scene {
        WindowGroup(id: "chat") {
            Group {
                if permissions.allGranted {
                    ChatPanel()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(settings)
            .environmentObject(runner)
            .environmentObject(permissions)
            .frame(minWidth: 200, idealWidth: 620, maxWidth: 760)
            .fixedSize(horizontal: true, vertical: true)
            .clearWindowContainerBackgroundIfAvailable()
            .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("Odin", systemImage: "circle.hexagongrid") {
            StatusMenu()
                .environmentObject(settings)
                .environmentObject(runner)
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(permissions)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let icon = IconLoader.appIcon() {
            NSApp.applicationIconImage = icon
        }

        NotificationManager.shared.requestPermission()

        GlobalHotkey.shared.register { [weak self] in
            self?.toggleMainWindow()
        }

        if #available(macOS 13.0, *), Bundle.main.bundleIdentifier != nil {
            try? SMAppService.mainApp.register()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in NSApp.windows where window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotkey.shared.unregister()
    }

    private func toggleMainWindow() {
        if let window = NSApp.windows.first(where: { $0.canBecomeKey }) {
            if window.isVisible && NSApp.isActive {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func clearWindowContainerBackgroundIfAvailable() -> some View {
        if #available(macOS 15.0, *) {
            containerBackground(.clear, for: .window)
        } else {
            self
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask = [.borderless]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isMovableByWindowBackground = true
            window.level = .statusBar
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle,
            ]

            Self.anchorTopCenter(window: window)

            if let themeFrame = window.contentView?.superview {
                Self.stripBackgrounds(from: themeFrame)
            }

            for delay in [0.05, 0.15, 0.4] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    if let themeFrame = window.contentView?.superview {
                        Self.stripBackgrounds(from: themeFrame)
                    }
                }
            }

            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window,
              let themeFrame = window.contentView?.superview else { return }
        Self.stripBackgrounds(from: themeFrame)
        Self.anchorTopCenter(window: window)
    }

    static func anchorTopCenter(window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let size = window.frame.size
        let x = screen.frame.midX - size.width / 2
        let isRestingPill = size.height <= OdinNotchMetrics.restingHeight + 2
        let visibleRestingSliver: CGFloat = 0
        let expandedTopBleed = OdinNotchMetrics.expandedTopBleed
        let topBleed = isRestingPill
            ? max(0, size.height - visibleRestingSliver)
            : expandedTopBleed
        let y = screen.frame.maxY - size.height + topBleed
        let target = NSPoint(x: x, y: y)
        if window.frame.origin == target { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.allowsImplicitAnimation = true
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.0, 0.18, 1.0)
            window.animator().setFrameOrigin(target)
        }
    }

    private static func stripBackgrounds(from view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false

        if let effectView = view as? NSVisualEffectView {
            effectView.isHidden = true
        }

        for subview in view.subviews {
            stripBackgrounds(from: subview)
        }
    }
}
