import AppKit
import ServiceManagement
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var monitor: SessionMonitor
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !monitor.hooksInstalled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Claude Code hooks aren't installed yet, so no sessions will show up.")
                        .font(.caption)
                    Button("Install Hooks") { monitor.installHooks() }
                        .controlSize(.small)
                }
                .padding(8)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            }

            if monitor.sessions.isEmpty {
                Text("No active Claude Code sessions")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        VStack(spacing: 10) {
                            ForEach(monitor.sessions) { session in
                                SessionRowView(session: session, now: context.date)
                                    .contentShape(Rectangle())
                                    .contextMenu { actions(for: session) }
                            }
                        }
                    }
                }
                .frame(maxHeight: 380)
            }

            if let error = monitor.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack {
                Toggle("Open at Login", isOn: $opensAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: opensAtLogin) { _, enabled in setOpensAtLogin(enabled) }
                Spacer()
                if monitor.hooksInstalled {
                    Button("Reinstall Hooks") { monitor.installHooks() }
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 360)
    }

    private var header: some View {
        HStack {
            Text("Claude Code").font(.headline)
            Spacer()
            let awaiting = monitor.awaitingCount
            Text(awaiting == 0 ? "Nothing waiting on you" : "\(awaiting) waiting on you")
                .font(.caption)
                .foregroundStyle(awaiting == 0 ? Color.secondary : Color.orange)
        }
    }

    @ViewBuilder
    private func actions(for session: SessionSummary) -> some View {
        if !session.cwd.isEmpty {
            Button("Show Folder in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.cwd)
            }
            Button("Copy Resume Command") {
                let command = "cd \(shellQuoted(session.cwd)) && claude --resume \(session.id)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
        }
        Button("Dismiss") { monitor.dismiss(session) }
    }

    private func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            opensAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
