import Foundation
import XCTest
@testable import ExplorerCore

final class PreviewSelectionTests: XCTestCase {
    private func kind(_ name: String, _ bytes: [UInt8], dir: Bool = false) -> PreviewKind {
        let file = item(name, dir: dir)
        return PreviewSelector.kind(for: file, signature: ContentSniffer.sniff(data: Data(bytes)))
    }

    private let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]
    private let pdf = Array("%PDF-1.7\n".utf8)
    private let zip: [UInt8] = [0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0]
    private let mp4: [UInt8] = [0, 0, 0, 0x18] + Array("ftypisom".utf8) + [0, 0, 0, 0]
    private let m4a: [UInt8] = [0, 0, 0, 0x18] + Array("ftypM4A ".utf8) + [0, 0, 0, 0]

    func testContentWinsOverExtension() {
        XCTAssertEqual(kind("photo.txt", png), .image, "PNG bytes in a .txt file are an image")
        XCTAssertEqual(kind("notes.jpg", Array("hello world\n".utf8)), .text, "text in a .jpg is text")
        XCTAssertEqual(kind("report.png", pdf), .pdf)
    }

    func testCommonTypes() {
        XCTAssertEqual(kind("a.png", png), .image)
        XCTAssertEqual(kind("a.pdf", pdf), .pdf)
        XCTAssertEqual(kind("movie.mp4", mp4), .video)
        XCTAssertEqual(kind("song.m4a", m4a), .audio, "ISO media with an audio extension is audio")
        XCTAssertEqual(kind("song.mp3", Array("ID3".utf8) + [3, 0, 0]), .audio)
        XCTAssertEqual(kind("main.swift", Array("import Foundation\n".utf8)), .text)
        XCTAssertEqual(kind("empty.txt", []), .text)
    }

    func testZipContainers() {
        XCTAssertEqual(kind("letter.docx", zip), .quickLook)
        XCTAssertEqual(kind("budget.xlsx", zip), .quickLook)
        XCTAssertEqual(kind("bundle.zip", zip), .fallback, "archives are not previewed")
    }

    func testRichTextAndSVGUseQuickLook() {
        XCTAssertEqual(kind("doc.rtf", Array("{\\rtf1\\ansi hello}".utf8)), .quickLook)
        XCTAssertEqual(kind("logo.svg", Array("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8)), .quickLook)
    }

    func testBinaryFallsBackByCategory() {
        let binary: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0xFF, 0x00]
        XCTAssertEqual(kind("clip.mkv", binary), .video)
        XCTAssertEqual(kind("photo.cr2", binary), .image)
        XCTAssertEqual(kind("font.ttf", binary), .quickLook)
        XCTAssertEqual(kind("fake.pdf", binary), .fallback, "a .pdf without a PDF header is not sent to PDFKit")
        XCTAssertEqual(kind("program", binary), .fallback)
    }

    func testFoldersPackagesAndUnreadable() {
        XCTAssertEqual(PreviewSelector.kind(for: item("Folder", dir: true), signature: nil), .folder)
        let app = FileItem(url: URL(fileURLWithPath: "/Applications/X.app"), isDirectory: true, isPackage: true)
        XCTAssertEqual(PreviewSelector.kind(for: app, signature: nil), .fallback)
        let pages = FileItem(url: URL(fileURLWithPath: "/tmp/Doc.pages"), isDirectory: true, isPackage: true)
        XCTAssertEqual(PreviewSelector.kind(for: pages, signature: nil), .quickLook)
        XCTAssertEqual(PreviewSelector.kind(for: item("a.png"), signature: nil), .fallback, "unreadable header")
        let broken = FileItem(url: URL(fileURLWithPath: "/tmp/link"), isDirectory: false, isSymbolicLink: true, isBrokenSymbolicLink: true)
        XCTAssertEqual(PreviewSelector.kind(for: broken, signature: .png), .fallback)
    }
}

final class TextPreviewTests: XCTestCase {
    private func content(_ result: TextPreviewResult, file: StaticString = #filePath, line: UInt = #line) -> TextPreviewContent? {
        guard case .text(let c) = result else {
            XCTFail("expected text, got \(result)", file: file, line: line)
            return nil
        }
        return c
    }

    func testUTF8WithAndWithoutBOM() {
        let plain = content(TextPreviewLoader.decode(Data("héllo\nworld\n".utf8), totalBytes: 13))
        XCTAssertEqual(plain?.text, "héllo\nworld\n")
        XCTAssertEqual(plain?.encodingName, "UTF-8")
        XCTAssertEqual(plain?.lineCount, 2)
        XCTAssertEqual(plain?.isTruncated, false)

        let bom = content(TextPreviewLoader.decode(Data([0xEF, 0xBB, 0xBF] + Array("a".utf8)), totalBytes: 4))
        XCTAssertEqual(bom?.text, "a")
        XCTAssertEqual(bom?.lineCount, 1)
    }

    func testUTF16WithBOM() {
        var bytes: [UInt8] = [0xFF, 0xFE]
        for unit in "Hi ✓".utf16 { bytes += [UInt8(unit & 0xFF), UInt8(unit >> 8)] }
        let c = content(TextPreviewLoader.decode(Data(bytes), totalBytes: Int64(bytes.count)))
        XCTAssertEqual(c?.text, "Hi ✓")
        XCTAssertEqual(c?.encodingName, "UTF-16 LE")
    }

    func testLegacyEncodingFallback() {
        // "café" in Windows-1252 (0xE9 is not valid UTF-8 on its own).
        let c = content(TextPreviewLoader.decode(Data([0x63, 0x61, 0x66, 0xE9]), totalBytes: 4))
        XCTAssertEqual(c?.text, "café")
        XCTAssertTrue(c?.encodingName.hasPrefix("Western") ?? false)
    }

    func testBinaryIsRejected() {
        XCTAssertEqual(TextPreviewLoader.decode(Data([0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x00, 0x00]), totalBytes: 8), .binary)
        let controls = Data((0..<100).map { UInt8($0 % 8 + 1) })
        XCTAssertEqual(TextPreviewLoader.decode(controls, totalBytes: 100), .binary)
    }

    func testTruncationKeepsSplitMultibyteCharacter() {
        // "€" is E2 82 AC; cut after two bytes, as a size limit would.
        let data = Data(Array("price ".utf8) + [0xE2, 0x82])
        let c = content(TextPreviewLoader.decode(data, totalBytes: 1_000))
        XCTAssertEqual(c?.text, "price ")
        XCTAssertEqual(c?.isTruncated, true)
        XCTAssertEqual(c?.totalBytes, 1_000)
    }

    func testLoadHonoursLimitAndReportsMissingFiles() throws {
        let dir = try TempDirectory()
        let big = try dir.file("big.log", String(repeating: "line\n", count: 10_000))
        let c = content(TextPreviewLoader.load(url: big, limit: 1_000))
        XCTAssertEqual(c?.text.utf8.count, 1_000)
        XCTAssertEqual(c?.isTruncated, true)
        XCTAssertEqual(c?.totalBytes, 50_000)

        if case .unreadable = TextPreviewLoader.load(url: dir.url.appendingPathComponent("missing.txt")) {} else {
            XCTFail("missing file should be unreadable")
        }
    }
}

final class ZoomMathTests: XCTestCase {
    func testFitScale() {
        // The 4032 × 3024 photo from the design mock in a 386 × 290 pane ≈ 9.6%.
        let s = ZoomMath.fitScale(content: (4032, 3024), container: (386, 290))
        XCTAssertEqual(s, 386.0 / 4032.0, accuracy: 0.0001, "width is the limiting side")
        XCTAssertEqual(ZoomMath.percent(s), "9.6%")
        XCTAssertEqual(ZoomMath.fitScale(content: (100, 100), container: (500, 500)), 1, "no upscaling by default")
        XCTAssertEqual(ZoomMath.fitScale(content: (100, 100), container: (500, 500), allowUpscale: true), 5)
        XCTAssertEqual(ZoomMath.fitScale(content: (0, 0), container: (10, 10)), 1)
    }

    func testZoomSteps() {
        XCTAssertEqual(ZoomMath.zoomIn(from: 1), 1.25)
        XCTAssertEqual(ZoomMath.zoomOut(from: 1), 0.75)
        XCTAssertEqual(ZoomMath.zoomIn(from: 0.096), 0.1)
        XCTAssertEqual(ZoomMath.zoomIn(from: 16), ZoomMath.range.upperBound)
        XCTAssertEqual(ZoomMath.zoomOut(from: 0.05), ZoomMath.range.lowerBound)
        XCTAssertEqual(ZoomMath.percent(1), "100%")
        XCTAssertEqual(ZoomMath.percent(2.5), "250%")
    }

    func testRotation() {
        XCTAssertEqual(ZoomMath.normalizedTurns(-1), 3)
        XCTAssertEqual(ZoomMath.normalizedTurns(5), 1)
        XCTAssertTrue(ZoomMath.rotatedSize(width: 4, height: 3, quarterTurns: 1) == (3, 4))
        XCTAssertTrue(ZoomMath.rotatedSize(width: 4, height: 3, quarterTurns: 2) == (4, 3))
    }
}
