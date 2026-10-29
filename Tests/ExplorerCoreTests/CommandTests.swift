import XCTest
@testable import ExplorerCore

final class CommandTests: XCTestCase {
    func testShortcutsAreUniqueWithinScope() {
        var seen: [String: ExplorerCommand] = [:]
        for command in ExplorerCommand.allCases {
            guard let s = command.shortcut else { continue }
            let key = "\(command.shortcutScope)|\(s.displayString)"
            XCTAssertNil(seen[key], "\(command) duplicates \(seen[key].map { "\($0)" } ?? "")")
            seen[key] = command
        }
    }

    func testRequiredShortcutMap() {
        let expected: [ExplorerCommand: String] = [
            .copy: "⌘C", .cut: "⌘X", .paste: "⌘V", .rename: "↩", .open: "⌘O",
            .moveToTrash: "⌘⌫", .getInfo: "⌘I", .selectAll: "⌘A", .newFolder: "⇧⌘N",
            .toggleHiddenFiles: "⇧⌘.", .viewTiles: "⌘1", .viewCompactList: "⌘2",
            .viewGallery: "⌘3", .viewDetails: "⌘4", .quickPreview: "Space", .cancel: "⎋",
            .search: "⌘F", .focusPath: "⌘L", .goToParent: "⌘↑", .goBack: "⌘[",
            .goForward: "⌘]", .newTab: "⌘T", .closeTab: "⌘W", .refresh: "⌘R",
            .showContextMenu: "⌃↩", .goThisMac: "⇧⌘C",
        ]
        for (command, display) in expected {
            XCTAssertEqual(command.shortcut?.displayString, display, "\(command)")
        }
    }

    func testPermanentDeleteHasNoShortcut() {
        XCTAssertNil(ExplorerCommand.deletePermanently.shortcut)
    }

    func testFileListScopedKeysDoNotBecomeMenuEquivalents() {
        for command in [ExplorerCommand.rename, .quickPreview, .cancel, .showContextMenu] {
            XCTAssertEqual(command.shortcutScope, .fileList)
        }
        XCTAssertEqual(ExplorerCommand.command(for: Shortcut(.space), scope: .fileList), .quickPreview)
        XCTAssertEqual(ExplorerCommand.command(for: Shortcut(.returnKey), scope: .fileList), .rename)
        XCTAssertNil(ExplorerCommand.command(for: Shortcut(.returnKey), scope: .menu))
        XCTAssertEqual(ExplorerCommand.command(for: Shortcut(.character("4"), .command), scope: .menu), .viewDetails)
    }

    func testRoutingForwardsTextEditingCommands() {
        var ctx = CommandContext(selectionCount: 2, canPaste: true, isEditingText: true)
        XCTAssertEqual(CommandRouting.decide(.copy, in: ctx), .forwardToTextEditor("copy:"))
        XCTAssertEqual(CommandRouting.decide(.paste, in: ctx), .forwardToTextEditor("paste:"))
        XCTAssertEqual(CommandRouting.decide(.selectAll, in: ctx), .forwardToTextEditor("selectAll:"))
        XCTAssertEqual(CommandRouting.decide(.moveToTrash, in: ctx), .forwardToTextEditor("deleteToBeginningOfLine:"))
        XCTAssertEqual(CommandRouting.decide(.refresh, in: ctx), .perform)
        ctx.isEditingText = false
        XCTAssertEqual(CommandRouting.decide(.copy, in: ctx), .perform)
    }

    func testAvailability() {
        let empty = CommandContext(selectionCount: 0)
        XCTAssertEqual(CommandRouting.decide(.copy, in: empty), .unavailable)
        XCTAssertFalse(CommandRouting.isEnabled(.rename, in: CommandContext(selectionCount: 2)))
        XCTAssertTrue(CommandRouting.isEnabled(.rename, in: CommandContext(selectionCount: 1)))
        XCTAssertFalse(CommandRouting.isEnabled(.paste, in: CommandContext(canPaste: false)))
        XCTAssertFalse(CommandRouting.isEnabled(.paste, in: CommandContext(canPaste: true, isFolderWritable: false)))
        XCTAssertFalse(CommandRouting.isEnabled(.newFolder, in: CommandContext(isFolderWritable: false)))
        XCTAssertFalse(CommandRouting.isEnabled(.goBack, in: CommandContext()))
        XCTAssertTrue(CommandRouting.isEnabled(.goBack, in: CommandContext(canGoBack: true)))
        XCTAssertTrue(CommandRouting.isEnabled(.copy, in: CommandContext(selectionCount: 1, isFolderWritable: false)))
        XCTAssertFalse(CommandRouting.isEnabled(.moveToTrash, in: CommandContext(selectionCount: 1, isFolderWritable: false)))
    }

    func testViewCommandsCoverAllModes() {
        XCTAssertEqual(Set(ViewMode.allCases.map(ExplorerCommand.viewCommand(for:))),
                       [.viewTiles, .viewCompactList, .viewGallery, .viewDetails])
    }
}
