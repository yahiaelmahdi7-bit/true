import XCTest

/// Proves the thing Yahia reported ("I can't interact with the text"): a long-press on the terminal must
/// offer the edit menu, Select All must light up Copy, and Copy must land the text on the pasteboard.
/// Needs the mock server on :8899 (`MOCK_STATE=normal python3 scripts/remote-mock.py`).
/// Screenshots go to `TEST_RUNNER_SHOT_DIR` (xcodebuild strips the prefix, the runner sees `SHOT_DIR`), else `.out/run29`.
final class PaneSelectionUITests: XCTestCase {
    private var shotDir: URL {
        let env = ProcessInfo.processInfo.environment["SHOT_DIR"]
        let fallback = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".out/run29").path
        return URL(fileURLWithPath: env ?? fallback)
    }

    func testLongPressSelectAllCopy() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-baseURL", "http://localhost:8899", "-autoPair", "123456", "-uiState", "pane"]
        app.launch()
        sleep(4)
        UIPasteboard.general.string = "sentinel"
        // Second line of the mock transcript ("214 tests passed"), keyboard already up.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.16)).press(forDuration: 1.2)
        sleep(2)
        let labels = app.menuItems.allElementsBoundByIndex.map(\.label)
        let shot = app.screenshot().pngRepresentation
        try? shot.write(to: shotDir.appendingPathComponent("pane-menu-dark.png"))
        XCTAssertFalse(labels.isEmpty, "long-press showed no edit menu")
        print("MENU ITEMS AFTER LONG-PRESS: \(labels)")
        let selectAll = app.menuItems["Select All"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 3), "no Select All among \(labels)")
        selectAll.tap()
        sleep(2)
        let labels2 = app.menuItems.allElementsBoundByIndex.map(\.label)
        print("MENU ITEMS AFTER SELECT ALL: \(labels2)")
        let shot2 = app.screenshot().pngRepresentation
        try? shot2.write(to: shotDir.appendingPathComponent("pane-selection-live-dark.png"))
        let copy = app.menuItems["Copy"]
        if !copy.exists {   // menu dismissed after Select All: long-press again on the selection to bring it back
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.16)).press(forDuration: 1.2)
            sleep(2)
            print("MENU ITEMS AFTER SECOND LONG-PRESS: \(app.menuItems.allElementsBoundByIndex.map(\.label))")
        }
        XCTAssertTrue(copy.waitForExistence(timeout: 3), "no Copy after Select All")
        copy.tap()
        sleep(1)
        // Never read UIPasteboard here: iOS pops a "Runner would like to paste from True" alert that blocks the run.
        // The host verifies instead: `xcrun simctl pbpaste <sim> | grep -q "tests passed"`.
    }
}
