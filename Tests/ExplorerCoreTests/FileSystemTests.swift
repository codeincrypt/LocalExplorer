import XCTest
@testable import ExplorerCore

final class FileSystemTests: XCTestCase {
    func testListsImmediateChildrenWithMetadata() throws {
        let dir = try TempDirectory()
        try dir.file("a.txt", "hello", modified: Date(timeIntervalSince1970: 1_000_000))
        try dir.file(".secret", "s")
        try dir.folder("Sub")
        try dir.file("Sub/nested.txt")   // must not be listed (no recursion)

        let items = try LocalFileSystem().contents(of: dir.url)
        XCTAssertEqual(Set(items.map(\.name)), ["a.txt", ".secret", "Sub"])
        let a = try XCTUnwrap(items.first { $0.name == "a.txt" })
        XCTAssertEqual(a.size, 5)
        XCTAssertFalse(a.isDirectory)
        XCTAssertEqual(a.modificationDate, Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(a.category, .text)
        XCTAssertTrue(try XCTUnwrap(items.first { $0.name == ".secret" }).isHidden)
        let sub = try XCTUnwrap(items.first { $0.name == "Sub" })
        XCTAssertTrue(sub.isNavigableDirectory)
        XCTAssertNil(sub.size)
    }

    func testHiddenToggleOverRealListing() throws {
        let dir = try TempDirectory()
        try dir.file("visible")
        try dir.file(".dotfile")
        let items = try LocalFileSystem().contents(of: dir.url)
        XCTAssertEqual(FileFilter(showHidden: false).apply(to: items).map(\.name), ["visible"])
        XCTAssertEqual(FileFilter(showHidden: true).apply(to: items).count, 2)
    }

    func testSymbolicLinks() throws {
        let dir = try TempDirectory()
        let target = try dir.folder("Target")
        try dir.file("Target/inside.txt")
        try FileManager.default.createSymbolicLink(at: dir.url.appendingPathComponent("LinkToFolder"), withDestinationURL: target)
        try FileManager.default.createSymbolicLink(atPath: dir.url.appendingPathComponent("Broken").path, withDestinationPath: "/nonexistent/\(UUID())")

        let items = try LocalFileSystem().contents(of: dir.url)
        let link = try XCTUnwrap(items.first { $0.name == "LinkToFolder" })
        XCTAssertTrue(link.isSymbolicLink)
        XCTAssertTrue(link.isNavigableDirectory)
        let broken = try XCTUnwrap(items.first { $0.name == "Broken" })
        XCTAssertTrue(broken.isBrokenSymbolicLink)
        XCTAssertFalse(broken.isNavigableDirectory)
        // Browsing through the link lists the target's children.
        XCTAssertEqual(try LocalFileSystem().contents(of: link.url).map(\.name), ["inside.txt"])
    }

    func testMissingFolderIsReportedNotThrownRaw() throws {
        let dir = try TempDirectory()
        let missing = dir.url.appendingPathComponent("gone")
        XCTAssertThrowsError(try LocalFileSystem().contents(of: missing)) { error in
            XCTAssertEqual(error as? DirectoryLoadError, .notFound(path: missing.path))
        }
        let file = try dir.file("file.txt")
        XCTAssertThrowsError(try LocalFileSystem().contents(of: file)) { error in
            XCTAssertEqual(error as? DirectoryLoadError, .notADirectory(path: file.path))
        }
    }

    func testUnreadableFolderReportsPermissionDenied() throws {
        try XCTSkipIf(isRunningAsRoot, "root bypasses POSIX permissions")
        let dir = try TempDirectory()
        let locked = try dir.folder("Locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        XCTAssertThrowsError(try LocalFileSystem().contents(of: locked)) { error in
            XCTAssertEqual(error as? DirectoryLoadError, .permissionDenied(path: locked.path))
        }
    }

    func testErrorClassification() {
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        XCTAssertEqual(DirectoryLoadError.classify(denied, path: "/x"), .permissionDenied(path: "/x"))
        let posix = NSError(domain: NSCocoaErrorDomain, code: 0, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))])
        XCTAssertEqual(DirectoryLoadError.classify(posix, path: "/x"), .notFound(path: "/x"))
        XCTAssertEqual(FileOperationError.classify(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)), path: "/x"), .insufficientSpace(required: 0, available: 0))
    }

    func testExternalChangesAppearOnReload() throws {
        let dir = try TempDirectory()
        try dir.file("one")
        let fs = LocalFileSystem()
        XCTAssertEqual(try fs.contents(of: dir.url).count, 1)
        try dir.file("two")
        try FileManager.default.removeItem(at: dir.url.appendingPathComponent("one"))
        XCTAssertEqual(try fs.contents(of: dir.url).map(\.name), ["two"])
    }

    func testLargeDirectoryEnumeration() throws {
        let dir = try TempDirectory()
        for i in 0..<10_000 {
            _ = FileManager.default.createFile(atPath: dir.url.appendingPathComponent("f\(i).dat").path, contents: nil)
        }
        let start = Date()
        let items = try LocalFileSystem().contents(of: dir.url)
        let sorted = FileSorter.sorted(FileFilter().apply(to: items), by: FileSortDescriptor())
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(sorted.count, 10_000)
        XCTAssertEqual(sorted.first?.name, "f0.dat")
        XCTAssertEqual(sorted.last?.name, "f9999.dat")
        print("Enumerated, filtered and sorted 10,000 entries in \(String(format: "%.0f", elapsed * 1000)) ms")
    }

    func testTotalSizeAndSameVolume() throws {
        let dir = try TempDirectory()
        try dir.file("A/one", "12345")
        try dir.file("A/B/two", "123")
        XCTAssertEqual(try FileSystemFacts.totalSize(of: dir.url.appendingPathComponent("A")), 8)
        XCTAssertTrue(FileSystemFacts.isSameVolume(dir.url, dir.url.appendingPathComponent("A")))
        XCTAssertNotNil(FileSystemFacts.permissions(of: dir.url))
    }
}
