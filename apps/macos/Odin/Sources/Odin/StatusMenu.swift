import SwiftUI
import AppKit

/// The menu-bar popover. Compact, scannable, with the eye at the center
/// and the live activity ring wrapping it while a run is in progress.
struct StatusMenu: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var runner: AgentRunner
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()
            actions
            Hairline()
            footer
        }
        .frame(width: 260)
        .background(OdinTokens.Color.surface)
    }

    private var header: some View {
        // Just the brand wordmark. State is conveyed by the wordmark
        // color (amber idle / amberBright awaiting / success done /
        // danger error) so the menu still has feedback without the eye.
        Text("ODIN")
            .font(OdinRuneFont.font(size: 40))
            .foregroundStyle(irisColor)
            .tracking(2)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OdinTokens.Space.s14)
            .padding(.vertical, OdinTokens.Space.s14)
    }

    /// The brand color the ODIN wordmark takes in the status menu.
    /// Mirrors `EyeRuneMark.irisColor` so the two surfaces stay in sync
    /// even though only the chat panel shows the eye.
    private var irisColor: Color {
        if runner.isRunning { return OdinTokens.Color.amber }
        if let last = runner.lastResult {
            switch last.level {
            case .success: return OdinTokens.Color.success
            case .warning, .error: return OdinTokens.Color.danger
            case .info: return OdinTokens.Color.amber
            }
        }
        return OdinTokens.Color.amber
    }

    private var actions: some View {
        VStack(spacing: 2) {
            OdinMenuRow(
                label: "Show Odin",
                symbol: "macwindow",
                trailing: compactHotkeyString,
                onTap: { showOdin() }
            )
            if runner.isRunning {
                OdinMenuRow(
                    label: "Stop current task",
                    symbol: "stop.fill",
                    onTap: { runner.stop() }
                )
            }
            if runner.latestMessage != nil {
                OdinMenuRow(
                    label: "Clear status",
                    symbol: "trash",
                    onTap: { runner.clear() }
                )
            }
            if let tracePath = runner.progress.tracePath,
               FileManager.default.fileExists(atPath: tracePath) {
                OdinMenuRow(
                    label: "Reveal trace log",
                    symbol: "doc.text.magnifyingglass",
                    onTap: {
                        NSWorkspace.shared.selectFile(tracePath, inFileViewerRootedAtPath: "")
                    }
                )
            }
            OdinMenuRow(
                label: "Settings",
                symbol: "slider.horizontal.3",
                trailing: "⌘,",
                onTap: openSettingsAction
            )
        }
        .padding(.vertical, OdinTokens.Space.s4)
    }

    private var footer: some View {
        HStack(spacing: OdinTokens.Space.s8) {
            ModelChip(
                label: settings.modelAlias.isEmpty ? "No model" : settings.modelAlias
            )
            Spacer()
            Button(action: { NSApp.terminate(nil) }) {
                HStack(spacing: 5) {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Quit")
                        .font(OdinTokens.Font.caption)
                }
                .foregroundStyle(OdinTokens.Color.ink3)
                .padding(.horizontal, OdinTokens.Space.s8)
                .frame(height: 22)
                .background(
                    Capsule()
                        .fill(OdinTokens.Color.surface)
                )
                .overlay(
                    Capsule()
                        .stroke(OdinTokens.Color.hairline, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .help("Quit Odin")
        }
        .padding(.horizontal, OdinTokens.Space.s14)
        .padding(.vertical, OdinTokens.Space.s10)
    }

    // MARK: - Derived

    private var eyeState: OdinEye.State {
        if runner.isRunning { return .watching }
        if let last = runner.lastResult {
            switch last.level {
            case .success: return .done
            case .warning, .error: return .error
            case .info: return .idle
            }
        }
        return .idle
    }

    private var progressFraction: CGFloat {
        guard runner.isRunning,
              runner.progress.maxSteps > 0,
              runner.progress.step > 0 else { return 0 }
        return CGFloat(runner.progress.step) / CGFloat(runner.progress.maxSteps)
    }

    private var statusTitle: String {
        if runner.isRunning { return runner.progress.phaseTitle }
        if let last = runner.lastResult {
            switch last.level {
            case .success: return "Finished"
            case .warning: return "Stopped"
            case .error:   return "Needs attention"
            case .info:    return "Idle"
            }
        }
        return "Ready"
    }

    private var statusSubtitle: String {
        if runner.isRunning {
            let s = max(runner.progress.actionsExecuted, 0)
            let stepLabel = s == 1 ? "1 step" : "\(s) steps"
            if let action = runner.progress.currentAction, !action.isEmpty {
                return "\(stepLabel) · \(action)"
            }
            return stepLabel
        }
        if let last = runner.lastResult {
            let s = max(runner.progress.actionsExecuted, 0)
            let stepLabel = s == 1 ? "1 step" : "\(s) steps"
            if let detail = last.detail, !detail.isEmpty {
                return "\(stepLabel) · \(detail)"
            }
            return stepLabel
        }
        return "Awaiting your command"
    }

    private var compactHotkeyString: String {
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(settings.hotkeyModifiers))
        return HotkeyFormatter.modifierSymbols(modifierFlags)
            + HotkeyFormatter.symbol(for: UInt16(settings.hotkeyKeyCode))
    }

    // MARK: - Actions

    private func showOdin() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showMainWindow()
        }
    }

    private func openSettingsAction() {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// A circular progress ring wrapping the eye. Uses `Circle().trim(from:to:)`
/// on the amber color while a run is in progress.
struct ActivityRing<Content: View>: View {
    let progress: CGFloat
    let state: OdinEye.State
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(OdinTokens.Color.hairline, lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, min(progress, 1.0)))
                .stroke(
                    AngularGradient(
                        colors: [OdinTokens.Color.amber, OdinTokens.Color.amberBright],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(OdinMotion.current.breathe, value: progress)
            content()
        }
    }
}
