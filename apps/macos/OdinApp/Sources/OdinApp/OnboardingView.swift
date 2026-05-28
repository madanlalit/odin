import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var permissions: PermissionManager

    var body: some View {
        VStack(spacing: 0) {
            hero

            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(
                    title: "Screen Recording",
                    description: "So Odin can see what's on your display.",
                    symbol: "rectangle.dashed.badge.record",
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
                    granted: permissions.hasAccessibility,
                    onAction: {
                        PermissionManager.requestAccessibility()
                        PermissionManager.openAccessibilitySettings()
                    }
                )
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 24)

            Divider()

            HStack {
                Button("Refresh") { permissions.refresh() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OdinStyle.secondaryInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                Spacer()

                Button {
                    permissions.refresh()
                } label: {
                    HStack(spacing: 6) {
                        Text(permissions.allGranted ? "Continue" : "Waiting…")
                            .font(.system(size: 12, weight: .semibold))
                        if permissions.allGranted {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .frame(width: 120, height: 30)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!permissions.allGranted)
                .opacity(permissions.allGranted ? 1 : 0.55)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 520)
        .glassSurface(cornerRadius: OdinStyle.panelRadius)
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: permissions.allGranted)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: permissions.hasScreenRecording)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: permissions.hasAccessibility)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(OdinStyle.accent)
                .frame(width: 72, height: 72)
                .glassEffect(.regular, in: .circle)

            VStack(spacing: 4) {
                Text("Welcome to Odin")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(OdinStyle.ink)
                Text("Grant two permissions to get started.")
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
    let granted: Bool
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: granted ? "checkmark" : symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(granted ? OdinStyle.green : OdinStyle.secondaryInk)
                .frame(width: 38, height: 38)
                .glassEffect(.regular, in: .rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
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
                Button(action: onAction) {
                    Text("Grant")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
                .controlSize(.regular)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: OdinStyle.cardRadius))
    }
}
