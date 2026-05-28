import SwiftUI
import AppKit

struct StatusMenu: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var runner: AgentRunner
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(OdinStyle.separator).frame(height: 0.5)
            actions
            Rectangle().fill(OdinStyle.separator).frame(height: 0.5)
            modelInfo
            Rectangle().fill(OdinStyle.separator).frame(height: 0.5)
            footer
        }
        .frame(width: 240)
        .background(OdinStyle.background.opacity(0.85))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(runner.isRunning ? OdinStyle.accent.opacity(0.12) : Color.white.opacity(0.04))
                    .frame(width: 28, height: 28)
                Image(systemName: "circle.hexagongrid")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(runner.isRunning ? OdinStyle.brandGradient : LinearGradient(colors: [OdinStyle.ink.opacity(0.74)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 15, height: 15)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Odin")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OdinStyle.ink)
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(OdinStyle.secondaryInk)
                    .lineLimit(1)
            }

            Spacer()

            if runner.isRunning {
                Circle()
                    .fill(OdinStyle.brandGradient)
                    .frame(width: 6, height: 6)
                    .shadow(color: OdinStyle.accent.opacity(0.8), radius: 3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.toggleMainWindow()
                }
            } label: {
                Label("Show Odin", systemImage: "command")
            }
            .buttonStyle(StatusMenuButtonStyle())

            if runner.isRunning {
                Button {
                    runner.stop()
                } label: {
                    Label("Stop Current Task", systemImage: "stop.fill")
                }
                .buttonStyle(StatusMenuButtonStyle())
            }

            if runner.latestMessage != nil {
                Button {
                    runner.clear()
                } label: {
                    Label("Clear Status", systemImage: "trash")
                }
                .buttonStyle(StatusMenuButtonStyle())
            }
        }
        .padding(6)
    }

    private var modelInfo: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.provider.displayName)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(OdinStyle.ink)
                Text(settings.modelLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(OdinStyle.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings…", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(StatusMenuButtonStyle())

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Odin", systemImage: "power")
            }
            .buttonStyle(StatusMenuButtonStyle())
        }
        .padding(6)
    }

    private var statusLine: String {
        if runner.isRunning {
            return runner.progress.currentAction ?? runner.progress.phaseTitle
        }
        if let last = runner.lastResult {
            return last.level == .success ? "Finished" : "Needs attention"
        }
        return "Ready"
    }
}

struct StatusMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(OdinStyle.secondaryInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Color.white.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
            .scaleOnHover(scale: 1.01)
    }
}
