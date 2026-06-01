import Combine
import ServiceManagement
import SwiftUI
import AppKit

@main
struct OdinDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            StatusMenu()
                .environmentObject(appDelegate.settings)
                .environmentObject(appDelegate.runner)
                .tint(OdinStyle.accent)
        } label: {
            if let img = IconLoader.resizedLogo(height: 18, horizontalPadding: 6) {
                Image(nsImage: img)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appDelegate.settings)
                .environmentObject(appDelegate.permissions)
                .tint(OdinStyle.accent)
        }
    }
}

final class OdinPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    static private(set) var shared: AppDelegate!

    let settings = AppSettings()
    let runner = AgentRunner()
    let permissions = PermissionManager()

    var panel: NSPanel?
    private var panelStateCancellables = Set<AnyCancellable>()

    private var panelShouldPersist: Bool {
        runner.pendingApproval != nil || (runner.isRunning && settings.requireActionApproval)
    }

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let icon = IconLoader.appIcon() {
            NSApp.applicationIconImage = icon
            NSApp.dockTile.display()
        } else if let icon = Bundle.module.image(forResource: "AppIcon") {
            NSApp.applicationIconImage = icon
            NSApp.dockTile.display()
        }

        NotificationManager.shared.requestPermission()

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let window = notification.object as? NSWindow, window == self.panel else { return }
                if self.panelShouldPersist { return }
                window.orderOut(nil)
            }
        }

        GlobalHotkey.shared.register { [weak self] in
            self?.toggleMainWindow()
        }

        if #available(macOS 13.0, *), Bundle.main.bundleIdentifier != nil {
            try? SMAppService.mainApp.register()
        }

        setupPanel()

        runner.$isRunning
            .combineLatest(runner.$pendingApproval, settings.$requireActionApproval)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.refreshPanelLevel()
            }
            .store(in: &panelStateCancellables)
    }

    private func setupPanel() {
        let rootView = Group {
            if permissions.allGranted {
                ChatPanel()
            } else {
                OnboardingView()
            }
        }
        .environmentObject(settings)
        .environmentObject(runner)
        .environmentObject(permissions)
        .tint(OdinStyle.accent)

        let panel = OdinPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("OdinMainWindow")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]

        let hostingView = NSHostingView(rootView: rootView.background(WindowSizeUpdater(window: panel)))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor)
        ])

        self.panel = panel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        toggleMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotkey.shared.unregister()
    }

    func showMainWindow() {
        guard let panel = panel else { return }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleMainWindow() {
        guard let panel = panel else { return }
        if panelShouldPersist {
            showMainWindow()
            return
        }
        if panel.isVisible && NSApp.isActive {
            panel.orderOut(nil)
        } else {
            showMainWindow()
        }
    }

    private func refreshPanelLevel() {
        guard let panel else { return }
        let target: NSWindow.Level = panelShouldPersist ? .popUpMenu : .statusBar
        if panel.level != target {
            panel.level = target
        }
    }
}

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct WindowSizeUpdater: View {
    let window: NSWindow

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(key: SizePreferenceKey.self, value: geo.size)
        }
        .onPreferenceChange(SizePreferenceKey.self) { size in
            guard size.width > 0 && size.height > 0 else { return }
            DispatchQueue.main.async {
                Self.updateWindowFrame(window: window, size: size)
            }
        }
    }

    static func updateWindowFrame(window: NSWindow, size: CGSize) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let x = screen.frame.midX - size.width / 2
        let topMargin: CGFloat = 120
        let y = screen.frame.maxY - size.height - topMargin
        let target = NSRect(x: x, y: y, width: size.width, height: size.height)

        if window.frame == target { return }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.allowsImplicitAnimation = true
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.0, 0.18, 1.0)
            window.animator().setFrame(target, display: true)
        }
    }
}
