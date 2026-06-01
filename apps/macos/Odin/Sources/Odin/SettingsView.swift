import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var permissions: PermissionManager
    @State private var apiKey = ""
    @State private var awsAccessKeyId = ""
    @State private var awsSecretKey = ""
    @State private var awsSessionToken = ""
    @State private var savedFlash = false
    @State private var savedAwsCredentials = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Top margin to avoid overlapping with window control buttons (traffic lights)
                Spacer().frame(height: 16)

                Text("Odin Settings")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(OdinStyle.ink)
                    .padding(.bottom, -8)

                generalPane
                modelPane
                permissionsPane
                advancedPane
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 520, height: 600)
        .glassSurface(cornerRadius: OdinStyle.panelRadius)
        .onAppear {
            apiKey = settings.apiKey()
            awsAccessKeyId = settings.awsAccessKeyId()
            awsSecretKey = settings.awsSecretAccessKey()
            awsSessionToken = settings.awsSessionToken()
            permissions.startPolling()

            DispatchQueue.main.async {
                if let window = NSApp.windows.first(where: {
                    $0.title == "Odin Settings" ||
                    $0.identifier?.rawValue == "Settings" ||
                    $0.className.contains("SettingsWindow") ||
                    ($0.contentView?.subviews.first?.description.contains("SettingsView") ?? false)
                }) {
                    window.isOpaque = false
                    window.backgroundColor = .clear
                    window.titlebarAppearsTransparent = true
                    window.titleVisibility = .hidden
                    window.hasShadow = true
                }
            }
        }
        .onDisappear {
            permissions.stopPolling()
        }
        .onChange(of: settings.provider) { _, _ in
            apiKey = settings.apiKey()
            awsAccessKeyId = settings.awsAccessKeyId()
            awsSecretKey = settings.awsSecretAccessKey()
            awsSessionToken = settings.awsSessionToken()
        }
    }

    private func settingsSectionHeader(title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(OdinStyle.accent)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(OdinStyle.secondaryInk)
            }
        }
        .padding(.bottom, 2)
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsSectionHeader(
                title: "General",
                subtitle: "Provider, credentials, and how Odin connects to your model."
            )

            groupCard {
                rowSegmented(
                    label: "Provider",
                    selection: $settings.provider,
                    options: Provider.allCases.map { ($0, $0.displayName) }
                )

                rowDivider

                HStack(spacing: 12) {
                    rowLabel("API Key")
                    SecureField(settings.provider == .openrouter ? "sk-or-…" : "API Key / Token", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveKey)
                    primaryActionButton(
                        title: savedFlash ? "Saved" : "Save",
                        isDisabled: apiKey.isEmpty,
                        action: saveKey
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if settings.provider == .bedrock {
                    rowDivider

                    HStack(spacing: 12) {
                        rowLabel("AWS Region")
                        TextField("us-east-1", text: $settings.awsRegion)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    rowDivider

                    VStack(alignment: .leading, spacing: 10) {
                        Text("AWS CREDENTIALS (KEYCHAIN)")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(OdinStyle.tertiaryInk)
                            .tracking(0.8)
                            .padding(.top, 4)

                        HStack(spacing: 12) {
                            rowLabel("Access Key ID")
                            SecureField("AWS_ACCESS_KEY_ID", text: $awsAccessKeyId)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 12) {
                            rowLabel("Secret Key")
                            SecureField("AWS_SECRET_ACCESS_KEY", text: $awsSecretKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 12) {
                            rowLabel("Session Token")
                            SecureField("AWS_SESSION_TOKEN (Optional)", text: $awsSessionToken)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Spacer()
                            primaryActionButton(
                                title: savedAwsCredentials ? "Saved" : "Save AWS Credentials",
                                isDisabled: awsAccessKeyId.isEmpty && awsSecretKey.isEmpty,
                                action: saveAwsCredentialsAction
                            )
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                rowDivider

                HStack(spacing: 12) {
                    rowLabel("Status")
                    HStack(spacing: 6) {
                        Circle()
                            .fill(credentialsConfigured ? OdinStyle.accent : OdinStyle.tertiaryInk)
                            .frame(width: 7, height: 7)
                        Text(credentialsConfigured ? "Ready" : "Needs configuration")
                            .font(.system(size: 12))
                            .foregroundStyle(OdinStyle.secondaryInk)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                rowDivider

                ShortcutRecorderView()
            }

            footnote("Keys and secrets are stored securely in macOS Keychain.")
        }
    }

    private var credentialsConfigured: Bool {
        switch settings.provider {
        case .openrouter:
            return !settings.apiKey().isEmpty
        case .bedrock:
            return !settings.awsRegion.isEmpty && (!settings.awsAccessKeyId().isEmpty || !settings.apiKey().isEmpty)
        }
    }

    private var modelPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsSectionHeader(
                title: "Model",
                subtitle: "Pick the vision-capable model Odin uses to reason about the screen."
            )

            groupCard {
                HStack(spacing: 12) {
                    rowLabel("Model ID")
                    TextField(defaultModelHint, text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                rowDivider

                HStack(spacing: 12) {
                    rowLabel("Effective")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.modelAlias)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(OdinStyle.ink)
                        Text(settings.effectiveModel)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(OdinStyle.secondaryInk)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("SUGGESTED MODELS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(OdinStyle.tertiaryInk)
                    .tracking(0.8)
                    .padding(.top, 4)
                
                VStack(spacing: 6) {
                    ForEach(settings.suggestedModels) { suggestion in
                        suggestedModelRow(suggestion)
                    }
                }
            }
        }
    }

    private func suggestedModelRow(_ suggestion: AppSettings.ModelSuggestion) -> some View {
        let isSelected = settings.effectiveModel == suggestion.modelID
        return Button {
            settings.model = suggestion.modelID
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.alias)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(isSelected ? OdinStyle.ink : OdinStyle.secondaryInk)
                    Text(suggestion.modelID)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(OdinStyle.tertiaryInk)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(OdinStyle.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? OdinStyle.accent.opacity(0.06) : OdinStyle.warmCream.opacity(0.02))
            )
            .glassEffect(.regular, in: .rect(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? OdinStyle.accent.opacity(0.24) : OdinStyle.cardStroke, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var defaultModelHint: String {
        switch settings.provider {
        case .openrouter: return "google/gemini-2.0-flash-001"
        case .bedrock: return "us.anthropic.claude-opus-4-7"
        }
    }

    private var permissionsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsSectionHeader(
                title: "Permissions",
                subtitle: "Odin needs to see your screen and control your Mac to operate."
            )

            groupCard {
                permissionRow(
                    title: "Screen Recording",
                    description: "Lets Odin capture screenshots of what you're looking at.",
                    granted: permissions.hasScreenRecording,
                    onGrant: PermissionManager.requestScreenRecording,
                    onSettings: PermissionManager.openScreenRecordingSettings
                )
                rowDivider
                permissionRow(
                    title: "Accessibility",
                    description: "Lets Odin click, type, and read interface elements.",
                    granted: permissions.hasAccessibility,
                    onGrant: PermissionManager.requestAccessibility,
                    onSettings: PermissionManager.openAccessibilitySettings
                )
            }

            footnote("Granting permissions opens System Settings. Status updates automatically once you toggle them on.")
        }
    }

    private func permissionRow(
        title: String,
        description: String,
        granted: Bool,
        onGrant: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: granted ? "checkmark" : "exclamationmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(granted ? OdinStyle.accent : OdinStyle.tertiaryInk)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(granted ? OdinStyle.accent.opacity(0.12) : OdinStyle.warmCream.opacity(0.04))
                )
                .overlay(
                    Circle()
                        .strokeBorder(granted ? OdinStyle.accent.opacity(0.3) : OdinStyle.warmCream.opacity(0.08), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OdinStyle.ink)
                Text(description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(OdinStyle.secondaryInk)
            }

            Spacer()

            if granted {
                Text("Granted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OdinStyle.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(OdinStyle.accent.opacity(0.12))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(OdinStyle.accent.opacity(0.3), lineWidth: 0.5)
                    )
            } else {
                primaryActionButton(title: "Grant", isDisabled: false) {
                    onGrant(); onSettings()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var advancedPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsSectionHeader(
                title: "Advanced",
                subtitle: "Limits, safety, and tracing for power users."
            )

            groupCard {
                advancedStepper(label: "Max steps", value: $settings.maxSteps, range: 1...500)
                rowDivider
                advancedStepper(label: "Max actions / batch", value: $settings.maxBatchActions, range: 1...20)
                rowDivider
                rowToggle(label: "Confirm every action", isOn: $settings.requireActionApproval)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("TRACING")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(OdinStyle.tertiaryInk)
                    .tracking(0.8)
                    .padding(.top, 4)

                groupCard {
                    HStack(spacing: 12) {
                        rowLabel("Working Directory")
                        Text(abbreviatedRepoPath)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(OdinStyle.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { pickFolder(into: $settings.repoPath) }
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    rowDivider

                    rowToggle(label: "Save screenshots with traces", isOn: $settings.traceScreenshots)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("CUSTOM ENVIRONMENT VARIABLES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(OdinStyle.tertiaryInk)
                    .tracking(0.8)
                    .padding(.top, 4)

                groupCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add custom environment variables (e.g. KEY=VALUE), one per line:")
                            .font(.system(size: 11))
                            .foregroundStyle(OdinStyle.secondaryInk)
                        TextEditor(text: $settings.customEnv)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 80)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(OdinStyle.warmCream.opacity(0.1), lineWidth: 0.5)
                            )
                    }
                    .padding(16)
                }
            }

            HStack {
                Spacer()
                Text("Odin · v0.6.0")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(OdinStyle.tertiaryInk)
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(OdinStyle.tertiaryInk)
            .padding(.horizontal, 4)
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .frame(width: 120, alignment: .leading)
            .foregroundStyle(OdinStyle.secondaryInk)
    }

    private func groupCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(OdinStyle.warmCream.opacity(0.02))
            )
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(OdinStyle.cardStroke, lineWidth: 0.5)
            )
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(OdinStyle.separator)
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    private func rowSegmented<T: Hashable>(
        label: String,
        selection: Binding<T>,
        options: [(T, String)]
    ) -> some View {
        HStack(spacing: 12) {
            rowLabel(label)
            Picker("", selection: selection) {
                ForEach(options, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func advancedStepper(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(OdinStyle.secondaryInk)
            Spacer()
            Text("\(value.wrappedValue)")
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(OdinStyle.ink)
                .frame(width: 48, alignment: .trailing)
            Stepper("", value: value, in: range)
                .labelsHidden()
                .frame(width: 50)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func rowToggle(label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(OdinStyle.secondaryInk)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func primaryActionButton(
        title: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 4)
        }
        .buttonStyle(.brandGlass)
        .controlSize(.regular)
        .disabled(isDisabled)
    }

    private var abbreviatedRepoPath: String {
        let home = NSHomeDirectory()
        if settings.repoPath.hasPrefix(home) {
            return settings.repoPath.replacingOccurrences(of: home, with: "~")
        }
        return settings.repoPath
    }

    private func saveKey() {
        settings.setAPIKey(apiKey)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            savedFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                savedFlash = false
            }
        }
    }

    private func saveAwsCredentialsAction() {
        settings.setAwsAccessKeyId(awsAccessKeyId)
        settings.setAwsSecretAccessKey(awsSecretKey)
        settings.setAwsSessionToken(awsSessionToken)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            savedAwsCredentials = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                savedAwsCredentials = false
            }
        }
    }

    private func pickFolder(into binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
        }
    }
}

struct ShortcutRecorderView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var isRecording = false
    @State private var localMonitor: Any? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text("Global Hotkey")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(OdinStyle.secondaryInk)
                .frame(width: 120, alignment: .leading)
            
            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                Text(isRecording ? "Press shortcut keys..." : shortcutString)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(minWidth: 160)
            }
            .buttonStyle(.brandGlass)
            .controlSize(.regular)
            
            if isRecording {
                Text("Press Esc to cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(OdinStyle.tertiaryInk)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onDisappear {
            stopRecording()
        }
    }

    private var shortcutString: String {
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(settings.hotkeyModifiers))
        let parts = HotkeyFormatter.modifierVerbose(modifierFlags)
        return (parts + [HotkeyFormatter.name(for: UInt16(settings.hotkeyKeyCode))])
            .joined(separator: " + ")
    }

    private func startRecording() {
        isRecording = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if keyCode == 53 { // Esc
                stopRecording()
                return nil
            }

            if modifiers.isEmpty {
                return nil
            }

            settings.hotkeyKeyCode = Int(keyCode)
            settings.hotkeyModifiers = Int(modifiers.rawValue)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}
