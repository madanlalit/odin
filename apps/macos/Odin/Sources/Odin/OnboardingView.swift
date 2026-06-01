import SwiftUI
import AppKit

/// Onboarding — three calm steps that turn first-time setup into a
/// product moment, not a checklist.
struct OnboardingView: View {
    @EnvironmentObject private var permissions: PermissionManager
    @EnvironmentObject private var settings: AppSettings
    @SwiftUI.State private var step: Step = .welcome

    enum Step: Int, CaseIterable, Identifiable {
        case welcome = 0
        case permissions
        case tour
        var id: Int { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            progressDots
                .padding(.top, OdinTokens.Space.s16)
                .padding(.bottom, OdinTokens.Space.s8)

            Group {
                switch step {
                case .welcome:     welcomeStep
                case .permissions: permissionsStep
                case .tour:        tourStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .move(edge: .trailing)))

            Hairline()
            footer
        }
        .frame(width: 560, height: 460)
        .odinPanelSurface()
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
        .animation(OdinMotion.current.rise, value: step)
        .animation(OdinMotion.current.snap, value: permissions.allGranted)
    }

    // MARK: - Progress dots

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue
                          ? OdinTokens.Color.amber
                          : OdinTokens.Color.hairline)
                    .frame(width: s == step ? 18 : 6, height: 4)
                    .animation(OdinMotion.current.snap, value: step)
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: OdinTokens.Space.s20) {
            Spacer()
            OdinEye(state: .watching, size: 64)
            VStack(spacing: OdinTokens.Space.s8) {
                Text("Welcome to Odin")
                    .font(OdinTokens.Font.display)
                    .foregroundStyle(OdinTokens.Color.ink)
                Text("Your watchful companion for the Mac.")
                    .font(OdinTokens.Font.body)
                    .foregroundStyle(OdinTokens.Color.ink2)
            }
            VStack(alignment: .leading, spacing: OdinTokens.Space.s10) {
                FeatureRow(symbol: "eye", title: "Sees your screen", detail: "Odin captures context the way you do.")
                FeatureRow(symbol: "wand.and.stars", title: "Reasons, then acts", detail: "Plans, clicks, types — all by your hand.")
                FeatureRow(symbol: "lock.shield", title: "Always on your side", detail: "Approve actions. Step away. Take it back.")
            }
            .padding(.horizontal, OdinTokens.Space.s40)
            Spacer()
        }
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(spacing: OdinTokens.Space.s20) {
            Spacer().frame(height: OdinTokens.Space.s12)
            VStack(spacing: OdinTokens.Space.s6) {
                Text("Two permissions")
                    .font(OdinTokens.Font.title)
                    .foregroundStyle(OdinTokens.Color.ink)
                Text("Odin needs to see your screen and control your Mac to act on your behalf.")
                    .font(OdinTokens.Font.body)
                    .foregroundStyle(OdinTokens.Color.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OdinTokens.Space.s40)
            }
            VStack(spacing: OdinTokens.Space.s10) {
                PermissionRow(
                    title: "Screen Recording",
                    description: "Odin captures the display to understand what you're looking at.",
                    symbol: "rectangle.dashed.badge.record",
                    granted: permissions.hasScreenRecording,
                    onAction: openScreenRecording
                )
                PermissionRow(
                    title: "Accessibility",
                    description: "Odin clicks, types, and reads interface elements on your behalf.",
                    symbol: "accessibility",
                    granted: permissions.hasAccessibility,
                    onAction: openAccessibility
                )
            }
            .padding(.horizontal, OdinTokens.Space.s40)
            Spacer()
        }
    }

    // MARK: - Step 3: Tour

    private var tourStep: some View {
        VStack(spacing: OdinTokens.Space.s20) {
            Spacer().frame(height: OdinTokens.Space.s8)
            VStack(spacing: OdinTokens.Space.s6) {
                Text("Three quick gestures")
                    .font(OdinTokens.Font.title)
                    .foregroundStyle(OdinTokens.Color.ink)
                Text("Odin lives in your menu bar. Summon it from anywhere.")
                    .font(OdinTokens.Font.body)
                    .foregroundStyle(OdinTokens.Color.ink2)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: OdinTokens.Space.s14) {
                TourRow(
                    number: "1",
                    title: "Press your hotkey",
                    detail: "\(compactHotkeyString) brings Odin to your cursor from any app."
                )
                TourRow(
                    number: "2",
                    title: "Type what you want",
                    detail: "Plain language. 'Plan my week', 'Find todos in Mail', 'Summarize this tab'."
                )
                TourRow(
                    number: "3",
                    title: "Watch the eye",
                    detail: "Amber means Odin is working. Approve when it asks. Take it back anytime."
                )
            }
            .padding(.horizontal, OdinTokens.Space.s40)
            Spacer()
        }
    }

    // MARK: - Footer (next/back buttons)

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") {
                    withAnimation(OdinMotion.current.rise) {
                        if let prev = Step(rawValue: step.rawValue - 1) { step = prev }
                    }
                }
                .buttonStyle(.odinText)
            } else {
                Spacer()
            }
            Spacer()
            primaryButton
        }
        .padding(.horizontal, OdinTokens.Space.s20)
        .padding(.vertical, OdinTokens.Space.s12)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .welcome:
            Button("Get started") {
                withAnimation(OdinMotion.current.rise) { step = .permissions }
            }
            .buttonStyle(.odinPrimary)
            .frame(width: 180)
        case .permissions:
            Button(permissions.allGranted ? "Continue" : "Grant both") {
                if !permissions.hasScreenRecording { openScreenRecording() }
                if !permissions.hasAccessibility   { openAccessibility() }
                if permissions.allGranted {
                    withAnimation(OdinMotion.current.rise) { step = .tour }
                }
            }
            .buttonStyle(.odinPrimary)
            .frame(width: 180)
            .disabled(!permissions.allGranted)
            .opacity(permissions.allGranted ? 1 : 0.55)
        case .tour:
            Button("Finish") {
                withAnimation(OdinMotion.current.rise) {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.showMainWindow()
                    }
                }
            }
            .buttonStyle(.odinPrimary)
            .frame(width: 180)
        }
    }

    // MARK: - Helpers

    private var compactHotkeyString: String {
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(settings.hotkeyModifiers))
        return HotkeyFormatter.modifierSymbols(modifierFlags)
            + HotkeyFormatter.symbol(for: UInt16(settings.hotkeyKeyCode))
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

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: OdinTokens.Space.s12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(OdinTokens.Color.amber)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(OdinTokens.Font.bodyEm)
                    .foregroundStyle(OdinTokens.Color.ink)
                Text(detail)
                    .font(OdinTokens.Font.body)
                    .foregroundStyle(OdinTokens.Color.ink2)
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let description: String
    let symbol: String
    let granted: Bool
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: OdinTokens.Space.s12) {
            ZStack {
                RoundedRectangle(cornerRadius: OdinTokens.R.card, style: .continuous)
                    .fill(OdinTokens.Color.surfaceRaised)
                    .frame(width: 38, height: 38)
                Image(systemName: granted ? "checkmark" : symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(granted ? OdinTokens.Color.success : OdinTokens.Color.amber)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(OdinTokens.Font.bodyEm)
                    .foregroundStyle(OdinTokens.Color.ink)
                Text(description)
                    .font(OdinTokens.Font.caption)
                    .foregroundStyle(OdinTokens.Color.ink2)
                    .lineLimit(2)
            }
            Spacer()
            if granted {
                OdinChip(text: "Granted", style: .success, height: 22)
            } else {
                Button("Grant", action: onAction)
                    .buttonStyle(.odinSoft)
            }
        }
        .padding(OdinTokens.Space.s12)
        .background(
            RoundedRectangle(cornerRadius: OdinTokens.R.card, style: .continuous)
                .fill(OdinTokens.Color.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OdinTokens.R.card, style: .continuous)
                .stroke(
                    granted ? OdinTokens.Color.success.opacity(0.25) : OdinTokens.Color.hairline,
                    lineWidth: 0.5
                )
        )
        .animation(OdinMotion.current.snap, value: granted)
    }
}

private struct TourRow: View {
    let number: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: OdinTokens.Space.s12) {
            Text(number)
                .font(OdinTokens.Font.caption)
                .foregroundStyle(OdinTokens.Color.amber)
                .frame(width: 20, height: 20)
                .background(
                    Circle().fill(OdinTokens.Color.amberSoft)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(OdinTokens.Font.bodyEm)
                    .foregroundStyle(OdinTokens.Color.ink)
                Text(detail)
                    .font(OdinTokens.Font.body)
                    .foregroundStyle(OdinTokens.Color.ink2)
                    .lineLimit(2)
            }
        }
    }
}
