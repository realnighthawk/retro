import XCTest

/// Navigation/account checks need no running engine; read-contract behavior is covered by native unit fixtures.
final class FlowTests: XCTestCase {
    private func launch(on surface: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-dev-engine", "http://127.0.0.1:18091", "-demo-tab", surface]
        app.launch()
        return app
    }

    func testWardrobeNavigationReplacesTheProductivityDemo() {
        let app = launch(on: "today")
        XCTAssertTrue(app.tabBars.buttons["Wardrobe"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        XCTAssertTrue(app.tabBars.buttons["History"].exists)
        XCTAssertFalse(app.tabBars.buttons["Goals"].exists)
        XCTAssertFalse(app.tabBars.buttons["Review"].exists)
        XCTAssertFalse(app.buttons["Capture"].exists)
        app.tabBars.buttons["Wardrobe"].tap()
        XCTAssertTrue(app.searchFields["Search garment names"].waitForExistence(timeout: 5))
    }

    func testAccountIsReachableFromEachDestination() {
        let app = launch(on: "history")
        for title in ["History", "Wardrobe", "Today"] {
            XCTAssertTrue(app.tabBars.buttons[title].waitForExistence(timeout: 10))
            app.tabBars.buttons[title].tap()
            app.buttons["Account"].tap()
            XCTAssertTrue(app.staticTexts["dev@local"].waitForExistence(timeout: 5))
            app.buttons["Done"].tap()
        }
    }
}
