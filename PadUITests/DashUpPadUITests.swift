import XCTest

/// UI automation for DashUp on iPad. Driven by environment variables passed through xcodebuild as
/// `TEST_RUNNER_<NAME>=…`, so the same tests serve screenshots and end-to-end checks:
///
/// - `DASHUP_SHOTS`: directory to write screenshots into (`testScreenshots`).
/// - `DASHUP_PAIR_CODE`: pairing code the Mac agent is showing (`testPairAndApprove`).
@MainActor
final class DashUpPadUITests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    /// Captures every screen from demo data.
    func testScreenshots() throws {
        let directory = try XCTUnwrap(env["DASHUP_SHOTS"], "Set TEST_RUNNER_DASHUP_SHOTS")
        let shots: [(String, [String])] = [
            ("home", ["-screen", "home"]),
            ("claude", ["-screen", "claude"]),
            ("claude-detail", ["-screen", "claude", "-claudeDetail", "s1"]),
            ("tabs", ["-screen", "tabs"]),
            ("apps", ["-screen", "apps"]),
            ("media", ["-screen", "media"]),
            ("pad", ["-screen", "pad"]),
            ("settings", ["-screen", "settings"]),
            ("standby", ["-standby"]),
            ("standby-calm", ["-standby", "-calm"]),
        ]
        // With a background photo, when one is provided.
        let photo = env["DASHUP_BACKGROUND"].map { [("home-photo", ["-screen", "home", "-backgroundFile", $0]),
                                                      ("claude-photo", ["-screen", "claude"]),
                                                      ("pad-photo", ["-screen", "pad"])] } ?? []
        for (name, arguments) in shots.map({ ($0.0, $0.1 + ["-clearBackground"]) }) + photo {
            let app = XCUIApplication()
            app.launchArguments = ["-demo"] + arguments
            app.launch()
            sleep(3)
            let png = XCUIScreen.main.screenshot().pngRepresentation
            try png.write(to: URL(fileURLWithPath: directory).appending(path: "\(name).png"))
            app.terminate()
        }
    }

    /// Pairs with the running Mac agent, then waits for a permission request and taps Allow.
    func testPairAndApprove() throws {
        let code = try XCTUnwrap(env["DASHUP_PAIR_CODE"], "Set TEST_RUNNER_DASHUP_PAIR_CODE")
        let app = XCUIApplication()
        app.launchArguments = ["-resetPairing"]
        app.launch()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Pairing screen didn't appear")
        field.typeText(code)

        XCTAssertTrue(app.staticTexts["Claude Code"].waitForExistence(timeout: 20), "Didn't reach Home after pairing")
        if let directory = env["DASHUP_SHOTS"] {
            sleep(4) // let icons and favicons arrive
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: directory).appending(path: "live-home.png"))
        }

        let allow = app.buttons["Allow"].firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 90), "No permission request arrived")
        if let directory = env["DASHUP_SHOTS"] {
            sleep(1) // let the card finish animating in
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: directory).appending(path: "live-approval.png"))
        }
        allow.tap()
        sleep(2)
        XCTAssertFalse(app.buttons["Allow"].exists, "The approval card should clear after Allow")
    }
}
