import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var permissions: PermissionManager
    @State private var apiKey = ""
    @State private var savedFlash = false
    @State private var selection: Section = .general

    enum Section: String, CaseIterable, Identifiable {
        case general, model, permissions, advanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .model: return "Model"
            case .permissions: return "Permissions"
            case .advanced: return "Advanced"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .model: return "cpu"
            case .permissions: return "lock.shield"
            case .advanced: return "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .font(.system(size: 12.5, weight: .medium))
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 168, ideal: 180, max: 220)
        } detail: {
            ScrollView {
                Group {
                    switch selection {
                    case .general: generalPane
                    case .model: modelPane
                    case .permissions: permissionsPane
                    case .advanced: advancedPane
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 480)
        }
        .frame(width: 760, height: 520)
        .preferredColorScheme(.dark)
        .onAppear { apiKey = settings.apiKey() }
        .onChange(of: settings.provider) { _, _ in apiKey = settings.apiKey() }
    }


    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            paneHeader(
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

                if settings.provider == .openrouter {
                    HStack(spacing: 12) {
                        rowLabel("API Key")
                        SecureField("sk-or-…", text: $apiKey)
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
                } else {
                    HStack(spacing: 12) {
                        rowLabel("AWS Region")
                        TextField("us-east-1", text: $settings.awsRegion)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                rowDivider

                HStack(spacing: 12) {
                    rowLabel("Status")
                    HStack(spacing: 6) {
                        Circle()
                            .fill(credentialsConfigured ? OdinStyle.green : OdinStyle.tertiaryInk)
                            .frame(width: 7, height: 7)
                        Text(credentialsConfigured ? "Ready" : "Needs configuration")
                            .font(.system(size: 12))
                            .foregroundStyle(OdinStyle.secondaryInk)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            footnote("Keys are stored securely in macOS Keychain.")
        }
    }

    private var credentialsConfigured: Bool {
        switch settings.provider {
        case .openrouter: return !settings.apiKey().isEmpty
        case .bedrock: return !settings.awsRegion.isEmpty
        }
    }


    private var modelPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            paneHeader(
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
                    Text(settings.effectiveModel)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(OdinStyle.secondaryInk)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Suggested")
                VStack(spacing: 6) {
                    ForEach(suggestedModels, id: \.self) { model in
                        suggestedModelRow(model)
                    }
                }
            }
        }
    }

    private func suggestedModelRow(_ model: String) -> some View {
        let isSelected = settings.effectiveModel == model
        return Button {
            settings.model = model
        } label: {
            HStack(spacing: 10) {
                Text(model)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(isSelected ? OdinStyle.ink : OdinStyle.secondaryInk)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(OdinStyle.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 9))
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

    private var suggestedModels: [String] {
        switch settings.provider {
        case .openrouter:
            return [
                "google/gemini-2.0-flash-001",
                "anthropic/claude-opus-4.7",
                "anthropic/claude-sonnet-4.6",
            ]
        case .bedrock:
            return [
                "us.anthropic.claude-opus-4-7",
                "us.anthropic.claude-sonnet-4-6",
                "us.anthropic.claude-haiku-4-5",
            ]
        }
    }


    private var permissionsPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            paneHeader(
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
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
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
                .foregroundStyle(granted ? OdinStyle.green : OdinStyle.tertiaryInk)
                .frame(width: 30, height: 30)
                .glassEffect(.regular, in: .circle)

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
                    .foregroundStyle(OdinStyle.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: .capsule)
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
        VStack(alignment: .leading, spacing: 20) {
            paneHeader(
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

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Tracing")

                groupCard {
                    HStack(spacing: 12) {
                        rowLabel("Trace folder")
                        Text(abbreviatedTracePath)
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


    private func paneHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(OdinStyle.ink)
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(OdinStyle.secondaryInk)
        }
        .padding(.bottom, 4)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(OdinStyle.tertiaryInk)
            .tracking(0.8)
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
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
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
                .frame(width: 200, alignment: .leading)
                .foregroundStyle(OdinStyle.secondaryInk)
            Spacer()
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(OdinStyle.ink)
                    .frame(width: 48, alignment: .trailing)
            }
            .labelsHidden()
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
        .buttonStyle(.glass)
        .controlSize(.regular)
        .disabled(isDisabled)
    }

    private var abbreviatedTracePath: String {
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
