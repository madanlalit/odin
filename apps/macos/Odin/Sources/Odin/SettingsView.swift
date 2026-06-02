import SwiftUI
import AppKit

/// Odin Settings — one focused window, four logical sections, all using
/// the unified `OdinField` / `OdinSegmentedPicker` / `OdinToggle` family.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var permissions: PermissionManager

    @SwiftUI.State private var apiKey: String = ""
    @SwiftUI.State private var awsAccessKeyId: String = ""
    @SwiftUI.State private var awsSecretKey: String = ""
    @SwiftUI.State private var awsSessionToken: String = ""
    @SwiftUI.State private var savedFlash: Bool = false
    @SwiftUI.State private var savedAwsCredentials: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OdinTokens.Space.s24) {
                Spacer().frame(height: OdinTokens.Space.s20)

                hero

                generalPane
                modelPane
                permissionsPane
                advancedPane

                footer
            }
            .padding(.horizontal, OdinTokens.Space.s24)
            .padding(.bottom, OdinTokens.Space.s24)
        }
        .frame(width: 560, height: 640)
        .odinPanelSurface(radius: OdinTokens.R.window)
        .onAppear { onAppear() }
        .onDisappear { permissions.stopPolling() }
        .onChange(of: settings.provider) { _, _ in syncKeysFromKeychain() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: OdinTokens.Space.s4) {
            HStack(spacing: OdinTokens.Space.s10) {
                OdinEye(state: .idle, size: 28, animated: false)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Odin Settings")
                        .font(OdinTokens.Font.hero)
                        .foregroundStyle(OdinTokens.Color.ink)
                    Text("Shape how Odin watches and acts.")
                        .font(OdinTokens.Font.body)
                        .foregroundStyle(OdinTokens.Color.ink2)
                }
                Spacer()
                OdinChip(
                    text: "v0.6.0",
                    style: .neutral,
                    mono: true,
                    height: 22
                )
            }
        }
    }

    // MARK: - General

    private var generalPane: some View {
        section("General", subtitle: "Provider, credentials, and how Odin connects to your model.") {
            VStack(spacing: 0) {
                row {
                    OdinRowLabel(text: "Provider")
                    OdinSegmentedPicker(
                        selection: $settings.provider,
                        options: Provider.allCases,
                        label: { Text($0.displayName) }
                    )
                    Spacer()
                }
                hairline()
                row {
                    OdinRowLabel(text: "API Key")
                    OdinField(
                        placeholder: settings.provider == .openrouter ? "sk-or-…" : "API Key / Token",
                        text: $apiKey,
                        secure: true,
                        onSubmit: saveKey
                    )
                    saveButton(title: savedFlash ? "Saved" : "Save",
                               enabled: !apiKey.isEmpty,
                               action: saveKey)
                }
                if settings.provider == .bedrock {
                    hairline()
                    row {
                        OdinRowLabel(text: "AWS Region")
                        OdinField(placeholder: "us-east-1", text: $settings.awsRegion)
                        Spacer()
                    }
                    hairline()
                    awsCredentialsBlock
                }
                hairline()
                row {
                    OdinRowLabel(text: "Status")
                    HStack(spacing: 6) {
                        OdinDot(color: credentialsConfigured
                                ? OdinTokens.Color.success
                                : OdinTokens.Color.amber, size: 7)
                        Text(credentialsConfigured ? "Ready" : "Needs configuration")
                            .font(OdinTokens.Font.body)
                            .foregroundStyle(OdinTokens.Color.ink2)
                    }
                    Spacer()
                }
                hairline()
                row {
                    OdinRowLabel(text: "Global Hotkey")
                    ShortcutRecorderView()
                    Spacer()
                }
            }
            .odinCard()
            footnote("Keys and secrets are stored securely in macOS Keychain.")
        }
    }

    private var awsCredentialsBlock: some View {
        VStack(alignment: .leading, spacing: OdinTokens.Space.s8) {
            Text("AWS CREDENTIALS")
                .font(OdinTokens.Font.micro)
                .foregroundStyle(OdinTokens.Color.ink3)
                .padding(.top, OdinTokens.Space.s4)
            HStack {
                OdinRowLabel(text: "Access Key ID", width: 132)
                OdinField(placeholder: "AWS_ACCESS_KEY_ID", text: $awsAccessKeyId, secure: true)
            }
            HStack {
                OdinRowLabel(text: "Secret Key", width: 132)
                OdinField(placeholder: "AWS_SECRET_ACCESS_KEY", text: $awsSecretKey, secure: true)
            }
            HStack {
                OdinRowLabel(text: "Session Token", width: 132)
                OdinField(placeholder: "AWS_SESSION_TOKEN (Optional)", text: $awsSessionToken, secure: true)
            }
            HStack {
                Spacer()
                saveButton(title: savedAwsCredentials ? "Saved" : "Save AWS Credentials",
                           enabled: !awsAccessKeyId.isEmpty || !awsSecretKey.isEmpty,
                           action: saveAwsCredentials)
            }
            .padding(.top, OdinTokens.Space.s4)
        }
        .padding(.horizontal, OdinTokens.Space.s16)
        .padding(.vertical, OdinTokens.Space.s12)
    }

    // MARK: - Model

    private var modelPane: some View {
        section("Model", subtitle: "Pick the vision-capable model Odin uses to reason about the screen.") {
            VStack(spacing: 0) {
                row {
                    OdinRowLabel(text: "Model ID")
                    OdinField(placeholder: defaultModelHint, text: $settings.model, mono: true)
                    Spacer()
                }
                hairline()
                row {
                    OdinRowLabel(text: "Effective")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.modelAlias)
                            .font(OdinTokens.Font.bodyEm)
                            .foregroundStyle(OdinTokens.Color.ink)
                        Text(settings.effectiveModel)
                            .font(OdinTokens.Font.mono)
                            .foregroundStyle(OdinTokens.Color.ink2)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
            }
            .odinCard()
            if !settings.suggestedModels.isEmpty {
                Text("SUGGESTED MODELS")
                    .font(OdinTokens.Font.micro)
                    .foregroundStyle(OdinTokens.Color.ink3)
                    .padding(.top, OdinTokens.Space.s8)
                VStack(spacing: OdinTokens.Space.s6) {
                    ForEach(settings.suggestedModels) { suggestion in
                        suggestedModelRow(suggestion)
                    }
                }
            }
        }
    }

    // MARK: - Permissions

    private var permissionsPane: some View {
        section("Permissions", subtitle: "Odin needs to see your screen and control your Mac to operate.") {
            VStack(spacing: 0) {
                permissionRow(
                    title: "Screen Recording",
                    description: "Lets Odin capture screenshots of what you're looking at.",
                    granted: permissions.hasScreenRecording,
                    onAction: openScreenRecording
                )
                hairline()
                permissionRow(
                    title: "Accessibility",
                    description: "Lets Odin click, type, and read interface elements.",
                    granted: permissions.hasAccessibility,
                    onAction: openAccessibility
                )
            }
            .odinCard()
            footnote("Granting permissions opens System Settings. Status updates automatically once you toggle them on.")
        }
    }

    // MARK: - Advanced

    private var advancedPane: some View {
        section("Advanced", subtitle: "Limits, safety, tracing, and accessibility preferences.") {
            VStack(spacing: 0) {
                row {
                    OdinRowLabel(text: "Max steps")
                    Spacer()
                    stepperButton(value: $settings.maxSteps, in: 1...500)
                }
                hairline()
                row {
                    OdinRowLabel(text: "Max actions / batch")
                    Spacer()
                    stepperButton(value: $settings.maxBatchActions, in: 1...20)
                }
                hairline()
                row {
                    OdinRowLabel(text: "Confirm every action")
                    Spacer()
                    Toggle("", isOn: $settings.requireActionApproval)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(OdinTokens.Color.amber)
                        .controlSize(.small)
                }
                hairline()
                row {
                    OdinRowLabel(text: "Reduce motion")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { OdinMotion.reduceMotion },
                        set: { OdinMotion.reduceMotion = $0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(OdinTokens.Color.amber)
                    .controlSize(.small)
                }
            }
            .odinCard()

            subSection("TRACING", spacing: OdinTokens.Space.s6) {
                VStack(spacing: 0) {
                    row {
                        OdinRowLabel(text: "Working directory")
                        Text(abbreviatedRepoPath)
                            .font(OdinTokens.Font.mono)
                            .foregroundStyle(OdinTokens.Color.ink2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 220, alignment: .trailing)
                        Button("Choose…") { pickFolder(into: $settings.repoPath) }
                            .buttonStyle(.odinText)
                    }
                    hairline()
                    row {
                        OdinRowLabel(text: "Save screenshots with traces")
                        Spacer()
                        Toggle("", isOn: $settings.traceScreenshots)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(OdinTokens.Color.amber)
                            .controlSize(.small)
                    }
                }
                .odinCard()
            }

            subSection("CUSTOM ENVIRONMENT VARIABLES", spacing: OdinTokens.Space.s6) {
                VStack(alignment: .leading, spacing: OdinTokens.Space.s8) {
                    Text("Add KEY=VALUE pairs, one per line. Available to the agent at runtime.")
                        .font(OdinTokens.Font.body)
                        .foregroundStyle(OdinTokens.Color.ink2)
                    OdinTextArea(placeholder: "EXAMPLE_API_KEY=…", text: $settings.customEnv)
                }
                .padding(OdinTokens.Space.s14)
                .background(
                    RoundedRectangle(cornerRadius: OdinTokens.R.card, style: .continuous)
                        .fill(OdinTokens.Color.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OdinTokens.R.card, style: .continuous)
                        .stroke(OdinTokens.Color.hairline, lineWidth: 0.5)
                )
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Text("Built for macOS 26 · Liquid Glass")
                .font(OdinTokens.Font.mono)
                .foregroundStyle(OdinTokens.Color.ink4)
            Spacer()
        }
        .padding(.top, OdinTokens.Space.s12)
    }

    // MARK: - Helpers

    private var credentialsConfigured: Bool {
        switch settings.provider {
        case .openrouter:
            return !settings.apiKey().isEmpty
        case .bedrock:
            return !settings.awsRegion.isEmpty &&
                (!settings.awsAccessKeyId().isEmpty || !settings.apiKey().isEmpty)
        }
    }

    private var defaultModelHint: String {
        settings.defaultModelID
    }

    private var abbreviatedRepoPath: String {
        let home = NSHomeDirectory()
        if settings.repoPath.hasPrefix(home) {
            return settings.repoPath.replacingOccurrences(of: home, with: "~")
        }
        return settings.repoPath
    }

    // MARK: - Builders

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OdinTokens.Space.s10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(OdinTokens.Font.title)
                    .foregroundStyle(OdinTokens.Color.ink)
                Text(subtitle)
                    .font(OdinTokens.Font.body)
                    .foregroundStyle(OdinTokens.Color.ink2)
            }
            content()
        }
    }

    @ViewBuilder
    private func subSection<Content: View>(
        _ eyebrow: String,
        spacing: CGFloat,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(eyebrow)
                .font(OdinTokens.Font.micro)
                .foregroundStyle(OdinTokens.Color.ink3)
                .padding(.top, OdinTokens.Space.s4)
            content()
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: OdinTokens.Space.s12) {
            content()
        }
        .padding(.horizontal, OdinTokens.Space.s16)
        .padding(.vertical, OdinTokens.Space.s12)
    }

    private func hairline() -> some View {
        Rectangle()
            .fill(OdinTokens.Color.hairline)
            .frame(height: 0.5)
            .padding(.leading, OdinTokens.Space.s16)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(OdinTokens.Font.caption)
            .foregroundStyle(OdinTokens.Color.ink3)
            .padding(.horizontal, OdinTokens.Space.s4)
            .padding(.top, OdinTokens.Space.s2)
    }

    private func saveButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.odinSoft)
            .disabled(!enabled)
    }

    private func stepperButton(value: Binding<Int>, in range: ClosedRange<Int>) -> some View {
        HStack(spacing: OdinTokens.Space.s8) {
            Text("\(value.wrappedValue)")
                .font(OdinTokens.Font.mono)
                .foregroundStyle(OdinTokens.Color.ink)
                .frame(width: 40, alignment: .trailing)
            Stepper("", value: value, in: range)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private func permissionRow(
        title: String,
        description: String,
        granted: Bool,
        onAction: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: OdinTokens.Space.s12) {
            ZStack {
                Circle()
                    .fill(granted ? OdinTokens.Color.success.opacity(0.12) : OdinTokens.Color.surfaceRaised)
                    .frame(width: 32, height: 32)
                Image(systemName: granted ? "checkmark" : "exclamationmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(granted ? OdinTokens.Color.success : OdinTokens.Color.amber)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(OdinTokens.Font.bodyEm)
                    .foregroundStyle(OdinTokens.Color.ink)
                Text(description)
                    .font(OdinTokens.Font.caption)
                    .foregroundStyle(OdinTokens.Color.ink2)
            }
            Spacer()
            if granted {
                OdinChip(text: "Granted", style: .success, height: 22)
            } else {
                Button("Grant", action: onAction)
                    .buttonStyle(.odinSoft)
            }
        }
        .padding(.horizontal, OdinTokens.Space.s16)
        .padding(.vertical, OdinTokens.Space.s12)
    }

    private func suggestedModelRow(_ suggestion: AppSettings.ModelSuggestion) -> some View {
        let isSelected = settings.effectiveModel == suggestion.modelID
        return Button {
            settings.model = suggestion.modelID
        } label: {
            HStack(spacing: OdinTokens.Space.s10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.alias)
                        .font(OdinTokens.Font.bodyEm)
                        .foregroundStyle(isSelected ? OdinTokens.Color.ink : OdinTokens.Color.ink2)
                    Text(suggestion.modelID)
                        .font(OdinTokens.Font.mono)
                        .foregroundStyle(OdinTokens.Color.ink3)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(OdinTokens.Color.amber)
                }
            }
            .padding(.horizontal, OdinTokens.Space.s14)
            .padding(.vertical, OdinTokens.Space.s10)
            .background(
                RoundedRectangle(cornerRadius: OdinTokens.R.card, style: .continuous)
                    .fill(isSelected ? OdinTokens.Color.amberSoft : OdinTokens.Color.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OdinTokens.R.card, style: .continuous)
                    .stroke(isSelected ? OdinTokens.Color.amberLine : OdinTokens.Color.hairline,
                            lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lifecycle

    private func onAppear() {
        syncKeysFromKeychain()
        permissions.startPolling()
        DispatchQueue.main.async {
            for window in NSApp.windows where window.title == "Odin Settings"
                || window.identifier?.rawValue == "Settings"
                || window.className.contains("SettingsWindow")
                || (window.contentView?.subviews.first?.description.contains("SettingsView") ?? false) {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.hasShadow = true
            }
        }
    }

    private func syncKeysFromKeychain() {
        apiKey = settings.apiKey()
        awsAccessKeyId = settings.awsAccessKeyId()
        awsSecretKey = settings.awsSecretAccessKey()
        awsSessionToken = settings.awsSessionToken()
    }

    private func saveKey() {
        settings.setAPIKey(apiKey)
        withAnimation(OdinMotion.current.snap) { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(OdinMotion.current.snap) { savedFlash = false }
        }
    }

    private func saveAwsCredentials() {
        settings.setAwsAccessKeyId(awsAccessKeyId)
        settings.setAwsSecretAccessKey(awsSecretKey)
        settings.setAwsSessionToken(awsSessionToken)
        withAnimation(OdinMotion.current.snap) { savedAwsCredentials = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(OdinMotion.current.snap) { savedAwsCredentials = false }
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

    private func openScreenRecording() {
        PermissionManager.requestScreenRecording()
        PermissionManager.openScreenRecordingSettings()
    }
    private func openAccessibility() {
        PermissionManager.requestAccessibility()
        PermissionManager.openAccessibilitySettings()
    }
}

/// The hotkey recorder, ported to the new design language.
struct ShortcutRecorderView: View {
    @EnvironmentObject private var settings: AppSettings
    @SwiftUI.State private var isRecording: Bool = false
    @SwiftUI.State private var localMonitor: Any? = nil

    var body: some View {
        HStack(spacing: OdinTokens.Space.s8) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                HStack(spacing: OdinTokens.Space.s6) {
                    if isRecording {
                        OdinDot(color: OdinTokens.Color.amber, size: 6)
                    }
                    Text(isRecording ? "Press shortcut keys…" : shortcutString)
                        .font(OdinTokens.Font.mono)
                }
                .padding(.horizontal, OdinTokens.Space.s12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: OdinTokens.R.chip, style: .continuous)
                        .fill(isRecording ? OdinTokens.Color.amberSoft : OdinTokens.Color.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OdinTokens.R.chip, style: .continuous)
                        .stroke(isRecording ? OdinTokens.Color.amberLine : OdinTokens.Color.hairline,
                                lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            if isRecording {
                Text("Press Esc to cancel")
                    .font(OdinTokens.Font.caption)
                    .foregroundStyle(OdinTokens.Color.ink3)
            }
        }
        .onDisappear { stopRecording() }
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
            if keyCode == 53 {
                stopRecording()
                return nil
            }
            if modifiers.isEmpty { return nil }
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
