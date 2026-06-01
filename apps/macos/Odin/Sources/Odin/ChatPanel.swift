import SwiftUI
import AppKit

struct ChatPanel: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var runner: AgentRunner

    @State private var task = ""
    @State private var showTrace = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        openPill
            .frame(width: 540, alignment: .top)
            .notchSurface(
                cornerRadius: OdinStyle.panelRadius,
                isAccented: runner.isRunning || runner.pendingApproval != nil
            )
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                inputFocused = true
            }
        }
        .onAppear {
            inputFocused = true
            let runnerRef = runner
            TakeoverMonitor.shared.enable {
                if runnerRef.isRunning {
                    runnerRef.stop()
                }
            }
        }
        .onDisappear {
            TakeoverMonitor.shared.disable()
        }
        .background(
            Button(action: {
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "OdinMainWindow" }) {
                    window.orderOut(nil)
                }
            }) {
                Color.clear
            }
            .keyboardShortcut(.escape, modifiers: [])
            .buttonStyle(.plain)
            .opacity(0)
        )
    }



    private var openPill: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let approval = runner.pendingApproval {
                Rectangle().fill(OdinStyle.separator).frame(height: 0.5)
                ApprovalRegion(
                    approval: approval,
                    allow: { runner.respondToPendingApproval(approved: true) },
                    skip: { runner.respondToPendingApproval(approved: false) },
                    stop: { runner.stop() }
                )
            }

            inputRegion

            if runner.pendingApproval == nil, runner.isRunning {
                Rectangle().fill(OdinStyle.separator).frame(height: 0.5)
                ProgressHairline(fraction: progressFraction)
                    .padding(.top, -1)
            }

            if let lastResult = runner.lastResult, lastResult.level == .error || lastResult.level == .warning {
                Rectangle().fill(OdinStyle.separator).frame(height: 0.5)
                ErrorBanner(message: lastResult, dismiss: { runner.lastResult = nil })
            }

            if !pinnedAndRecents.isEmpty && !runner.isRunning && runner.pendingApproval == nil {
                Rectangle().fill(OdinStyle.separator).frame(height: 0.5)
                recentsRow
            }

            if showTrace && !runner.messages.isEmpty {
                Rectangle().fill(OdinStyle.separator).frame(height: 0.5)
                TraceTimeline(messages: runner.messages, progress: runner.progress)
                    .frame(maxHeight: 360)
            }

            if !runner.messages.isEmpty {
                expandHandle
            }
        }
    }

    private var inputRegion: some View {
        HStack(alignment: .center, spacing: 12) {
            OdinMark(
                isActive: runner.isRunning || runner.pendingApproval != nil,
                size: 18
            )

            inputContent

            Spacer(minLength: 8)

            trailingControls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, runner.isRunning ? 10 : 12)
    }

    @ViewBuilder
    private var inputContent: some View {
        if runner.isRunning {
            VStack(alignment: .leading, spacing: 2) {
                Text(liveTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OdinStyle.ink)
                    .lineLimit(1)
                if !liveSubtitle.isEmpty {
                    Text(liveSubtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(OdinStyle.secondaryInk)
                        .lineLimit(1)
                }
            }
        } else {
            taskField
        }
    }

    private var taskField: some View {
        ZStack(alignment: .leading) {
            if task.isEmpty && !inputFocused {
                HStack(spacing: 8) {
                    BlinkingCaret(height: 16)
                    Text("What should I do?")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(OdinStyle.tertiaryInk)
                }
                .allowsHitTesting(false)
            }
            TextField("", text: $task)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(OdinStyle.ink)
                .tint(OdinStyle.accent)
                .focused($inputFocused)
                .onSubmit(submitTask)
        }
        .frame(height: 24)
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = true }
    }

    private var trailingControls: some View {
        HStack(spacing: 8) {
            costChip
            modelChip
            primaryButton
        }
    }

    @ViewBuilder
    private var costChip: some View {
        if let cost = runner.progress.costUSD, cost > 0 {
            Text(String(format: "$%.3f", cost))
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(OdinStyle.tertiaryInk)
                .softChip()
        }
    }

    private var modelChip: some View {
        Menu {
            Picker("Provider", selection: $settings.provider) {
                ForEach(Provider.allCases) { Text($0.displayName).tag($0) }
            }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(OdinStyle.gold).frame(width: 5, height: 5)
                Text(shortModelLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(OdinStyle.secondaryInk)
                    .lineLimit(1)
            }
            .softChip()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private var primaryButton: some View {
        if runner.isRunning {
            Button(action: { runner.stop() }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(OdinStyle.red)
                    .frame(width: 26, height: 26)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .help("Stop run")
        } else {
            Button(action: submitTask) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(task.isEmpty ? OdinStyle.tertiaryInk : OdinStyle.ink)
                    .frame(width: 26, height: 26)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(task.isEmpty)
            .help("Run")
        }
    }

    private var pinnedAndRecents: [String] {
        let pinned = settings.pinnedTasks
        let recent = settings.recentTasks.filter { !pinned.contains($0) }
        return pinned + recent
    }

    private var recentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pinnedAndRecents, id: \.self) { item in
                    RecentChip(
                        text: item,
                        pinned: settings.isPinned(item),
                        onTap: {
                            task = item
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                                submitTask()
                            }
                        },
                        onPinToggle: {
                            settings.togglePinned(item)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(height: 44)
    }

    private var expandHandle: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                showTrace.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                if runner.pendingApproval != nil && !showTrace {
                    Circle()
                        .fill(OdinStyle.gold)
                        .frame(width: 5, height: 5)
                }
                Image(systemName: showTrace ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                Text(showTrace ? "Hide trace" : "\(runner.messages.count) steps")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(OdinStyle.tertiaryInk)
            .padding(.horizontal, 10)
            .frame(height: 18)
            .background(Capsule().fill(OdinStyle.cardFill))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var liveTitle: String {
        let current = runner.currentTask?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let current, !current.isEmpty { return current }
        if let last = runner.lastResult {
            switch last.level {
            case .success: return "Done"
            case .warning: return "Stopped"
            case .error: return "Needs attention"
            case .info: return "Idle"
            }
        }
        return "Working…"
    }

    private var liveSubtitle: String {
        if runner.isRunning {
            if let action = runner.progress.currentAction {
                return "\(runner.progress.phaseTitle) \(action)"
            }
            if let detail = runner.progress.phaseDetail, !detail.isEmpty {
                return detail
            }
            return runner.progress.phaseTitle
        }
        if let last = runner.lastResult {
            let steps = max(runner.progress.actionsExecuted, 0)
            let stepLabel = steps == 1 ? "1 step" : "\(steps) steps"
            if let detail = last.detail, !detail.isEmpty {
                return "\(detail) · \(stepLabel)"
            }
            return "Done · \(stepLabel)"
        }
        return ""
    }

    private var progressFraction: CGFloat {
        guard runner.isRunning else { return 0 }
        let base: CGFloat
        if runner.progress.maxSteps > 0, runner.progress.step > 0 {
            base = CGFloat(runner.progress.step) / CGFloat(runner.progress.maxSteps)
        } else {
            base = 0.16
        }
        return min(max(base + 0.12, 0.18), 0.94)
    }

    private var shortModelLabel: String {
        let model = settings.modelLabel
        if model.contains("opus") { return "opus-4-7" }
        if model.contains("sonnet") { return "sonnet-4-6" }
        if model.contains("haiku") { return "haiku-4-5" }
        if model.contains("gemini") { return "gemini-2.0" }
        if model.count <= 14 { return model }
        return String(model.prefix(14))
    }



    private func submitTask() {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        runner.run(task: trimmed, settings: settings)
        settings.addRecentTask(trimmed)
        task = ""
        showTrace = false
    }

}

private struct BlinkingCaret: View {
    var height: CGFloat = 16
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.0, style: .continuous)
            .fill(OdinStyle.brandGradient)
            .frame(width: 2.0, height: height)
            .opacity(visible ? 1.0 : 0.0)
            .onAppear {
                withAnimation(
                    .linear(duration: 0.5)
                    .repeatForever(autoreverses: true)
                ) {
                    visible = false
                }
            }
    }
}

private struct OdinMark: View {
    let isActive: Bool
    var size: CGFloat = 18
    @State private var breath: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.5

    var body: some View {
        ZStack {
            if isActive {
                Circle()
                    .fill(OdinStyle.accent)
                    .frame(width: size * 1.25, height: size * 1.25)
                    .opacity(glowOpacity)
                    .blur(radius: 2.5)
                    .scaleEffect(breath)
            }
            
            OdinLogoImage()
                .foregroundStyle(isActive ? OdinStyle.accent : OdinStyle.accent.opacity(0.8))
                .frame(width: size * 1.1, height: size * 0.6)
                .shadow(color: OdinStyle.accent.opacity(isActive ? 0.6 : 0), radius: 3)
        }
        .frame(width: size * 1.3, height: size * 1.3)
        .onAppear {
            if isActive {
                startAnimating()
            }
        }
        .onChange(of: isActive) { _, new in
            if new {
                startAnimating()
            } else {
                breath = 1.0
                glowOpacity = 0.5
            }
        }
    }

    private func startAnimating() {
        withAnimation(
            .easeInOut(duration: 1.1)
            .repeatForever(autoreverses: true)
        ) {
            breath = 1.35
            glowOpacity = 0.15
        }
    }
}

private struct ProgressHairline: View {
    let fraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.clear)
                Rectangle()
                    .fill(OdinStyle.gold)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 1.5)
    }
}

private struct RecentChip: View {
    let text: String
    let pinned: Bool
    let onTap: () -> Void
    let onPinToggle: () -> Void
    @State private var hovering = false

    private var displayText: String {
        if text.count <= 28 { return text }
        return String(text.prefix(26)) + "…"
    }

    var body: some View {
        HStack(spacing: 5) {
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(OdinStyle.gold)
            }
            Text(displayText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(OdinStyle.secondaryInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(
            Capsule().fill(hovering ? OdinStyle.cardFillHover : OdinStyle.cardFill)
        )
        .overlay(
            Capsule().strokeBorder(hovering ? OdinStyle.accent.opacity(0.4) : OdinStyle.cardStroke, lineWidth: 0.5)
        )
        .contentShape(Capsule())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button(pinned ? "Unpin" : "Pin", action: onPinToggle)
        }
        .help(text)
        .onHover { hovering = $0 }
        .scaleOnHover(scale: 1.03)
    }
}

private struct TraceTimeline: View {
    let messages: [RunnerMessage]
    let progress: RunnerProgress

    private var visibleMessages: [RunnerMessage] {
        Array(messages.suffix(20))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(visibleMessages.enumerated()), id: \.element.id) { index, message in
                            TraceRow(
                                message: message,
                                isFirst: index == 0,
                                isLast: index == visibleMessages.count - 1,
                                isCurrent: index == visibleMessages.count - 1
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = visibleMessages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            footerStrip
        }
    }

    private var footerStrip: some View {
        HStack(spacing: 14) {
            progressFooterItem(elapsedLabel)
            progressFooterItem("\(progress.actionsExecuted) steps")
            if let cost = progress.costUSD, cost > 0 {
                progressFooterItem(String(format: "$%.3f", cost))
            } else if progress.requests > 0 {
                progressFooterItem("\(progress.requests) calls")
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Rectangle().fill(Color.white.opacity(0.025)))
        .overlay(
            Rectangle().fill(OdinStyle.separator).frame(height: 0.5),
            alignment: .top
        )
    }

    private func progressFooterItem(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
            .foregroundStyle(OdinStyle.tertiaryInk)
    }

    private var elapsedLabel: String {
        guard let first = messages.first else { return "0s" }
        let seconds = max(0, Int(Date().timeIntervalSince(first.timestamp)))
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}

private struct TraceRow: View {
    let message: RunnerMessage
    let isFirst: Bool
    let isLast: Bool
    let isCurrent: Bool

    @State private var isExpanded = false
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            timelineRail

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OdinStyle.ink)
                    if let target = inlineTarget {
                        Text(target)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(OdinStyle.secondaryInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if hasDetail {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(OdinStyle.tertiaryInk)
                    }
                }
                if isExpanded, let detail = message.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(OdinStyle.secondaryInk)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(OdinStyle.cardFill)
                        )
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color.white.opacity(0.025) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            guard hasDetail else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isExpanded.toggle()
            }
        }
    }

    private var timelineRail: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(OdinStyle.separator)
                .frame(width: 1, height: 8)
                .opacity(isFirst ? 0 : 1)
            ZStack {
                Circle().fill(dotFill).frame(width: 10, height: 10)
                if isCurrent {
                    Circle()
                        .strokeBorder(OdinStyle.gold.opacity(0.35), lineWidth: 3)
                        .frame(width: 16, height: 16)
                }
                Image(systemName: dotIcon)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.white)
            }
            Rectangle()
                .fill(OdinStyle.separator)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .opacity(isLast ? 0 : 1)
        }
        .frame(width: 16)
    }

    private var dotFill: Color {
        switch message.level {
        case .success: return OdinStyle.green
        case .warning: return OdinStyle.gold
        case .error: return OdinStyle.red
        case .info: return isCurrent ? OdinStyle.gold : OdinStyle.secondaryInk
        }
    }

    private var dotIcon: String {
        switch message.level {
        case .success: return "checkmark"
        case .warning: return "exclamationmark"
        case .error: return "xmark"
        case .info: return "circle.fill"
        }
    }

    private var hasDetail: Bool {
        guard let d = message.detail else { return false }
        return !d.isEmpty
    }

    private var displayTitle: String {
        if message.title == "Task" { return "Request" }
        if message.title == "Hint" { return "Hint" }
        if message.title.hasPrefix("Step ") && message.title.hasSuffix(" plan") {
            return "Plan"
        }
        return Self.formatActionTitle(message.title)
    }

    private var inlineTarget: String? {
        guard let detail = message.detail, !detail.isEmpty else { return nil }
        if message.title == "Task" || message.title == "Hint" {
            if detail.count > 56 { return String(detail.prefix(54)) + "…" }
            return detail
        }
        let firstLine = detail.split(separator: "\n").first.map(String.init) ?? detail
        if firstLine.count > 48 { return String(firstLine.prefix(46)) + "…" }
        return firstLine
    }

    static func formatActionTitle(_ title: String) -> String {
        switch title {
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
            return title.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct ApprovalRegion: View {
    let approval: PendingActionApproval
    let allow: () -> Void
    let skip: () -> Void
    let stop: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(OdinStyle.cardFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(OdinStyle.cardStroke, lineWidth: 0.5)
                        )
                        .frame(width: 28, height: 28)
                    Image(systemName: actionSymbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OdinStyle.ink)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Odin wants to \(approvalSentence)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(OdinStyle.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(approvalContext)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(OdinStyle.secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button(action: allow) {
                    Text("Allow")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 64, height: 26)
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: [])

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(OdinStyle.tertiaryInk)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(OdinStyle.warmCream.opacity(isExpanded ? 0.10 : 0.04)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide details" : "Show details")
            }

            if isExpanded {
                expandedDetails
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let thought = approval.thought, !thought.isEmpty {
                Text(thought)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(OdinStyle.secondaryInk)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(OdinStyle.cardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(OdinStyle.cardStroke, lineWidth: 0.5)
                    )
            }

            if !approval.detailChips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(approval.detailChips, id: \.self) { chip in
                        Text(chip)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(OdinStyle.secondaryInk)
                            .softChip(height: 20)
                    }
                }
            }

            HStack(spacing: 8) {
                Spacer()

                Button(action: skip) {
                    Text("Skip step")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 92, height: 28)
                }
                .buttonStyle(SoftButtonStyle())
                .keyboardShortcut(.escape, modifiers: [])

                Button(action: stop) {
                    Text("Stop run")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 88, height: 28)
                }
                .buttonStyle(DestructiveButtonStyle())
                .keyboardShortcut(".", modifiers: .command)
            }
        }
    }

    private var actionSymbol: String {
        switch approval.action {
        case "click", "click_element", "press_element": return "cursorarrow.click.2"
        case "double_click", "double_click_element": return "cursorarrow.click.badge.clock"
        case "type", "set_text": return "keyboard"
        case "hotkey": return "command"
        case "scroll", "scroll_element": return "arrow.up.arrow.down"
        default: return "arrow.up.right.circle"
        }
    }

    private var approvalSentence: String {
        let title = approval.actionTitle
        guard let first = title.first else { return "perform an action" }
        return first.lowercased() + title.dropFirst()
    }

    private var approvalContext: String {
        let subtitle = approval.actionSubtitle ?? "Current app"
        return "\(subtitle) · Step \(approval.batchIndex) of \(approval.batchCount)"
    }
}

private struct ErrorBanner: View {
    let message: RunnerMessage
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(message.level.color)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(message.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(OdinStyle.ink)
                if let detail = message.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(OdinStyle.secondaryInk)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(OdinStyle.tertiaryInk)
            }
            .buttonStyle(.plain)
            .scaleOnHover()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(message.level.color.opacity(0.04))
    }
}

extension RunnerMessage.Level {
    var color: Color {
        switch self {
        case .info: return OdinStyle.gold
        case .success: return OdinStyle.green
        case .warning: return OdinStyle.gold
        case .error: return OdinStyle.red
        }
    }
}
