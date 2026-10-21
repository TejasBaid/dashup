import DashUpKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let agent = Agent()

    func applicationDidFinishLaunching(_ notification: Notification) {
        agent.start()
    }
}

@main
struct DashUpMacApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(agent: delegate.agent)
        } label: {
            Image(systemName: delegate.agent.pendingCount > 0 ? "rectangle.badge.checkmark" : "rectangle.bottomhalf.inset.filled")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuContent: View {
    @Bindable var agent: Agent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 10)
            pairing
            Divider().padding(.vertical, 10)
            claude
            Divider().padding(.vertical, 10)
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Open at login", isOn: $agent.launchAtLogin)
                    .toggleStyle(.checkbox)
                HStack {
                    Button("Edit Pad…") { agent.editPad() }
                    Spacer()
                    Button("Quit DashUp") { NSApp.terminate(nil) }
                }
            }
            if let error = agent.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DashUp").font(.headline)
            HStack(spacing: 6) {
                Circle()
                    .fill(agent.connectedDevices.isEmpty ? Color.secondary.opacity(0.5) : Color.green)
                    .frame(width: 7, height: 7)
                Text(agent.connectedDevices.isEmpty ? "No iPad connected" : agent.connectedDevices.joined(separator: ", ") + " connected")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private var pairing: some View {
        if let code = agent.pairingCode {
            VStack(alignment: .leading, spacing: 6) {
                Text("Enter this code on your iPad").font(.callout).foregroundStyle(.secondary)
                Text(code.map(String.init).joined(separator: " "))
                    .font(.system(size: 30, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    if let expires = agent.pairingExpires {
                        Text("Expires \(expires, style: .relative)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cancel") { agent.stopPairing() }
                }
            }
        } else {
            HStack {
                Text("iPad").foregroundStyle(.secondary)
                Spacer()
                Button("Pair an iPad…") { agent.startPairing() }
            }
        }
    }

    private var claude: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Claude Code").foregroundStyle(.secondary)
                Spacer()
                Text(agent.sessionCount == 1 ? "1 session" : "\(agent.sessionCount) sessions").foregroundStyle(.secondary)
            }
            if agent.hooksInstalled {
                HStack {
                    Label(agent.hookServerRunning ? "Approvals from iPad are on" : "Hook server isn't running",
                          systemImage: agent.hookServerRunning ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.callout)
                    Spacer()
                    Button("Turn off") { agent.uninstallHooks() }
                }
            } else {
                Text("Adds HTTP hooks to ~/.claude/settings.json so sessions report live activity and ask for approval on your iPad. Your existing hooks are kept and the file is backed up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Connect Claude Code") { agent.installHooks() }
            }
        }
    }
}
