import SwiftUI
import AppKit

/// The Odin chat panel. One liquid-glass surface, four calm zones:
/// Stage (what's happening), WhisperLog (recent activity), Command
/// (the input), and Library (pinned and recent tasks).
struct ChatPanel: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var runner: AgentRunner

    @SwiftUI.State private var task: String = ""
    @SwiftUI.State private var pickerVisible: Bool = false
    @SwiftUI.State private var whisperLogExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StageHeader(
                state: stageState,
                onSuggestion: { suggestion in
                    task = suggestion
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { submitTask() }
                },
                onAllow: { runner.respondToPendingApproval(approved: true) },
                onStop: { runner.stop() }
            )
            if shouldShowWhisperLog {
                Hairline()
                WhisperLogDisclosure(
                    entryCount: whisperEntries.count,
                    isExpanded: whisperLogExpanded,
                    onToggle: {
                        withAnimation(OdinMotion.current.rise) { whisperLogExpanded.toggle() }
                    }
                )
                if whisperLogExpanded {
                    WhisperLog(entries: whisperEntries)
                        .frame(maxHeight: whisperLogHeight)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                }
            }
            if shouldShowCommandAndLibrary {
                Hairline()
                CommandBar(
                    text: $task,
                    modelLabel: shortModelLabel,
                    costLabel: costLabel,
                    isRunning: runner.isRunning,
                    canSubmit: !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onSubmit: submitTask,
                    onStop: { runner.stop() },
                    onPickModel: { pickerVisible.toggle() }
                )
                if !pinnedAndRecents.isEmpty && !runner.isRunning && runner.pendingApproval == nil {
                    Hairline()
                    LibraryStrip(
                        pinned: settings.pinnedTasks,
                        recents: settings.recentTasks,
                        onSelect: { item in
                            task = item
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { submitTask() }
                        },
                        onPinToggle: { settings.togglePinned($0) }
                    )
                }
            }
        }
        .frame(width: OdinTokens.Size.panelWidth)
        .odinPanelSurface(isAccented: runner.isRunning || runner.pendingApproval != nil)
        .background(
            // Hidden escape-to-dismiss button
            Button(action: dismiss) { Color.clear }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .opacity(0)
        )
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                NotificationCenter.default.post(name: .odinFocusCommand, object: nil)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                NotificationCenter.default.post(name: .odinFocusCommand, object: nil)
            }
            let runnerRef = runner
            TakeoverMonitor.shared.enable {
                if runnerRef.isRunning { runnerRef.stop() }
            }
        }
        .onDisappear {
            TakeoverMonitor.shared.disable()
        }
        .onChange(of: runner.isRunning) { _, isRunning in
            // While a run is active, traces must be open so the user can
            // watch progress. Once it completes, collapse the log so the
            // panel returns to a calm "Done" state. The user can always
            // tap the disclosure row to inspect the trace.
            withAnimation(OdinMotion.current.rise) {
                whisperLogExpanded = isRunning
            }
        }
    }

    // MARK: - Derived

    private var stageState: StageHeader.State {
        if let approval = runner.pendingApproval {
            return .awaiting(approval: approval)
        }
        if runner.isRunning {
            return .working(
                phase: runner.progress.phaseTitle,
                currentAction: runner.progress.currentAction,
                step: runner.progress.step,
                maxSteps: max(runner.progress.maxSteps, 1),
                elapsed: elapsedLabel,
                cost: costLabel
            )
        }
        if let last = runner.lastResult {
            switch last.level {
            case .error:
                return .error(headline: "Needs attention", detail: last.detail ?? last.title)
            case .warning:
                return .error(headline: "Stopped", detail: last.detail ?? last.title)
            case .success:
                return .done(headline: "Done", detail: last.detail)
            case .info:
                return .idle()
            }
        }
        return .idle(suggestions: idleSuggestions)
    }

    private var idleSuggestions: [String] {
        if !settings.pinnedTasks.isEmpty { return Array(settings.pinnedTasks.prefix(3)) }
        return Self.defaultSuggestions
    }

    private static let defaultSuggestions: [String] = [
        "Plan my week",
        "Summarize this tab",
        "Find todos in Mail"
    ]

    private var whisperEntries: [WhisperLog.Entry] {
        runner.messages.map { msg in
            WhisperLog.Entry(
                timestamp: msg.timestamp,
                title: Self.formatTitle(msg.title),
                detail: msg.detail,
                level: Self.mapLevel(msg.level)
            )
        }
    }

    private var shouldShowWhisperLog: Bool {
        !runner.messages.isEmpty
    }

    private var whisperLogHeight: CGFloat {
        let count = min(whisperEntries.count, OdinTokens.Size.whisperMaxLines)
        return CGFloat(count) * OdinTokens.Size.whisperLineHeight + OdinTokens.Space.s12
    }

    private var shouldShowCommandAndLibrary: Bool {
        // Always show command, except when approval is up and we want focus
        // to land on the Allow button. Even in awaiting mode the user may
        // want to add a hint.
        true
    }

    private var pinnedAndRecents: [String] {
        let pinned = settings.pinnedTasks
        let recents = settings.recentTasks.filter { !pinned.contains($0) }
        return pinned + recents
    }

    private var shortModelLabel: String {
        let model = settings.modelLabel
        if model.isEmpty { return "—" }
        if model.count <= 14 { return model }
        return String(model.prefix(14))
    }

    private var costLabel: String? {
        guard let cost = runner.progress.costUSD, cost > 0 else { return nil }
        return String(format: "$%.3f", cost)
    }

    private var elapsedLabel: String {
        guard let first = runner.messages.first else { return "0s" }
        let seconds = max(0, Int(Date().timeIntervalSince(first.timestamp)))
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    // MARK: - Actions

    private func submitTask() {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        runner.run(task: trimmed, settings: settings)
        settings.addRecentTask(trimmed)
        task = ""
    }

    private func dismiss() {
        guard runner.pendingApproval == nil else { return }
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "OdinMainWindow" }) {
            window.orderOut(nil)
        }
    }

    // MARK: - Title formatting

    private static func formatTitle(_ raw: String) -> String {
        if raw == "Task" { return "Request" }
        if raw == "Hint" { return "Hint" }
        if raw.hasPrefix("Step ") && raw.hasSuffix(" plan") { return "Plan" }
        switch raw {
        case "click", "click_element": return "Click"
        case "double_click", "double_click_element": return "Double click"
        case "press_element": return "Press"
        case "focus_element": return "Focus"
        case "set_text": return "Set text"
        case "type": return "Type"
        case "hotkey": return "Shortcut"
        case "scroll", "scroll_element": return "Scroll"
        case "move": return "Move"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func mapLevel(_ level: RunnerMessage.Level) -> WhisperLog.Entry.Level {
        switch level {
        case .info:    return .info
        case .success: return .success
        case .warning: return .warning
        case .error:   return .error
        }
    }
}
