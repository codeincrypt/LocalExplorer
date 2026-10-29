import XCTest

/// End-to-end UI tests. Each test launches the app on a fresh fixture folder in the
/// temporary directory with its own state file, so the user's files and settings are
/// never touched. Run with `make uitest` (requires the Xcode project from XcodeGen).
final class LocalExplorerUITests: XCTestCase {
    private var fixture: URL!
    private var stateFile: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let fm = FileManager.default
        fixture = fm.temporaryDirectory.appendingPathComponent("LocalExplorerUITests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: fixture.appendingPathComponent("Folder A/Nested", isDirectory: true), withIntermediateDirectories: true)
        try Data("alpha\n".utf8).write(to: fixture.appendingPathComponent("alpha.txt"))
        try Data("{\"b\": 2}\n".utf8).write(to: fixture.appendingPathComponent("beta.json"))
        try Data("# Gamma\n".utf8).write(to: fixture.appendingPathComponent("gamma.md"))
        try Data("hidden".utf8).write(to: fixture.appendingPathComponent(".secret"))
        try Data("inner".utf8).write(to: fixture.appendingPathComponent("Folder A/inner.txt"))

        app = XCUIApplication()
        app.launchEnvironment["LOCAL_EXPLORER_START_PATH"] = fixture.path
        // State lives outside the fixture so it never shows up in listings.
        stateFile = fm.temporaryDirectory.appendingPathComponent("LocalExplorerUITests-state-\(UUID().uuidString).json")
        app.launchEnvironment["LOCAL_EXPLORER_STATE_FILE"] = stateFile.path
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let fixture {
            // Restore permissions changed by tests so cleanup succeeds.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.appendingPathComponent("Locked").path)
            try? FileManager.default.removeItem(at: fixture)
        }
        if let stateFile { try? FileManager.default.removeItem(at: stateFile) }
    }

    private var status: XCUIElement { app.staticTexts["statusSummary"] }

    private func waitForStatus(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@ OR label == %@", text, text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "status bar should read “\(text)”, was “\(status.label)”", file: file, line: line)
    }

    func testOpensFixtureAndCountsVisibleItems() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        // Folder A, alpha.txt, beta.json, gamma.md — .secret is hidden.
        waitForStatus("4 items")
    }

    func testTogglesHiddenFiles() {
        waitForStatus("4 items")
        app.typeKey(".", modifierFlags: [.command, .shift])
        waitForStatus("5 items")
        app.typeKey(".", modifierFlags: [.command, .shift])
        waitForStatus("4 items")
    }

    func testSwitchesAllViewModesWithKeyboard() {
        waitForStatus("4 items")
        let expectations: [(String, String)] = [
            ("1", "fileList.tiles"), ("2", "fileList.compactList"),
            ("3", "fileList.gallery"), ("4", "fileList.details"),
        ]
        for (key, identifier) in expectations {
            app.typeKey(key, modifierFlags: .command)
            XCTAssertTrue(app.descendants(matching: .any)[identifier].waitForExistence(timeout: 3), "⌘\(key) should show \(identifier)")
        }
    }

    func testSwitchesViewModesWithToolbar() {
        for mode in ["tiles", "compactList", "gallery", "details"] {
            app.buttons["viewMode.\(mode)"].click()
            XCTAssertTrue(app.descendants(matching: .any)["fileList.\(mode)"].waitForExistence(timeout: 3))
        }
    }

    func testSelectAllAndMultipleSelection() {
        waitForStatus("4 items")
        app.typeKey("a", modifierFlags: .command)
        let predicate = NSPredicate(format: "label BEGINSWITH %@", "4 of 4 selected")
        expectation(for: predicate, evaluatedWith: status)
        waitForExpectations(timeout: 3)
    }

    func testNavigatesIntoFolderAndBack() {
        waitForStatus("4 items")
        app.typeKey("l", modifierFlags: .command)
        let path = app.textFields["pathField"]
        XCTAssertTrue(path.waitForExistence(timeout: 3))
        path.typeKey("a", modifierFlags: .command)
        path.typeText(fixture.appendingPathComponent("Folder A").path + "\r")
        waitForStatus("2 items")
        app.typeKey("[", modifierFlags: .command)
        waitForStatus("4 items")
        app.typeKey("]", modifierFlags: .command)
        waitForStatus("2 items")
        app.typeKey(XCUIKeyboardKey.upArrow.rawValue, modifierFlags: .command)
        waitForStatus("1 of 4 selected")
    }

    func testSearchFiltersCurrentFolder() {
        waitForStatus("4 items")
        app.typeKey("f", modifierFlags: .command)
        let search = app.textFields["searchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.typeText("ext:json")
        waitForStatus("1 item")
        search.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        waitForStatus("4 items")
    }

    func testPreviewPaneTogglesAndShowsSelection() {
        waitForStatus("4 items")
        let pane = app.descendants(matching: .any)["previewPane"]
        if !pane.exists { app.buttons["togglePreviewPane"].click() }
        XCTAssertTrue(pane.waitForExistence(timeout: 3))
        app.buttons["togglePreviewPane"].click()
        XCTAssertFalse(pane.waitForExistence(timeout: 1))
        app.buttons["togglePreviewPane"].click()
        XCTAssertTrue(pane.waitForExistence(timeout: 3))
    }

    func testNewFolderOffersRename() {
        waitForStatus("4 items")
        app.typeKey("n", modifierFlags: [.command, .shift])
        let sheetField = app.sheets.textFields.firstMatch
        XCTAssertTrue(sheetField.waitForExistence(timeout: 3), "new folder should open the rename sheet")
        sheetField.typeKey("a", modifierFlags: .command)
        sheetField.typeText("Created\r")
        waitForStatus("1 of 5 selected")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.appendingPathComponent("Created").path))
    }

    func testPermissionDeniedShowsActionableError() throws {
        try XCTSkipIf(getuid() == 0, "root bypasses POSIX permissions")
        let locked = fixture.appendingPathComponent("Locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        app.typeKey("l", modifierFlags: .command)
        let path = app.textFields["pathField"]
        XCTAssertTrue(path.waitForExistence(timeout: 3))
        path.typeKey("a", modifierFlags: .command)
        path.typeText(locked.path + "\r")
        XCTAssertTrue(app.descendants(matching: .any)["errorState"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Grant Access…"].exists)
        // Resolve: restore permission and retry.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        app.buttons["Try Again"].click()
        waitForStatus("0 items")
    }
}
