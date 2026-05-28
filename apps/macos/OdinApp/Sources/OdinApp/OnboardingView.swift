import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var permissions: PermissionManager

    var body: some View {
        VStack(spacing: 0) {
            hero

            VStack(alignment: .leading, spacing: 14) {
                PermissionRow(
                    title: "Screen Recording",
                    description: "So Odin can see what's on your display.",
                    symbol: "rectangle.dashed.badge.record",
                    iconColors: [OdinStyle.accent, OdinStyle.accentSecondary],
                    granted: permissions.hasScreenRecording,
                    onAction: {
                        PermissionManager.requestScreenRecording()
                        PermissionManager.openScreenRecordingSettings()
                    }
                )

                PermissionRow(
                    title: "Accessibility",
                    description: "So Odin can click, type, and read interface elements.",
                    symbol: "accessibility",
                    iconColors: [OdinStyle.accentSecondary, OdinStyle.accent],
                    granted: permissions.hasAccessibility,
                    onAction: {
                        PermissionManager.requestAccessibility()
                        PermissionManager.openAccessibilitySettings()
                    }
                )
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 24)

            Rectangle()
                .fill(OdinStyle.separator)
                .frame(height: 0.5)

            HStack {
                Button("Refresh") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        permissions.refresh()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OdinStyle.secondaryInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .scaleOnHover()

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        permissions.refresh()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(permissions.allGranted ? "Continue" : "Waiting…")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                        if permissions.allGranted {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 120, height: 32)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!permissions.allGranted)
                .opacity(permissions.allGranted ? 1 : 0.45)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 520)
        .background(
            NotchShape(cornerRadius: OdinStyle.panelRadius)
                .fill(OdinStyle.background)
        )
        .overlay(
            NotchBorder(cornerRadius: OdinStyle.panelRadius)
                .stroke(OdinStyle.warmCream.opacity(0.08), lineWidth: 0.7)
        )
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: permissions.allGranted)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: permissions.hasScreenRecording)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: permissions.hasAccessibility)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(OdinStyle.accent.opacity(0.08))
                    .frame(width: 96, height: 96)

                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(OdinStyle.accent)
                    .frame(width: 72, height: 72)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            }

            VStack(spacing: 4) {
                Text("Welcome to Odin")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(OdinStyle.ink)
                Text("Grant two system permissions to get started.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(OdinStyle.secondaryInk)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
    }
}

private struct PermissionRow: View {
    let title: String
    let description: String
    let symbol: String
    let iconColors: [Color]
    let granted: Bool
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.02))
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )

                Image(systemName: granted ? "checkmark" : symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(granted ? OdinStyle.green : OdinStyle.accentSecondary)
            }

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
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Granted")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(OdinStyle.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(OdinStyle.green.opacity(0.08)))
                .overlay(Capsule().strokeBorder(OdinStyle.green.opacity(0.22), lineWidth: 0.5))
            } else {
                Button(action: onAction) {
                    Text("Grant")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(.brandGlass)
                .controlSize(.regular)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: OdinStyle.cardRadius, style: .continuous)
                .fill(OdinStyle.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OdinStyle.cardRadius, style: .continuous)
                .strokeBorder(OdinStyle.cardStroke, lineWidth: 0.5)
        )
        .scaleOnHover()
    }
}
