import XCTest

final class StillIOSUITests: XCTestCase {
    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func launch(demo: Bool = true, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-still-test-library", UUID().uuidString, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if demo { app.launchArguments.append("-still-demo") }
        app.launchArguments += extraArguments
        app.launch()
        return app
    }

    func testStackOpensPhotosAndPersistsAnnotation() {
        let app = launch()
        XCTAssertTrue(app.buttons["openAlbum"].waitForExistence(timeout: 10))
        capture(app, name: "iPhone album stack")
        XCTAssertEqual(app.staticTexts["albumPosition"].label, "1 / 6")
        app.buttons["下一本"].tap()
        XCTAssertEqual(app.staticTexts["albumPosition"].label, "2 / 6")
        app.buttons["openAlbum"].tap()
        XCTAssertTrue(app.buttons["photo-0"].waitForExistence(timeout: 5))
        capture(app, name: "iPhone album photos")
        app.buttons["photo-0"].tap()
        app.buttons["editAnnotation"].tap()
        let title = app.textFields["annotationTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("A quiet morning")
        app.buttons["saveAnnotation"].tap()
        XCTAssertTrue(app.staticTexts["A quiet morning"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        app.buttons["下一本"].tap()
        app.buttons["openAlbum"].tap()
        app.buttons["photo-0"].tap()
        XCTAssertTrue(app.staticTexts["A quiet morning"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Persisted photo annotation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testEmptyLibraryAndCancelledImport() {
        let app = launch(demo: false)
        XCTAssertTrue(app.staticTexts["第一本相册，从这里开始"].waitForExistence(timeout: 10))
        app.buttons["newAlbum"].tap()
        XCTAssertTrue(app.textFields["albumNameField"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveAlbum"].isEnabled)
        app.textFields["albumNameField"].tap()
        app.textFields["albumNameField"].typeText("Test album")
        XCTAssertFalse(app.buttons["saveAlbum"].isEnabled)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.staticTexts["第一本相册，从这里开始"].exists)
    }

    func testSwipeAndLastAlbumBoundary() {
        let app = launch()
        XCTAssertTrue(app.buttons["openAlbum"].waitForExistence(timeout: 10))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.57))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertEqual(app.staticTexts["albumPosition"].label, "2 / 6")
        for _ in 0..<4 { app.buttons["下一本"].tap() }
        XCTAssertEqual(app.staticTexts["albumPosition"].label, "6 / 6")
        XCTAssertFalse(app.buttons["下一本"].isEnabled)
        app.buttons["openAlbum"].tap()
        XCTAssertTrue(app.buttons["photo-5"].waitForExistence(timeout: 5))
    }

    func testCreateAlbumFromSystemPicker() throws {
        let app = launch(demo: false)
        XCTAssertTrue(app.buttons["newAlbum"].waitForExistence(timeout: 10))
        app.buttons["newAlbum"].tap()
        app.textFields["albumNameField"].tap()
        app.textFields["albumNameField"].typeText("Phone memories")
        app.buttons["choosePhotos"].tap()
        let photo = app.images.matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@",
                                                   "PXGGridLayout-Info", "照片,", "Photo,")).firstMatch
        guard photo.waitForExistence(timeout: 90) else {
            XCTFail("Seed the simulator Photos library with xcrun simctl addmedia before this test.\n\(app.debugDescription)")
            return
        }
        photo.tap()
        let add = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@",
                                                  "完成", "Done", "添加", "Add")).firstMatch
        guard add.waitForExistence(timeout: 10) else { XCTFail(app.debugDescription); return }
        add.tap()
        XCTAssertTrue(app.buttons["saveAlbum"].waitForExistence(timeout: 5))
        app.buttons["saveAlbum"].tap()
        XCTAssertTrue(app.buttons["openAlbum"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["selectedAlbumName"].label, "Phone memories")
        capture(app, name: "Imported album")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["openAlbum"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["selectedAlbumName"].label, "Phone memories")
        app.buttons["openAlbum"].tap()
        XCTAssertTrue(app.buttons["photo-0"].waitForExistence(timeout: 5))
    }

    func testDarkAndAccessibleLayouts() {
        let app = launch(extraArguments: ["-still-dark"])
        XCTAssertTrue(app.buttons["openAlbum"].waitForExistence(timeout: 10))
        capture(app, name: "Dark album stack")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["newAlbum"].exists)
        capture(app, name: "Landscape album list")
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["newAlbum"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["albumPosition"].exists)
        capture(app, name: "Accessible album list")
    }
}
