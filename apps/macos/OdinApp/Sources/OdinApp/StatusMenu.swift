import SwiftUI
import AppKit

struct StatusMenu: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var runner: AgentRunner
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(OdinStyle.separator).frame(height: 0.5)
            actions
        }
        .frame(width: 260)
        .background(OdinStyle.background.opacity(0.85))
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(runner.isRunning ? OdinStyle.accent.opacity(0.12) : OdinStyle.warmCream.opacity(0.04))
                    .frame(width: 28, height: 28)
                Image("OdinLogo", bundle: .module)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(runner.isRunning ? OdinStyle.accent : OdinStyle.ink.opacity(0.74))
                    .frame(width: 22, height: 12)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Odin")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OdinStyle.ink)
                Text(statusLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
                    .frame(maxWidth: 150, alignment: .leading)
            }

            Spacer()

            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text(settings.modelAlias)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(OdinStyle.secondaryInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(OdinStyle.warmCream.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(OdinStyle.warmCream.opacity(0.08), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 3) {
            StatusMenuButton(
                label: "Show Odin",
                systemImage: "macwindow",
                shortcut: compactHotkeyString
            ) {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.showMainWindow()
                }
            }

            if runner.isRunning {
                StatusMenuButton(
                    label: "Stop Current Task",
                    systemImage: "stop.fill",
                    shortcut: nil
                ) {
                    runner.stop()
                }
            }

            if runner.latestMessage != nil {
                StatusMenuButton(
                    label: "Clear Status",
                    systemImage: "trash",
                    shortcut: nil
                ) {
                    runner.clear()
                }
            }

            if let tracePath = runner.progress.tracePath, FileManager.default.fileExists(atPath: tracePath) {
                StatusMenuButton(
                    label: "Reveal Trace Log",
                    systemImage: "doc.text.magnifyingglass",
                    shortcut: nil
                ) {
                    NSWorkspace.shared.selectFile(tracePath, inFileViewerRootedAtPath: "")
                }
            }

            StatusMenuButton(
                label: "Settings…",
                systemImage: "slider.horizontal.3",
                shortcut: "⌘,"
            ) {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }

            StatusMenuButton(
                label: "Quit Odin",
                systemImage: "power",
                shortcut: "⌘Q"
            ) {
                NSApp.terminate(nil)
            }
        }
        .padding(6)
    }

    private var statusLine: String {
        if runner.isRunning {
            return runner.progress.currentAction ?? runner.progress.phaseTitle
        }
        if let last = runner.lastResult {
            if last.level == .success {
                return "Finished"
            } else {
                return last.detail ?? last.title
            }
        }
        return "Ready"
    }

    private var statusColor: Color {
        if runner.isRunning {
            return OdinStyle.accent
        }
        if let last = runner.lastResult {
            return last.level == .success ? OdinStyle.secondaryInk : Color(red: 1.0, green: 0.4, blue: 0.4)
        }
        return OdinStyle.secondaryInk
    }


    private var compactHotkeyString: String {
        let keyCode = settings.hotkeyKeyCode
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(settings.hotkeyModifiers))
        
        var parts = ""
        if modifierFlags.contains(.control) { parts += "⌃" }
        if modifierFlags.contains(.option) { parts += "⌥" }
        if modifierFlags.contains(.shift) { parts += "⇧" }
        if modifierFlags.contains(.command) { parts += "⌘" }
        
        parts += keyName(for: UInt16(keyCode))
        return parts
    }

    private func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            if let char = KeyMap.char(for: keyCode) {
                return char.uppercased()
            }
            return "\(keyCode)"
        }
    }
}

struct StatusMenuButton: View {
    let label: String
    let systemImage: String
    var shortcut: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 14, height: 14)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(OdinStyle.tertiaryInk)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(OdinStyle.warmCream.opacity(0.04))
                        )
                }
            }
            .foregroundStyle(isHovering ? OdinStyle.ink : OdinStyle.secondaryInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? OdinStyle.warmCream.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}
