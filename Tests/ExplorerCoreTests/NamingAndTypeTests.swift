import XCTest
@testable import ExplorerCore

final class FilenameTests: XCTestCase {
    func testValidation() {
        XCTAssertEqual(FilenameValidator.validate(""), [.empty])
        XCTAssertEqual(FilenameValidator.validate(".."), [.reserved])
        XCTAssertEqual(FilenameValidator.validate("a/b"), [.containsSlash])
        XCTAssertEqual(FilenameValidator.validate("a:b"), [.containsColon])
        XCTAssertEqual(FilenameValidator.validate(String(repeating: "é", count: 200)), [.tooLong])
        XCTAssertEqual(FilenameValidator.validate("Résumé 2024.pdf"), [])
    }

    func testRenameValidation() {
        let existing: Set<String> = ["a.txt", "b.txt", "Folder"]
        let exists = { existing.contains($0) }
        XCTAssertEqual(FilenameValidator.validateRename(original: "a.txt", proposed: "b.txt", isDirectory: false, exists: exists).issues, [.alreadyExists])
        XCTAssertTrue(FilenameValidator.validateRename(original: "a.txt", proposed: "A.txt", isDirectory: false, exists: { $0 == "a.txt" || $0 == "A.txt" }).isValid)
        let ext = FilenameValidator.validateRename(original: "a.txt", proposed: "a.md", isDirectory: false, exists: exists)
        XCTAssertTrue(ext.isValid)
        XCTAssertEqual(ext.warnings, [.extensionChanged(from: "txt", to: "md")])
        XCTAssertEqual(FilenameValidator.validateRename(original: "a.txt", proposed: ".a.txt", isDirectory: false, exists: exists).warnings, [.becomesHidden])
        XCTAssertTrue(FilenameValidator.validateRename(original: "Folder", proposed: "Folder.v2", isDirectory: true, exists: exists).warnings.isEmpty)
    }

    func testFilenameParts() {
        XCTAssertEqual(FilenameParts(name: "photo.jpg"), FilenameParts(stem: "photo", ext: "jpg"))
        XCTAssertEqual(FilenameParts(name: "backup.tar.gz"), FilenameParts(stem: "backup", ext: "tar.gz"))
        XCTAssertEqual(FilenameParts(name: ".zshrc"), FilenameParts(stem: ".zshrc", ext: ""))
        XCTAssertEqual(FilenameParts(name: "my.folder", isDirectory: true), FilenameParts(stem: "my.folder", ext: ""))
        XCTAssertEqual(FilenameParts(name: "Version 1.0 final"), FilenameParts(stem: "Version 1.0 final", ext: ""))
    }

    func testKeepBothNames() {
        var existing: Set<String> = ["photo.jpg"]
        XCTAssertEqual(UniqueNameGenerator.keepBothName(for: "photo.jpg") { existing.contains($0) }, "photo 2.jpg")
        existing.insert("photo 2.jpg")
        XCTAssertEqual(UniqueNameGenerator.keepBothName(for: "photo.jpg") { existing.contains($0) }, "photo 3.jpg")
        XCTAssertEqual(UniqueNameGenerator.keepBothName(for: "photo 2.jpg") { existing.contains($0) }, "photo 3.jpg")
        XCTAssertEqual(UniqueNameGenerator.keepBothName(for: "a.tar.gz") { _ in false }, "a 2.tar.gz")
        XCTAssertEqual(UniqueNameGenerator.keepBothName(for: "v1.0", isDirectory: true) { _ in false }, "v1.0 2")
    }

    func testDuplicateNames() {
        var existing: Set<String> = []
        XCTAssertEqual(UniqueNameGenerator.duplicateName(for: "report.pdf") { existing.contains($0) }, "report copy.pdf")
        existing = ["report copy.pdf"]
        XCTAssertEqual(UniqueNameGenerator.duplicateName(for: "report.pdf") { existing.contains($0) }, "report copy 2.pdf")
        XCTAssertEqual(UniqueNameGenerator.duplicateName(for: "report copy.pdf") { existing.contains($0) }, "report copy 2.pdf")
    }

    func testNewFolderNames() {
        XCTAssertEqual(UniqueNameGenerator.newFolderName { _ in false }, "untitled folder")
        let existing: Set<String> = ["untitled folder", "untitled folder 2"]
        XCTAssertEqual(UniqueNameGenerator.newFolderName { existing.contains($0) }, "untitled folder 3")
    }

    func testBatchRenamePlan() {
        let dir = URL(fileURLWithPath: "/tmp/batch")
        let urls = ["IMG_1.jpg", "IMG_2.jpg", "notes.txt"].map { dir.appendingPathComponent($0) }
        let plan = BatchRenamePlanner.plan(for: urls, rule: .format(baseName: "Trip ", startIndex: 1, digits: 3, position: .after), existsOnDisk: { _ in false })
        XCTAssertEqual(plan.map(\.newName), ["Trip 001.jpg", "Trip 002.jpg", "Trip 003.txt"])
        XCTAssertTrue(plan.allSatisfy { $0.issue == nil })

        let replace = BatchRenamePlanner.plan(for: urls, rule: .replaceText(find: "img_", replacement: "", caseSensitive: false), existsOnDisk: { _ in false })
        XCTAssertEqual(replace.map(\.newName), ["1.jpg", "2.jpg", "notes.txt"])

        let collide = BatchRenamePlanner.plan(for: urls, rule: .replaceText(find: "IMG_1", replacement: "IMG_2", caseSensitive: true), existsOnDisk: { _ in false })
        XCTAssertEqual(collide[0].issue, .duplicateInBatch)
        XCTAssertEqual(collide[1].issue, .duplicateInBatch)

        let invalid = BatchRenamePlanner.plan(for: urls, rule: .addText("/", position: .before), existsOnDisk: { _ in false })
        XCTAssertEqual(invalid[0].issue, .invalid(.containsSlash))

        let onDisk = BatchRenamePlanner.plan(for: [urls[2]], rule: .addText("-old", position: .after), existsOnDisk: { $0.lastPathComponent == "notes-old.txt" })
        XCTAssertEqual(onDisk[0].issue, .existsOnDisk)

        // A case-only change is the same file on case-insensitive volumes, not a collision.
        let caseOnly = BatchRenamePlanner.plan(for: [urls[2]], rule: .changeCase(.upper), existsOnDisk: { _ in true })
        XCTAssertNil(caseOnly[0].issue)
    }
}

final class TypeDetectionTests: XCTestCase {
    func testExtensionClassification() {
        XCTAssertEqual(FileTypeClassifier.category(forName: "a.HEIC", isDirectory: false, isPackage: false), .image)
        XCTAssertEqual(FileTypeClassifier.category(forName: "a.mov", isDirectory: false, isPackage: false), .video)
        XCTAssertEqual(FileTypeClassifier.category(forName: "a.flac", isDirectory: false, isPackage: false), .audio)
        XCTAssertEqual(FileTypeClassifier.category(forName: "a.pdf", isDirectory: false, isPackage: false), .pdf)
        XCTAssertEqual(FileTypeClassifier.category(forName: "a.swift", isDirectory: false, isPackage: false), .code)
        XCTAssertEqual(FileTypeClassifier.category(forName: "a.json", isDirectory: false, isPackage: false), .text)
        XCTAssertEqual(FileTypeClassifier.category(forName: "a.tar.gz", isDirectory: false, isPackage: false), .archive)
        XCTAssertEqual(FileTypeClassifier.category(forName: "Safari.app", isDirectory: true, isPackage: true), .application)
        XCTAssertEqual(FileTypeClassifier.category(forName: "x.y", isDirectory: true, isPackage: false), .folder)
        XCTAssertEqual(FileTypeClassifier.category(forName: "README", isDirectory: false, isPackage: false), .other)
    }

    func testSniffing() {
        XCTAssertEqual(ContentSniffer.sniff(data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0])), .png)
        XCTAssertEqual(ContentSniffer.sniff(data: Data([0xFF, 0xD8, 0xFF, 0xE0])), .jpeg)
        XCTAssertEqual(ContentSniffer.sniff(data: Data("%PDF-1.7\n".utf8)), .pdf)
        XCTAssertEqual(ContentSniffer.sniff(data: Data("GIF89a....".utf8)), .gif)
        XCTAssertEqual(ContentSniffer.sniff(data: Data("RIFF\u{0}\u{0}\u{0}\u{0}WEBPVP8 ".utf8)), .webp)
        XCTAssertEqual(ContentSniffer.sniff(data: Data([0, 0, 0, 0x18] + Array("ftypheic".utf8))), .heif)
        XCTAssertEqual(ContentSniffer.sniff(data: Data([0, 0, 0, 0x18] + Array("ftypisom".utf8))), .mp4Family)
        XCTAssertEqual(ContentSniffer.sniff(data: Data("hello, world ✓".utf8)), .utf8Text)
        XCTAssertEqual(ContentSniffer.sniff(data: Data([0x00, 0x01, 0x02, 0x03])), .binary)
        XCTAssertEqual(ContentSniffer.sniff(data: Data()), .empty)
        // A multi-byte character cut off at the end of the sample is still text.
        let truncated = Data("ab✓".utf8).dropLast()
        XCTAssertEqual(ContentSniffer.sniff(data: Data(truncated)), .utf8Text)
    }

    func testSniffingIgnoresMisleadingExtension() throws {
        let dir = try TempDirectory()
        let fake = dir.url.appendingPathComponent("image.png")
        try Data("plain text, not a PNG".utf8).write(to: fake)
        XCTAssertEqual(ContentSniffer.sniff(url: fake), .utf8Text)
        XCTAssertEqual(ContentSniffer.category(for: .utf8Text), .text)
    }

    func testFormatting() {
        XCTAssertEqual(DisplayFormat.byteCount(0), "0 bytes")
        XCTAssertEqual(DisplayFormat.byteCount(999), "999 bytes")
        XCTAssertEqual(DisplayFormat.byteCount(5_700_000), "5.7 MB")
        XCTAssertEqual(DisplayFormat.byteCount(120_000_000_000), "120 GB")
        XCTAssertEqual(DisplayFormat.symbolicPermissions(0o755, isDirectory: true), "drwxr-xr-x")
        XCTAssertEqual(DisplayFormat.symbolicPermissions(0o4755, isDirectory: false), "-rwsr-xr-x")
        XCTAssertEqual(DisplayFormat.symbolicPermissions(0o1777, isDirectory: true), "drwxrwxrwt")
        XCTAssertEqual(DisplayFormat.octalPermissions(0o644), "0644")
        XCTAssertEqual(DisplayFormat.statusSummary(total: 34, selected: 0, selectedBytes: nil), "34 items")
        XCTAssertEqual(DisplayFormat.statusSummary(total: 34, selected: 1, selectedBytes: 5_700_000), "1 of 34 selected, 5.7 MB")
        XCTAssertEqual(DisplayFormat.duration(83.4), "1:23")
        XCTAssertEqual(DisplayFormat.duration(3725), "1:02:05")
    }
}
