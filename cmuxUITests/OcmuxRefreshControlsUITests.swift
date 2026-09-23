import XCTest

/// Pins the two ocmux refresh affordances as *clickable UI*, not just as code.
///
/// `OcmuxRefreshTargetsTests` already pins which surfaces may be refreshed.
/// What that suite cannot see is whether the controls reach the user at all:
/// the titlebar ⟳ has to sit in the controls strip with a real hit area, and
/// the per-row ⟳ only exists while the pointer rests on its sidebar row. Both
/// are exercised here through coordinate clicks, so a control that renders but
/// is not hittable — or a hover gate that never opens — fails.
final class OcmuxRefreshControlsUITests: XCTestCase {
    /// The titlebar ⟳ renders beside "+" and accepts a real click.
    @MainActor
    func testTitlebarRefreshAllControlIsClickable() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }

        let refreshAll = control(in: app, identifier: "titlebarControl.ocmuxRefreshAll")
        XCTAssertTrue(
            refreshAll.waitForExistence(timeout: 10),
            "The titlebar must carry the ocmux refresh-all control."
        )
        XCTAssertTrue(refreshAll.isHittable, "A rendered-but-unhittable control is unreachable.")

        let frame = refreshAll.frame
        XCTAssertGreaterThan(frame.width, 10)
        XCTAssertGreaterThan(frame.height, 10)

        // Sits after the new-workspace split button, matching TitlebarControlsHitRegions.
        let newWorkspaceMenu = control(in: app, identifier: "titlebarControl.newWorkspaceMenu")
        if newWorkspaceMenu.exists {
            XCTAssertGreaterThan(
                frame.minX,
                newWorkspaceMenu.frame.minX,
                "The ⟳ belongs after the + split button, not before it."
            )
        }

        // A coordinate click exercises hit testing; an accessibility press would bypass it.
        refreshAll.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.width / 2, dy: frame.height / 2))
            .click()

        // With no ocmux-tagged panes open the refresh is a no-op, and must stay one:
        // it may not close surfaces, spawn workspaces, or take the app down.
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground, "Refresh-all must not terminate the app.")
        XCTAssertTrue(refreshAll.waitForExistence(timeout: 5), "The control must survive its own click.")
    }

    /// The per-row ⟳ appears on hover and accepts a real click.
    @MainActor
    func testSidebarWorkspaceRefreshControlAppearsOnHoverAndIsClickable() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        let rowRefresh = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sidebarWorkspace.ocmuxRefresh."))
            .firstMatch

        // The gate is the point: at rest the row keeps its exact layout.
        XCTAssertFalse(
            rowRefresh.exists,
            "The per-row ⟳ must stay hidden until the pointer rests on the row."
        )

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sidebarWorkspaceRow"))
            .firstMatch
        let hoverTarget: XCUIElement = row.exists ? row : app.windows.firstMatch
        hoverTarget.hover()

        XCTAssertTrue(
            rowRefresh.waitForExistence(timeout: 5),
            "Hovering a workspace row must reveal its ocmux refresh control."
        )
        XCTAssertTrue(rowRefresh.isHittable)

        let frame = rowRefresh.frame
        rowRefresh.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.width / 2, dy: frame.height / 2))
            .click()

        XCTAssertEqual(app.state, .runningForeground, "Row refresh must not terminate the app.")
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication.cmuxTestApplication()
        app.launchEnvironment["CMUX_UI_TEST_MODE"] = "1"
        app.launchArguments += [
            "-workspacePresentationMode", "standard",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func control(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
