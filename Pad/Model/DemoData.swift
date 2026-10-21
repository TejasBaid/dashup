import DashUpKit
import Foundation

/// Sample data matching the mockups. Used with the `-demo` launch argument and in previews.
enum DemoData {
    static func load(into model: AppModel) {
        let now = Date.now
        model.status = .connected
        model.macName = "Tejas’s Mac mini"
        let ask = PermissionAsk(id: "demo-ask", sessionID: "s1", toolName: "Bash",
                                subject: "xcodebuild -scheme DashUpPad -sdk iphonesimulator build",
                                cwd: "/Users/tejas/conductor/workspaces/DashUp/medan",
                                createdAt: now.addingTimeInterval(-16), expiresAt: now.addingTimeInterval(29))
        model.claude = ClaudeState(sessions: [
            ClaudeSession(id: "s1", pid: 1, name: "medan-6c", cwd: "/Users/tejas/conductor/workspaces/DashUp/medan",
                          project: "DashUp / medan", isConductor: true, phase: .needsApproval,
                          phaseSince: now.addingTimeInterval(-16), startedAt: now.addingTimeInterval(-18 * 60),
                          title: "Add vitals ring to Home", lastPrompt: "Add the TickRing to Home and make sure the iPad target builds.",
                          lastMessage: "Tests pass. Building the iPad target in the simulator to confirm everything compiles.",
                          model: "claude-opus-5-5", branch: "medan/46lf2", contextTokens: 82_000,
                          timeline: timeline(now), filesChanged: [
                            FileChange(path: "Pad/Features/Home/HomeView.swift", written: false),
                            FileChange(path: "Pad/DesignSystem/TickRing.swift", written: true),
                            FileChange(path: "Pad/Features/Home/VitalsCard.swift", written: false),
                          ], steps: 34),
            ClaudeSession(id: "s2", pid: 2, name: "boston-40", cwd: "/Users/tejas/conductor/workspaces/ConductorLink/boston",
                          project: "ConductorLink / boston", isConductor: true, phase: .working,
                          phaseSince: now.addingTimeInterval(-12 * 60), startedAt: now.addingTimeInterval(-40 * 60),
                          title: "Resume reconnects from the last snapshot",
                          lastMessage: "Refactoring the bridge so reconnects resume the last snapshot instead of refetching.",
                          activity: "Editing Link/Bridge.swift", model: "claude-opus-5-5", contextTokens: 64_000,
                          filesChanged: [FileChange(path: "Sources/Link/Bridge.swift", written: false)], steps: 48),
            ClaudeSession(id: "s4", pid: 4, name: "seoul-12", cwd: "/Users/tejas/conductor/workspaces/DashUp/seoul",
                          project: "DashUp / seoul", isConductor: true, phase: .waiting,
                          phaseSince: now.addingTimeInterval(-2 * 60), startedAt: now.addingTimeInterval(-25 * 60),
                          title: "Add pairing by QR code",
                          lastMessage: "Should the QR code expire with the 6-digit code after 5 minutes, or stay valid until it's used once?",
                          model: "claude-sonnet-5-5", contextTokens: 41_000,
                          filesChanged: [FileChange(path: "Pad/Features/Pairing/PairingView.swift", written: false),
                                         FileChange(path: "Mac/Server/PeerServer.swift", written: false)], steps: 19),
            ClaudeSession(id: "s3", pid: 3, name: "api-cleanup", cwd: "/Users/tejas/Desktop/Projects/api",
                          project: "api", isConductor: false, phase: .finished,
                          phaseSince: now.addingTimeInterval(-4 * 60), startedAt: now.addingTimeInterval(-38 * 60),
                          title: "Remove the legacy auth middleware",
                          lastMessage: "All 48 tests pass. I removed the legacy auth middleware and updated the README.",
                          model: "claude-sonnet-5-5", contextTokens: 182_000,
                          filesChanged: [FileChange(path: "src/middleware/auth.ts", written: false), FileChange(path: "README.md", written: false)], steps: 61),
        ], pending: ProcessInfo.processInfo.arguments.contains("-calm") ? [] : [ask], hooksInstalled: true, recent: [
            ClaudeSession(id: "r1", pid: 0, name: "api-cleanup", cwd: "", project: "api", isConductor: false, phase: .idle,
                          phaseSince: now.addingTimeInterval(-2 * 3600), startedAt: now.addingTimeInterval(-3 * 3600), title: "Fix favicon cache on reconnect"),
            ClaudeSession(id: "r2", pid: 0, name: "dashup-docs", cwd: "", project: "DashUp", isConductor: false, phase: .idle,
                          phaseSince: now.addingTimeInterval(-3 * 3600), startedAt: now.addingTimeInterval(-4 * 3600), title: "Write the hooks section of the README"),
            ClaudeSession(id: "r3", pid: 0, name: "boston-39", cwd: "", project: "ConductorLink", isConductor: true, phase: .idle,
                          phaseSince: now.addingTimeInterval(-5 * 3600), startedAt: now.addingTimeInterval(-6 * 3600), title: "Reconnect bridge without refetching"),
        ])
        if ProcessInfo.processInfo.arguments.contains("-calm") {
            model.claude.sessions[0].phase = .finished
            model.claude.sessions[0].phaseSince = now.addingTimeInterval(-6 * 60)
        }

        model.apps = AppsState(running: [
            RunningApp(bundleID: "com.apple.dt.Xcode", name: "Xcode", pid: 1, isFront: true, isHidden: false, windowCount: 1, caption: "1 window", memoryBytes: 3_400_000_000),
            RunningApp(bundleID: "com.google.Chrome", name: "Chrome", pid: 2, isFront: false, isHidden: false, windowCount: 3, caption: "23 tabs", memoryBytes: 2_100_000_000),
            RunningApp(bundleID: "com.conductor.app", name: "Conductor", pid: 3, isFront: false, isHidden: false, windowCount: 1, caption: "3 sessions", memoryBytes: 860_000_000),
            RunningApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty", pid: 4, isFront: false, isHidden: false, windowCount: 2, caption: "2 windows", memoryBytes: 212_000_000),
            RunningApp(bundleID: "com.apple.MobileSMS", name: "Messages", pid: 5, isFront: false, isHidden: false, windowCount: 1, memoryBytes: 140_000_000),
            RunningApp(bundleID: "com.apple.Music", name: "Music", pid: 6, isFront: false, isHidden: false, windowCount: 1, caption: "Playing", memoryBytes: 190_000_000),
        ], installed: [
            ("com.apple.ActivityMonitor", "Activity Monitor"), ("com.apple.AppStore", "App Store"), ("com.apple.calculator", "Calculator"),
            ("com.apple.iCal", "Calendar"), ("com.google.Chrome", "Chrome"), ("com.conductor.app", "Conductor"),
            ("com.apple.FaceTime", "FaceTime"), ("com.apple.finder", "Finder"), ("com.mitchellh.ghostty", "Ghostty"),
            ("com.apple.mail", "Mail"), ("com.apple.Maps", "Maps"), ("com.apple.MobileSMS", "Messages"),
            ("com.apple.Music", "Music"), ("com.apple.Notes", "Notes"), ("com.apple.Photos", "Photos"),
            ("com.apple.Preview", "Preview"), ("com.apple.reminders", "Reminders"), ("com.apple.Safari", "Safari"),
            ("com.apple.shortcuts", "Shortcuts"), ("com.apple.systempreferences", "System Settings"), ("com.apple.Terminal", "Terminal"),
            ("net.whatsapp.WhatsApp", "WhatsApp"), ("com.apple.dt.Xcode", "Xcode"),
        ].map { InstalledApp(bundleID: $0.0, name: $0.1) })

        let tabs: [(String, String)] = [
            ("tejasbaid/dashup · Pull Request #12", "https://github.com/tejasbaid/dashup/pull/12"),
            ("NWListener | Apple Developer Documentation", "https://developer.apple.com/documentation/network/nwlistener"),
            ("Hooks reference — Claude Code Docs", "https://code.claude.com/docs/en/hooks"),
            ("DSH-41 Approve permissions from iPad", "https://linear.app/dashup/issue/DSH-41"),
            ("DashUp — iPad dashboard v3", "https://www.figma.com/file/dashup"),
            ("Designing Fluid Interfaces — WWDC18", "https://www.youtube.com/watch?v=1"),
            ("dashup-site · Deployments", "https://vercel.com/tejas/dashup-site"),
            ("Inbox (3)", "https://mail.google.com/mail/u/0/"),
            ("Swift Concurrency: Actors and Sendable", "https://www.swift.org/documentation/concurrency/"),
            ("Show HN: I turned my iPad into a Mac dashboard", "https://news.ycombinator.com/item?id=1"),
        ]
        model.chrome = ChromeState(isRunning: true, windows: [
            ChromeWindow(id: 1, tabs: tabs.prefix(6).enumerated().map { ChromeTab(id: $0.offset + 1, title: $0.element.0, url: $0.element.1) }, activeTabIndex: 1),
            ChromeWindow(id: 2, tabs: tabs.dropFirst(6).enumerated().map { ChromeTab(id: $0.offset + 10, title: $0.element.0, url: $0.element.1) }, activeTabIndex: 2),
        ])

        model.nowPlaying = NowPlayingState(app: "Music", bundleID: "com.apple.Music", isRunning: true, state: .playing, trackID: "demo",
                                           title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming",
                                           duration: 243, position: 96, positionDate: now, volume: 62)

        model.pad = PadState(pages: [
            PadPage(id: "dev", title: "Dev", sections: [
                PadSection(id: "modes", title: "Modes", style: .modes, items: [
                    PadItem(id: "awake", title: "Stay awake", isToggle: true, isOn: true, stateText: "1h 58m left"),
                    PadItem(id: "dark", title: "Dark mode", isToggle: true, isOn: true, stateText: "On"),
                    PadItem(id: "mic", title: "Mute mic", isToggle: true, stateText: "Live"),
                    PadItem(id: "sound", title: "Mute sound", isToggle: true, stateText: "On"),
                ]),
                PadSection(id: "project", title: "DashUp", subtitle: "~/Desktop/Projects/DashUp", style: .keys, items: [
                    PadItem(id: "tests", title: "Run tests", context: "swift test", lastRunAt: now.addingTimeInterval(-120), lastResult: "48 passed", lastSucceeded: true),
                    PadItem(id: "build", title: "Build iPad app", context: "xcodebuild", isRunning: true, runningSince: now.addingTimeInterval(-42)),
                    PadItem(id: "pr", title: "Open pull request", subtitle: "#12 · 2 reviews", context: "gh pr view --web"),
                    PadItem(id: "pull", title: "Pull & rebase", subtitle: "main", context: "git pull --rebase"),
                    PadItem(id: "claude", title: "New Claude session", subtitle: "Opens Conductor", usesClaudeMark: true),
                    PadItem(id: "xcode", title: "Open in Xcode", subtitle: "DashUp.xcodeproj", appBundleID: "com.apple.dt.Xcode"),
                    PadItem(id: "localhost", title: "localhost:3000", subtitle: "Opens in Chrome", appBundleID: "com.google.Chrome"),
                    PadItem(id: "sha", title: "Copy last commit", context: "git rev-parse"),
                ]),
                PadSection(id: "mac", title: "Mac", style: .compact, items: [
                    PadItem(id: "lock", title: "Lock", keycaps: ["⌃", "⌘", "Q"]),
                    PadItem(id: "sleep", title: "Sleep display", subtitle: "Wakes on input"),
                    PadItem(id: "shot", title: "Screenshot", keycaps: ["⇧", "⌘", "4"]),
                    PadItem(id: "mc", title: "Mission Control", keycaps: ["⌃", "↑"]),
                    PadItem(id: "desktop", title: "Show desktop", subtitle: "Moves windows aside"),
                    PadItem(id: "trash", title: "Empty Trash", subtitle: "Asks first", needsConfirmation: true),
                ]),
            ]),
        ])
    }

    private static func timeline(_ now: Date) -> [TimelineItem] {
        [
            TimelineItem(id: "0", kind: .prompt, date: now.addingTimeInterval(-60 * 60), text: "Set up the iPad project with a design system."),
            TimelineItem(id: "0a", kind: .tool, date: now.addingTimeInterval(-59 * 60), text: "Wrote", detail: "Pad/DesignSystem/Theme.swift", toolName: "Write"),
            TimelineItem(id: "0b", kind: .tool, date: now.addingTimeInterval(-58 * 60), text: "Ran", detail: "xcodegen generate", toolName: "Bash"),
            TimelineItem(id: "1", kind: .prompt, date: now.addingTimeInterval(-18 * 60), text: "Add the TickRing to Home and make sure the iPad target builds."),
            TimelineItem(id: "2", kind: .text, date: now.addingTimeInterval(-16 * 60), text: "I'll add a reusable TickRing view, wire it into the Home screen, then build to verify."),
            TimelineItem(id: "3", kind: .tool, date: now.addingTimeInterval(-16 * 60), text: "Read", detail: "Pad/Features/Home/HomeView.swift", toolName: "Read"),
            TimelineItem(id: "4", kind: .tool, date: now.addingTimeInterval(-15 * 60), text: "Wrote", detail: "Pad/DesignSystem/TickRing.swift", toolName: "Write"),
            TimelineItem(id: "5", kind: .tool, date: now.addingTimeInterval(-14 * 60), text: "Edited", detail: "Pad/Features/Home/HomeView.swift", toolName: "Edit"),
            TimelineItem(id: "6", kind: .tool, date: now.addingTimeInterval(-3 * 60), text: "Ran", detail: "swift test --filter TickRing", toolName: "Bash"),
            TimelineItem(id: "7", kind: .text, date: now.addingTimeInterval(-20), text: """
                Tests pass. Building the iPad target in the simulator to confirm everything compiles.

                What changed:
                - New `TickRing` view in **Pad/DesignSystem**
                - Home's vitals card now uses it, with the legend underneath
                - Six snapshot tests cover 0%, 50% and 100%
                """),
        ]
    }
}
