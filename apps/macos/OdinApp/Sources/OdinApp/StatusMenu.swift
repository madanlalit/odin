import SwiftUI
import AppKit

struct StatusMenu: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var runner: AgentRunner
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            actions
            Divider()
            modelInfo
            Divider()
            footer
        }
        .frame(width: 240)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(runner.isRunning ? OdinStyle.gold.opacity(0.16) : Color.primary.opacity(0.06))
                    .frame(width: 28, height: 28)
                Image(systemName: "circle.hexagongrid")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(runner.isRunning ? OdinStyle.gold : OdinStyle.ink.opacity(0.78))
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
                    .fill(OdinStyle.gold)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                openWindow(id: "chat")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Show Odin", systemImage: "command")
            }

            if runner.isRunning {
                Button {
                    runner.stop()
                } label: {
                    Label("Stop Current Task", systemImage: "stop.fill")
                }
            }

            if runner.latestMessage != nil {
                Button {
                    runner.clear()
                } label: {
                    Label("Clear Status", systemImage: "trash")
                }
            }
        }
    }

    private var modelInfo: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.provider.displayName)
                    .font(.system(size: 11.5, weight: .medium))
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
        VStack(alignment: .leading, spacing: 0) {
            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings…", systemImage: "slider.horizontal.3")
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Odin", systemImage: "power")
            }
        }
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
