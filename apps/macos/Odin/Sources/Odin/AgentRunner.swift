import Foundation
import AppKit

struct RunnerMessage: Identifiable {
    enum Level {
        case info
        case success
        case warning
        case error
    }

    let id = UUID()
    let timestamp = Date()
    let title: String
    let detail: String?
    let level: Level
}

struct RunnerProgress {
    var step: Int = 0
    var maxSteps: Int = 0
    var actionsExecuted: Int = 0
    var phaseTitle: String = "Ready"
    var phaseDetail: String? = nil
    var currentAction: String? = nil
    var lastThought: String? = nil
    var lastAction: String? = nil
    var requests: Int = 0
    var costUSD: Double? = nil
    var costEstimated: Bool = false
    var tracePath: String? = nil

    static let empty = RunnerProgress()
}

struct PendingActionApproval: Identifiable {
    let id: String
    let step: Int
    let batchIndex: Int
    let batchCount: Int
    let thought: String?
    let action: String
    let actionTitle: String
    let actionSubtitle: String?
    let detailChips: [String]
    let focusOwnerProcessIdentifier: pid_t?

    var requiresForegroundFocus: Bool {
        action == "type" || action == "set_text" || action == "hotkey"
    }
}

final class AgentRunner: ObservableObject {
    @Published var isRunning = false
    @Published var messages: [RunnerMessage] = []
    @Published var progress = RunnerProgress.empty
    @Published var lastResult: RunnerMessage? = nil
    @Published var currentTask: String? = nil
    @Published var pendingApproval: PendingActionApproval? = nil
    @Published var pendingHint: String? = nil
    @Published var lastWhisper: String? = nil {
        didSet {
            guard let text = lastWhisper else {
                Task { @MainActor in WhisperOverlay.shared.hide() }
                return
            }
            Task { @MainActor in WhisperOverlay.shared.show(text: text) }
        }
    }

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutBuffer = ""
    private var stderrBuffer = ""

    var latestMessage: RunnerMessage? {
        messages.last
    }

    func run(task: String, settings: AppSettings) {
        stop()
        messages = []
        progress = RunnerProgress.empty
        progress.maxSteps = settings.maxSteps
        progress.phaseTitle = "Starting"
        progress.phaseDetail = task
        currentTask = task
        lastResult = nil
        append(RunnerMessage(title: "Task", detail: task, level: .info))
        isRunning = true

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        var isBundled = false
        var pythonURL: URL? = nil
        if let bundledPythonURL = Bundle.main.url(forResource: "python/bin/python3", withExtension: nil) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: bundledPythonURL.path),
               let size = attrs[.size] as? UInt64,
               size > 1000 {
                isBundled = true
                pythonURL = bundledPythonURL
            }
        }

        let tracePath = makeTracePath(repoPath: settings.repoPath, isBundled: isBundled)
        progress.tracePath = tracePath

        if isBundled, let pythonURL {
            process.executableURL = pythonURL
            process.currentDirectoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            
            let resourcePath = Bundle.main.resourcePath!
            var env = ProcessInfo.processInfo.environment
            env["PYTHONPATH"] = "\(resourcePath)/src:\(resourcePath)/site-packages"
            env["PYTHONUNBUFFERED"] = "1"
            env["PYTHONIOENCODING"] = "utf-8"
            
            env["ODIN_LLM_PROVIDER"] = settings.provider.rawValue
            env["AWS_REGION"] = settings.awsRegion
            env["AWS_DEFAULT_REGION"] = settings.awsRegion
            env["AWS_REGION_NAME"] = settings.awsRegion

            let key = settings.apiKey()
            if !key.isEmpty {
                if settings.provider == .openrouter {
                    env["OPENROUTER_API_KEY"] = key
                } else if settings.provider == .bedrock {
                    env["BEDROCK_API_KEY"] = key
                }
            }

            let awsAccessKeyId = settings.awsAccessKeyId()
            let awsSecretKey = settings.awsSecretAccessKey()
            let awsSessionToken = settings.awsSessionToken()

            if !awsAccessKeyId.isEmpty { env["AWS_ACCESS_KEY_ID"] = awsAccessKeyId }
            if !awsSecretKey.isEmpty { env["AWS_SECRET_ACCESS_KEY"] = awsSecretKey }
            if !awsSessionToken.isEmpty { env["AWS_SESSION_TOKEN"] = awsSessionToken }

            let lines = settings.customEnv.split(separator: "\n")
            for line in lines {
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let k = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let v = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !k.isEmpty {
                        env[k] = v
                    }
                }
            }
            process.environment = env
            process.arguments = buildArguments(
                task: task,
                settings: settings,
                tracePath: tracePath
            )
        } else {
            process.executableURL = URL(fileURLWithPath: settings.pythonPath)
            process.currentDirectoryURL = URL(fileURLWithPath: settings.repoPath)
            process.environment = settings.environment()
            process.arguments = buildArguments(
                task: task,
                settings: settings,
                tracePath: tracePath
            )
        }
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            DispatchQueue.main.async {
                self?.consumeStdout(text)
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            DispatchQueue.main.async {
                self?.consumeStderr(text)
            }
        }

        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                self?.process = nil
                self?.stdinPipe = nil
                self?.isRunning = false
                self?.pendingApproval = nil
                self?.hideAgentPointer()
                if process.terminationStatus != 0 && self?.lastResult == nil {
                    self?.progress.phaseTitle = "Needs attention"
                    self?.progress.phaseDetail = "The agent process exited with code \(process.terminationStatus)."
                    let msg = RunnerMessage(
                        title: "Agent exited",
                        detail: "Exit code \(process.terminationStatus)",
                        level: .warning
                    )
                    self?.append(msg)
                    self?.lastResult = msg
                }
            }
        }

        do {
            try process.run()
            self.process = process
            self.stdinPipe = stdin
        } catch {
            isRunning = false
            progress.phaseTitle = "Could not start"
            progress.phaseDetail = error.localizedDescription
            let msg = RunnerMessage(
                title: "Could not start Python",
                detail: error.localizedDescription,
                level: .error
            )
            append(msg)
            lastResult = msg
        }
    }

    func stop() {
        guard let process else { return }
        process.interrupt()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            if process.isRunning {
                kill(pid, SIGTERM)
            }
        }
        self.process = nil
        self.stdinPipe = nil
        isRunning = false
        pendingApproval = nil
        progress.phaseTitle = "Stopped"
        progress.phaseDetail = nil
        progress.currentAction = nil
        hideAgentPointer()
        lastWhisper = nil
    }

    func steer(hint: String) {
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingHint = trimmed
        let payload: [String: Any] = [
            "event": "user_hint",
            "hint": trimmed
        ]
        if
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let text = String(data: data, encoding: .utf8)
        {
            stdinPipe?.fileHandleForWriting.write(Data((text + "\n").utf8))
        }
        append(RunnerMessage(title: "Hint", detail: trimmed, level: .info))
    }

    func clearHint() {
        pendingHint = nil
    }

    func clear() {
        messages.removeAll()
        progress = RunnerProgress.empty
        lastResult = nil
        currentTask = nil
        pendingApproval = nil
        hideAgentPointer()
    }

    func respondToPendingApproval(approved: Bool) {
        guard let pendingApproval else { return }

        let payload: [String: Any] = [
            "event": "action_approval_response",
            "request_id": pendingApproval.id,
            "approved": approved
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let text = String(data: data, encoding: .utf8)
        else {
            return
        }

        let responseData = Data((text + "\n").utf8)
        let shouldRestoreFocus = approved && pendingApproval.requiresForegroundFocus
        let writeResponse = { [weak self] in
            self?.stdinPipe?.fileHandleForWriting.write(responseData)
        }

        self.pendingApproval = nil
        progress.phaseTitle = approved ? "Approved" : "Skipped"
        progress.phaseDetail = approved
            ? "Executing \(Self.displayName(forAction: pendingApproval.action))"
            : "Odin will choose another path"

        if shouldRestoreFocus {
            Self.restoreFocus(to: pendingApproval.focusOwnerProcessIdentifier)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                writeResponse()
            }
        } else {
            writeResponse()
        }
    }

    private func append(_ message: RunnerMessage) {
        messages.append(message)
        if messages.count > 200 {
            messages.removeFirst(messages.count - 200)
        }
    }

    private func buildArguments(
        task: String,
        settings: AppSettings,
        tracePath: String
    ) -> [String] {
        var args = [
            "-u",
            "-m", "odin.app_runner",
            "--task", task,
            "--provider", settings.provider.rawValue,
            "--max-steps", String(settings.maxSteps),
            "--max-batch-actions", String(settings.maxBatchActions),
            "--trace-path", tracePath
        ]

        let model = settings.effectiveModel
        args.append(contentsOf: ["--model", model])

        if settings.traceScreenshots {
            args.append("--trace-screenshots")
        }

        if settings.requireActionApproval {
            args.append("--require-action-approval")
        }

        return args
    }



    private func consumeStdout(_ text: String) {
        stdoutBuffer += text
        let lines = stdoutBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        guard let last = lines.last else { return }
        stdoutBuffer = String(last)

        for line in lines.dropLast() {
            handleJSONLine(String(line))
        }
    }

    private func consumeStderr(_ text: String) {
        stderrBuffer += text
        let lines = stderrBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        guard let last = lines.last else { return }
        stderrBuffer = String(last)

        for line in lines.dropLast() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.contains("NotOpenSSLWarning") || trimmed.contains("urllib3") {
                continue
            }
            append(
                RunnerMessage(title: "Python", detail: trimmed, level: .warning)
            )
        }
    }

    private func handleJSONLine(_ line: String) {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = object["event"] as? String
        else {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                append(RunnerMessage(title: "Output", detail: trimmed, level: .info))
            }
            return
        }

        let payload = object["data"] as? [String: Any] ?? [:]
        let step = (object["step"] as? Int) ?? 0

        switch event {
        case "run_started":
            progress.phaseTitle = "Starting"
            progress.phaseDetail = payload["task"] as? String
            append(RunnerMessage(title: "Started", detail: nil, level: .info))
        case "step_started":
            if step > 0 {
                progress.step = step
            }
            progress.phaseTitle = "Looking at the screen"
            progress.phaseDetail = "Capturing the current app state"
            progress.currentAction = nil
        case "llm_request_started":
            progress.phaseTitle = "Planning next step"
            progress.phaseDetail = "Choosing what to do next"
            progress.currentAction = nil
        case "actions_parsed":
            if let actions = payload["actions"] as? [[String: Any]], !actions.isEmpty {
                let names = actions.compactMap { $0["action"] as? String }
                let thoughts = actions.compactMap { $0["thought"] as? String }
                if let thought = thoughts.first(where: { !$0.isEmpty }) {
                    progress.lastThought = thought
                    progress.phaseDetail = thought
                    lastWhisper = thought
                }
                if let firstAction = names.first {
                    progress.lastAction = firstAction
                    progress.currentAction = Self.displayName(forAction: firstAction)
                }
                progress.phaseTitle = "Ready to act"
                let detail = names.joined(separator: ", ")
                append(
                    RunnerMessage(
                        title: "Step \(progress.step) plan",
                        detail: detail.isEmpty ? nil : detail,
                        level: .info
                    )
                )
            }
        case "llm_response_received":
            if isRunning {
                progress.phaseTitle = "Ready to act"
            }
            updateUsage(payload)
        case "action_execution_started":
            handleActionExecutionStarted(payload)
        case "action_approval_requested":
            handleActionApprovalRequested(payload, step: step)
        case "action_approval_received":
            let approved = payload["approved"] as? Bool ?? false
            append(
                RunnerMessage(
                    title: approved ? "Action approved" : "Action skipped",
                    detail: payload["action"] as? String,
                    level: approved ? .success : .warning
                )
            )
        case "action_executed":
            let message = payload["message"] as? String
            let success = payload["success"] as? Bool ?? false
            let actionName = payload["action"] as? String ?? "action"
            if success {
                progress.actionsExecuted += 1
                progress.phaseTitle = Self.completedTitle(forAction: actionName)
                progress.phaseDetail = progress.lastThought ?? message
            } else {
                progress.phaseTitle = "Action failed"
                progress.phaseDetail = message ?? payload["error"] as? String
            }
            progress.currentAction = Self.displayName(forAction: actionName)
            append(
                RunnerMessage(
                    title: success ? actionName : "\(actionName) failed",
                    detail: message ?? payload["error"] as? String,
                    level: success ? .success : .error
                )
            )
        case "action_validation_failed":
            append(
                RunnerMessage(
                    title: "Action rejected",
                    detail: payload["error"] as? String,
                    level: .warning
                )
            )
        case "action_blocked":
            append(
                RunnerMessage(
                    title: "Action blocked",
                    detail: payload["error"] as? String,
                    level: .warning
                )
            )
        case "parse_error":
            append(
                RunnerMessage(
                    title: "Parse error",
                    detail: payload["error"] as? String,
                    level: .warning
                )
            )
        case "task_done":
            let success = payload["success"] as? Bool ?? false
            let result = RunnerMessage(
                title: success ? "Done" : "Stopped",
                detail: payload["message"] as? String,
                level: success ? .success : .warning
            )
            progress.phaseTitle = result.title
            progress.phaseDetail = result.detail
            progress.currentAction = nil
            hideAgentPointer()
            lastWhisper = nil
            append(result)
            lastResult = result
            NotificationManager.shared.notifyTaskCompleted(
                success: success, message: result.detail
            )
        case "app_runner_error", "llm_error", "unexpected_error", "screenshot_error":
            let detail: String?
            if let message = payload["message"] as? String {
                detail = message
            } else if let err = payload["error"] as? [String: Any], let msg = err["message"] as? String {
                detail = msg
            } else {
                detail = payload["error"] as? String
            }
            let readableDetail = Self.userFacingError(detail)
            let msg = RunnerMessage(
                title: "Agent error",
                detail: readableDetail,
                level: .error
            )
            progress.phaseTitle = "Needs attention"
            progress.phaseDetail = readableDetail
            progress.currentAction = nil
            hideAgentPointer()
            lastWhisper = nil
            append(msg)
            lastResult = msg
            NotificationManager.shared.notifyError(detail: readableDetail)
        case "app_runner_finished", "run_finished":
            let success = payload["success"] as? Bool ?? false
            if lastResult == nil {
                let msg = RunnerMessage(
                    title: success ? "Done" : "Stopped",
                    detail: payload["message"] as? String,
                    level: success ? .success : .warning
                )
                append(msg)
                lastResult = msg
            }
            progress.phaseTitle = success ? "Done" : "Stopped"
            progress.phaseDetail = payload["message"] as? String
            progress.currentAction = nil
            hideAgentPointer()
            lastWhisper = nil
            if let totals = payload["llm_usage"] as? [String: Any] {
                applyUsageTotals(totals)
            }
        default:
            break
        }
    }

    private func handleActionExecutionStarted(_ payload: [String: Any]) {
        let actionName = payload["action"] as? String ?? "action"
        let thought = payload["thought"] as? String

        progress.phaseTitle = Self.activeTitle(forAction: actionName)
        progress.currentAction = Self.displayName(forAction: actionName)
        progress.lastAction = actionName
        if let thought, !thought.isEmpty {
            progress.lastThought = thought
            progress.phaseDetail = thought
            lastWhisper = thought
        } else {
            progress.phaseDetail = nil
            lastWhisper = Self.activeTitle(forAction: actionName)
        }
    }

    private func handleActionApprovalRequested(_ payload: [String: Any], step: Int) {
        let actionName = payload["action"] as? String ?? "action"
        let params = payload["params"] as? [String: Any] ?? [:]
        let target = payload["target"] as? [String: Any]
        let focusOwner = NSWorkspace.shared.frontmostApplication
        pendingApproval = PendingActionApproval(
            id: payload["request_id"] as? String ?? UUID().uuidString,
            step: step,
            batchIndex: payload["batch_index"] as? Int ?? 1,
            batchCount: payload["batch_count"] as? Int ?? 1,
            thought: payload["thought"] as? String,
            action: actionName,
            actionTitle: Self.approvalTitle(forAction: actionName, params: params),
            actionSubtitle: Self.approvalSubtitle(
                forAction: actionName,
                params: params,
                target: target
            ),
            detailChips: Self.approvalDetailChips(
                forAction: actionName,
                params: params,
                target: target
            ),
            focusOwnerProcessIdentifier: focusOwner?.processIdentifier
        )
        progress.phaseTitle = "Approval needed"
        progress.phaseDetail = payload["thought"] as? String
        progress.currentAction = Self.displayName(forAction: actionName)
        append(
            RunnerMessage(
                title: "Approval needed",
                detail: Self.displayName(forAction: actionName),
                level: .warning
            )
        )
    }

    private func updateUsage(_ payload: [String: Any]) {
        if let totals = payload["usage_totals"] as? [String: Any] {
            applyUsageTotals(totals)
        }
    }

    private func applyUsageTotals(_ totals: [String: Any]) {
        if let requests = totals["requests"] as? Int {
            progress.requests = requests
        }
        if let estimated = totals["cost_estimated"] as? Bool {
            progress.costEstimated = estimated
        }
        if let cost = totals["estimated_cost_usd"] as? Double {
            progress.costUSD = cost
        }
    }

    private func hideAgentPointer() {
        // No-op: pointer overlay removed
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? String {
            return Double(value)
        }
        return nil
    }

    private static func restoreFocus(to processIdentifier: pid_t?) {
        guard
            let processIdentifier,
            processIdentifier != pid_t(ProcessInfo.processInfo.processIdentifier),
            let app = NSRunningApplication(processIdentifier: processIdentifier)
        else {
            return
        }

        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private static func activeTitle(forAction action: String) -> String {
        switch action {
        case "click", "click_element":
            return "Clicking"
        case "double_click", "double_click_element":
            return "Double-clicking"
        case "press_element":
            return "Pressing"
        case "focus_element":
            return "Focusing"
        case "set_text", "type":
            return "Typing"
        case "hotkey":
            return "Sending shortcut"
        case "scroll", "scroll_element":
            return "Scrolling"
        case "move":
            return "Moving pointer"
        case "wait":
            return "Waiting"
        default:
            return "Acting"
        }
    }

    private static func completedTitle(forAction action: String) -> String {
        switch action {
        case "click", "click_element":
            return "Clicked"
        case "double_click", "double_click_element":
            return "Double-clicked"
        case "press_element":
            return "Pressed"
        case "focus_element":
            return "Focused"
        case "set_text", "type":
            return "Typed"
        case "hotkey":
            return "Sent shortcut"
        case "scroll", "scroll_element":
            return "Scrolled"
        case "move":
            return "Moved pointer"
        case "wait":
            return "Waited"
        default:
            return "Action complete"
        }
    }

    private static func userFacingError(_ detail: String?) -> String? {
        guard let detail, !detail.isEmpty else {
            return detail
        }
        if detail.contains("Could not connect to the endpoint URL")
            && detail.contains("bedrock-runtime") {
            return "Could not reach AWS Bedrock. Check network access, AWS credentials, region, and model access."
        }
        return detail
    }

    private static func displayName(forAction action: String) -> String {
        switch action {
        case "click":
            return "Click"
        case "click_element":
            return "Click element"
        case "double_click":
            return "Double click"
        case "double_click_element":
            return "Double click element"
        case "press_element":
            return "Press element"
        case "focus_element":
            return "Focus element"
        case "set_text":
            return "Set text"
        case "type":
            return "Type"
        case "hotkey":
            return "Shortcut"
        case "scroll":
            return "Scroll"
        case "scroll_element":
            return "Scroll element"
        case "move":
            return "Move pointer"
        case "wait":
            return "Wait"
        default:
            return action
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    private static func approvalTitle(
        forAction action: String,
        params: [String: Any]
    ) -> String {
        switch action {
        case "hotkey":
            let keys = stringArray(params["keys"])
            return keys.isEmpty ? "Press shortcut" : "Press \(formatKeys(keys))"
        case "type":
            return "Type \(quoted(params["text"]))"
        case "set_text":
            return "Set text to \(quoted(params["text"]))"
        case "click":
            return "Click at \(point(params))"
        case "double_click":
            return "Double-click at \(point(params))"
        case "move":
            return "Move pointer to \(point(params))"
        case "scroll":
            return "Scroll \(params["direction"] as? String ?? "")"
                .trimmingCharacters(in: .whitespaces)
        case "wait":
            return "Wait \(params["seconds"] ?? "")s"
        case "click_element":
            return "Click element \(params["element_id"] ?? "")"
        case "double_click_element":
            return "Double-click element \(params["element_id"] ?? "")"
        case "press_element":
            return "Press element \(params["element_id"] ?? "")"
        case "focus_element":
            return "Focus element \(params["element_id"] ?? "")"
        case "scroll_element":
            return "Scroll element \(params["element_id"] ?? "")"
        default:
            return displayName(forAction: action)
        }
    }

    private static func approvalSubtitle(
        forAction action: String,
        params: [String: Any],
        target: [String: Any]?
    ) -> String? {
        if let source = target?["source"] as? String {
            if let x = doubleValue(target?["x"]), let y = doubleValue(target?["y"]) {
                return "\(source.capitalized) target at \(Int(x)), \(Int(y))"
            }
            return "\(source.capitalized) target"
        }

        if action == "type" || action == "set_text" {
            return "Text entry"
        }
        if action == "hotkey" {
            return "Keyboard shortcut"
        }
        if let elementID = params["element_id"] as? String {
            return "Accessibility element \(elementID)"
        }
        return nil
    }

    private static func approvalDetailChips(
        forAction action: String,
        params: [String: Any],
        target: [String: Any]?
    ) -> [String] {
        var chips = [displayName(forAction: action)]

        if let button = params["button"] as? String {
            chips.append(button.capitalized)
        }
        if let amount = params["amount"] {
            chips.append("Amount \(amount)")
        }
        if let target, let source = target["source"] as? String {
            chips.append(source.capitalized)
        }
        if let elementID = params["element_id"] as? String {
            chips.append(elementID)
        }
        return chips
    }

    private static func stringArray(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { $0 as? String }
    }

    private static func formatKeys(_ keys: [String]) -> String {
        keys.map { key in
            switch key.lowercased() {
            case "command", "cmd":
                return "⌘"
            case "shift":
                return "⇧"
            case "option", "alt":
                return "⌥"
            case "control", "ctrl":
                return "⌃"
            case "return", "enter":
                return "Return"
            case "space":
                return "Space"
            case "escape", "esc":
                return "Esc"
            case "tab":
                return "Tab"
            default:
                return key.capitalized
            }
        }.joined(separator: " ")
    }

    private static func quoted(_ value: Any?) -> String {
        guard let text = value as? String, !text.isEmpty else { return "text" }
        let shortened = text.count > 72 ? String(text.prefix(69)) + "..." : text
        return "“\(shortened)”"
    }

    private static func point(_ params: [String: Any]) -> String {
        let x = params["x"].map { String(describing: $0) } ?? "?"
        let y = params["y"].map { String(describing: $0) } ?? "?"
        return "\(x), \(y)"
    }

    private func makeTracePath(repoPath: String, isBundled: Bool) -> String {
        let traces: URL
        if isBundled || repoPath.isEmpty {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            traces = appSupport.appendingPathComponent("Odin/Traces")
        } else {
            traces = URL(fileURLWithPath: repoPath).appendingPathComponent(".traces")
        }
        try? FileManager.default.createDirectory(at: traces, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "app-\(formatter.string(from: Date())).jsonl"
        return traces.appendingPathComponent(filename).path
    }
}
