import XCTest
@testable import ExplorerCore

final class FileOperationTests: XCTestCase {
    var dir: TempDirectory!
    var engine: FileOperationEngine!
    var trashFolder: URL!

    override func setUpWithError() throws {
        dir = try TempDirectory()
        trashFolder = dir.url.appendingPathComponent("_Trash")
        engine = FileOperationEngine(trash: FolderTrash(folder: trashFolder))
    }

    override func tearDown() {
        dir = nil
    }

    // MARK: Copy

    func testCopyFilesAndFolders() async throws {
        let a = try dir.file("src/a.txt", "A")
        try dir.file("src/Folder/inner.txt", "I")
        let dest = try dir.folder("dest")
        let report = await engine.copy([a, dir.url.appendingPathComponent("src/Folder")], into: dest, conflicts: ScriptedConflicts([]).handler)
        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(dir.read("dest/a.txt"), "A")
        XCTAssertEqual(dir.read("dest/Folder/inner.txt"), "I")
        XCTAssertTrue(dir.exists("src/a.txt"), "copy keeps the source")
        XCTAssertEqual(dir.names("dest"), ["Folder", "a.txt"], "no temporary files left behind")
        if case .created(let urls)? = report.record { XCTAssertEqual(urls.count, 2) } else { XCTFail("expected undo record") }
    }

    func testCopyIntoSameFolderMakesCopy() async throws {
        let a = try dir.file("a.txt", "A")
        let report = await engine.copy([a], into: dir.url, conflicts: ScriptedConflicts([]).handler)
        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(dir.read("a copy.txt"), "A")
    }

    func testConflictReplaceMovesOldItemToTrash() async throws {
        let src = try dir.file("src/a.txt", "NEW")
        try dir.file("dest/a.txt", "OLD")
        let conflicts = ScriptedConflicts([ConflictResolution(.replace)])
        let report = await engine.copy([src], into: dir.url.appendingPathComponent("dest"), conflicts: conflicts.handler)
        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(conflicts.seen.count, 1)
        XCTAssertEqual(conflicts.seen[0].existing.lastPathComponent, "a.txt")
        XCTAssertEqual(dir.read("dest/a.txt"), "NEW")
        XCTAssertEqual(dir.read("_Trash/a.txt"), "OLD", "replaced item is preserved in the Trash")
        XCTAssertNil(report.record, "replace operations are not offered for undo")
    }

    func testConflictKeepBothSkipAndApplyToAll() async throws {
        for name in ["1.txt", "2.txt", "3.txt"] {
            try dir.file("src/\(name)", "new")
            try dir.file("dest/\(name)", "old")
        }
        let sources = ["1.txt", "2.txt", "3.txt"].map { dir.url.appendingPathComponent("src/\($0)") }
        let conflicts = ScriptedConflicts([ConflictResolution(.skip), ConflictResolution(.keepBoth, applyToRemaining: true)])
        let report = await engine.copy(sources, into: dir.url.appendingPathComponent("dest"), conflicts: conflicts.handler)
        XCTAssertEqual(conflicts.seen.count, 2, "the third conflict uses the remembered choice")
        XCTAssertEqual(conflicts.seen[0].remainingItems, 2)
        XCTAssertEqual(report.skipped.map(\.lastPathComponent), ["1.txt"])
        XCTAssertEqual(dir.names("dest"), ["1.txt", "2 2.txt", "2.txt", "3 2.txt", "3.txt"])
        XCTAssertEqual(dir.read("dest/2.txt"), "old", "never overwritten without Replace")
    }

    func testConflictCancelStopsBatch() async throws {
        try dir.file("src/1.txt"); try dir.file("dest/1.txt", "old")
        try dir.file("src/2.txt")
        let sources = ["1.txt", "2.txt"].map { dir.url.appendingPathComponent("src/\($0)") }
        let report = await engine.copy(sources, into: dir.url.appendingPathComponent("dest"), conflicts: ScriptedConflicts([ConflictResolution(.cancel)]).handler)
        XCTAssertTrue(report.cancelled)
        XCTAssertFalse(dir.exists("dest/2.txt"))
        XCTAssertEqual(dir.read("dest/1.txt"), "old")
    }

    func testCannotCopyFolderIntoItself() async throws {
        let folder = try dir.folder("Folder")
        let child = try dir.folder("Folder/Child")
        let report = await engine.copy([folder], into: child, conflicts: ScriptedConflicts([]).handler)
        XCTAssertEqual(report.failures.first?.error, .destinationInsideSource(path: folder.path))
        let report2 = await engine.move([folder], into: folder, conflicts: ScriptedConflicts([]).handler)
        XCTAssertEqual(report2.failures.first?.error, .destinationInsideSource(path: folder.path))
    }

    func testMissingSourceIsPartialFailure() async throws {
        let ok = try dir.file("ok.txt")
        let missing = dir.url.appendingPathComponent("missing.txt")
        let dest = try dir.folder("dest")
        let report = await engine.copy([missing, ok], into: dest, conflicts: ScriptedConflicts([]).handler)
        XCTAssertEqual(report.completed.count, 1)
        XCTAssertEqual(report.failures.first?.error, .notFound(path: missing.path))
        XCTAssertNotNil(report.failureSummary)
    }

    func testCancellationBeforeStart() async throws {
        let a = try dir.file("a.txt")
        let dest = try dir.folder("dest")
        let engine = self.engine!
        let task = Task { () -> FileOperationReport in
            withUnsafeCurrentTask { $0?.cancel() }
            return await engine.copy([a], into: dest, conflicts: ScriptedConflicts([]).handler)
        }
        let report = await task.value
        XCTAssertTrue(report.cancelled)
        XCTAssertEqual(dir.names("dest"), [])
    }

    func testProgressIsReported() async throws {
        let files = try (0..<5).map { try dir.file("src/\($0).bin", String(repeating: "x", count: 100)) }
        let dest = try dir.folder("dest")
        let box = ProgressBox()
        _ = await engine.copy(files, into: dest, conflicts: ScriptedConflicts([]).handler, progress: { box.append($0) })
        XCTAssertEqual(box.values.last?.completedItems, 5)
        XCTAssertEqual(box.values.last?.totalBytes, 500)
        XCTAssertEqual(box.values.last?.fraction ?? 0, 1, accuracy: 0.0001)
    }

    func testSelectedChildOfSelectedFolderIsNotCopiedTwice() async throws {
        let folder = try dir.folder("F")
        let child = try dir.file("F/child.txt")
        let dest = try dir.folder("dest")
        let report = await engine.copy([folder, child], into: dest, conflicts: ScriptedConflicts([]).handler)
        XCTAssertEqual(report.completed.count, 1)
        XCTAssertEqual(dir.names("dest"), ["F"])
    }

    // MARK: Move

    func testMoveAndUndo() async throws {
        let a = try dir.file("src/a.txt", "A")
        let dest = try dir.folder("dest")
        let report = await engine.move([a], into: dest, conflicts: ScriptedConflicts([]).handler)
        XCTAssertTrue(report.succeeded)
        XCTAssertFalse(dir.exists("src/a.txt"))
        XCTAssertEqual(dir.read("dest/a.txt"), "A")
        let record = try XCTUnwrap(report.record)
        let undo = await engine.undo(record)
        XCTAssertTrue(undo.succeeded)
        XCTAssertEqual(dir.read("src/a.txt"), "A")
        XCTAssertFalse(dir.exists("dest/a.txt"))
    }

    func testMoveIntoSameFolderIsSkipped() async throws {
        let a = try dir.file("a.txt")
        let report = await engine.move([a], into: dir.url, conflicts: ScriptedConflicts([]).handler)
        XCTAssertEqual(report.skipped, [a])
        XCTAssertTrue(dir.exists("a.txt"))
    }

    func testMoveReplaceRestoresSourceIfTargetCannotBeRetired() async throws {
        // Replacing a folder that contains the source is refused before anything moves.
        try dir.file("Outer/inner/Outer/x.txt")
        let source = dir.url.appendingPathComponent("Outer/inner/Outer")
        let report = await engine.move([source], into: dir.url, conflicts: ScriptedConflicts([ConflictResolution(.replace)]).handler)
        XCTAssertEqual(report.failures.first?.error, .replacingAncestor(path: dir.url.appendingPathComponent("Outer").path))
        XCTAssertTrue(dir.exists("Outer/inner/Outer/x.txt"))
    }

    func testUndoRefusesToOverwrite() async throws {
        let a = try dir.file("src/a.txt", "A")
        let dest = try dir.folder("dest")
        let report = await engine.move([a], into: dest, conflicts: ScriptedConflicts([]).handler)
        try dir.file("src/a.txt", "NEW OCCUPANT")
        let undo = await engine.undo(try XCTUnwrap(report.record))
        XCTAssertFalse(undo.succeeded)
        XCTAssertEqual(dir.read("src/a.txt"), "NEW OCCUPANT")
        XCTAssertEqual(dir.read("dest/a.txt"), "A")
    }

    // MARK: Rename, duplicate, new folder

    func testRename() throws {
        let a = try dir.file("a.txt", "A")
        let renamed = try engine.rename(a, to: "b.txt")
        XCTAssertEqual(renamed.lastPathComponent, "b.txt")
        XCTAssertEqual(dir.read("b.txt"), "A")
        try dir.file("c.txt")
        XCTAssertThrowsError(try engine.rename(renamed, to: "c.txt")) {
            XCTAssertEqual($0 as? FileOperationError, .alreadyExists(path: dir.url.appendingPathComponent("c.txt").path))
        }
        XCTAssertThrowsError(try engine.rename(renamed, to: "bad/name")) {
            XCTAssertEqual($0 as? FileOperationError, .invalidName(.containsSlash))
        }
    }

    func testCaseOnlyRename() throws {
        let a = try dir.file("readme.md", "R")
        let renamed = try engine.rename(a, to: "README.md")
        XCTAssertEqual(renamed.lastPathComponent, "README.md")
        XCTAssertEqual(dir.names(), ["README.md"])
    }

    func testDuplicate() async throws {
        let a = try dir.file("report.pdf", "P")
        let first = await engine.duplicate([a])
        let second = await engine.duplicate([a])
        XCTAssertEqual(first.destinations.map(\.lastPathComponent), ["report copy.pdf"])
        XCTAssertEqual(second.destinations.map(\.lastPathComponent), ["report copy 2.pdf"])
        XCTAssertEqual(dir.read("report copy 2.pdf"), "P")
    }

    func testCreateFolder() throws {
        let first = try engine.createFolder(in: dir.url)
        let second = try engine.createFolder(in: dir.url)
        XCTAssertEqual(first.lastPathComponent, "untitled folder")
        XCTAssertEqual(second.lastPathComponent, "untitled folder 2")
        XCTAssertThrowsError(try engine.createFolder(in: dir.url, name: "untitled folder"))
        XCTAssertThrowsError(try engine.createFolder(in: dir.url, name: ""))
    }

    func testCreateFolderInReadOnlyDirectory() throws {
        try XCTSkipIf(isRunningAsRoot, "root bypasses POSIX permissions")
        let ro = try dir.folder("ReadOnly")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: ro.path)
        XCTAssertThrowsError(try engine.createFolder(in: ro)) {
            XCTAssertEqual($0 as? FileOperationError, .permissionDenied(path: ro.appendingPathComponent("untitled folder").path))
        }
    }

    // MARK: Trash and delete

    func testTrashAndUndo() async throws {
        let a = try dir.file("a.txt", "A")
        let report = await engine.moveToTrash([a])
        XCTAssertTrue(report.succeeded)
        XCTAssertFalse(dir.exists("a.txt"))
        XCTAssertEqual(dir.read("_Trash/a.txt"), "A")
        let undo = await engine.undo(try XCTUnwrap(report.record))
        XCTAssertTrue(undo.succeeded)
        XCTAssertEqual(dir.read("a.txt"), "A")
    }

    func testDeletePermanently() async throws {
        let a = try dir.file("a.txt")
        try dir.file("F/b.txt")
        let report = await engine.deletePermanently([a, dir.url.appendingPathComponent("F")])
        XCTAssertTrue(report.succeeded)
        XCTAssertNil(report.record, "permanent deletion is never undoable")
        XCTAssertEqual(dir.names(), [])
    }

    func testUndoCreatedTrashesIt() async throws {
        let folder = try engine.createFolder(in: dir.url)
        let undo = await engine.undo(.created([folder]))
        XCTAssertTrue(undo.succeeded)
        XCTAssertFalse(dir.exists("untitled folder"))
    }

    // MARK: Batch rename

    func testBatchRenameHandlesSwaps() throws {
        let a = try dir.file("a.txt", "A")
        let b = try dir.file("b.txt", "B")
        let plan = [
            BatchRenameEntry(source: a, newName: "b.txt", issue: nil),
            BatchRenameEntry(source: b, newName: "a.txt", issue: nil),
        ]
        let report = engine.applyBatchRename(plan)
        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(dir.read("a.txt"), "B")
        XCTAssertEqual(dir.read("b.txt"), "A")
    }

    func testBatchRenameFromPlanner() throws {
        let urls = try ["IMG_1.jpg", "IMG_2.jpg"].map { try dir.file($0) }
        let plan = BatchRenamePlanner.plan(for: urls, rule: .format(baseName: "Holiday ", startIndex: 1, digits: 2, position: .after))
        let report = engine.applyBatchRename(plan)
        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(dir.names(), ["Holiday 01.jpg", "Holiday 02.jpg"])
        let undo = engine.applyBatchRename([])
        XCTAssertTrue(undo.completed.isEmpty)
    }

    func testBatchRenameRefusesInvalidPlan() throws {
        let a = try dir.file("a.txt")
        let report = engine.applyBatchRename([BatchRenameEntry(source: a, newName: "x", issue: .duplicateInBatch)])
        XCTAssertFalse(report.succeeded)
        XCTAssertTrue(dir.exists("a.txt"))
    }

    func testBatchRenameUndo() async throws {
        let urls = try ["one.txt", "two.txt"].map { try dir.file($0) }
        let report = engine.applyBatchRename(BatchRenamePlanner.plan(for: urls, rule: .changeCase(.upper)))
        XCTAssertEqual(dir.names(), ["ONE.txt", "TWO.txt"])
        let undo = await engine.undo(try XCTUnwrap(report.record))
        XCTAssertTrue(undo.succeeded, "\(undo.failures)")
        XCTAssertEqual(dir.names(), ["one.txt", "two.txt"])
    }
}

final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [OperationProgress] = []
    func append(_ p: OperationProgress) { lock.lock(); values.append(p); lock.unlock() }
}
