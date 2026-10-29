import XCTest
@testable import ExplorerCore

final class SortingTests: XCTestCase {
    let items = [
        item("file10.txt", size: 10, modified: 300),
        item("File2.txt", size: 200, modified: 100),
        item("beta", dir: true, modified: 50),
        item("alpha.png", size: 5, modified: 200),
        item("Alpha", dir: true, modified: 400),
    ]

    func testNameAscendingDirectoriesFirstNumericAndCaseInsensitive() {
        let sorted = FileSorter.sorted(items, by: FileSortDescriptor(key: .name)).map(\.name)
        XCTAssertEqual(sorted, ["Alpha", "beta", "alpha.png", "File2.txt", "file10.txt"])
    }

    func testNameDescendingKeepsDirectoriesFirst() {
        let sorted = FileSorter.sorted(items, by: FileSortDescriptor(key: .name, ascending: false)).map(\.name)
        XCTAssertEqual(sorted, ["beta", "Alpha", "file10.txt", "File2.txt", "alpha.png"])
    }

    func testMixedWhenDirectoriesFirstDisabled() {
        let sorted = FileSorter.sorted(items, by: FileSortDescriptor(key: .name, directoriesFirst: false)).map(\.name)
        XCTAssertEqual(sorted, ["Alpha", "alpha.png", "beta", "File2.txt", "file10.txt"])
    }

    func testSizeSortTreatsFoldersAsSmallest() {
        let d = FileSortDescriptor(key: .size, ascending: false, directoriesFirst: false)
        XCTAssertEqual(FileSorter.sorted(items, by: d).map(\.name), ["File2.txt", "file10.txt", "alpha.png", "Alpha", "beta"])
    }

    func testDateModifiedSort() {
        let d = FileSortDescriptor(key: .dateModified, ascending: true, directoriesFirst: false)
        XCTAssertEqual(FileSorter.sorted(items, by: d).map(\.name), ["beta", "File2.txt", "alpha.png", "file10.txt", "Alpha"])
    }

    func testKindSortGroupsByKindThenName() {
        let d = FileSortDescriptor(key: .kind, directoriesFirst: false)
        let sorted = FileSorter.sorted(items, by: d).map(\.kindDescription)
        XCTAssertEqual(sorted, sorted.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    func testSortIsDeterministicForTies() {
        let ties = [item("b", size: 1), item("a", size: 1), item("c", size: 1)]
        let d = FileSortDescriptor(key: .size, ascending: false)
        XCTAssertEqual(FileSorter.sorted(ties, by: d).map(\.name), ["a", "b", "c"])
    }

    func testTenThousandItemsSortQuickly() {
        let many = (0..<10_000).map { item("file \($0).dat", size: Int64($0 % 977), modified: Double($0 * 7 % 1000)) }
        measure {
            _ = FileSorter.sorted(many, by: FileSortDescriptor(key: .name))
        }
    }
}

final class FilterTests: XCTestCase {
    let items = [
        item(".hidden"),
        item("Report 2024.pdf"),
        item("photo.JPG"),
        item("photo_raw.dng"),
        item("Café notes.txt"),
        item("Projects", dir: true),
        item("flagged", hidden: true),
    ]

    func testHiddenFilesHiddenByDefault() {
        let names = FileFilter().apply(to: items).map(\.name)
        XCTAssertFalse(names.contains(".hidden"))
        XCTAssertFalse(names.contains("flagged"))
        XCTAssertEqual(names.count, 5)
    }

    func testShowHidden() {
        XCTAssertEqual(FileFilter(showHidden: true).apply(to: items).count, items.count)
    }

    func testSubstringSearchIsCaseAndDiacriticInsensitive() {
        XCTAssertEqual(FileFilter(query: "cafe").apply(to: items).map(\.name), ["Café notes.txt"])
        XCTAssertEqual(FileFilter(query: "REPORT").apply(to: items).map(\.name), ["Report 2024.pdf"])
    }

    func testMultipleTermsMustAllMatch() {
        XCTAssertEqual(FileFilter(query: "photo raw").apply(to: items).map(\.name), ["photo_raw.dng"])
    }

    func testWildcards() {
        XCTAssertEqual(FileFilter(query: "*.jpg").apply(to: items).map(\.name), ["photo.JPG"])
        XCTAssertEqual(FileFilter(query: "photo.???").apply(to: items).map(\.name), ["photo.JPG"])
        XCTAssertTrue(WildcardMatcher.matches("abc", pattern: "a*c"))
        XCTAssertTrue(WildcardMatcher.matches("abc", pattern: "*"))
        XCTAssertFalse(WildcardMatcher.matches("abc", pattern: "a?"))
        XCTAssertTrue(WildcardMatcher.matches("a.tar.gz", pattern: "*.gz"))
    }

    func testKindAndExtensionTokens() {
        XCTAssertEqual(FileFilter(query: "kind:folder").apply(to: items).map(\.name), ["Projects"])
        XCTAssertEqual(Set(FileFilter(query: "kind:image").apply(to: items).map(\.name)), ["photo.JPG", "photo_raw.dng"])
        XCTAssertEqual(FileFilter(query: "ext:pdf").apply(to: items).map(\.name), ["Report 2024.pdf"])
        XCTAssertEqual(FileFilter(query: "ext:.PDF").apply(to: items).map(\.name), ["Report 2024.pdf"])
    }

    func testSearchStillRespectsHiddenToggle() {
        XCTAssertTrue(FileFilter(query: "hidden").apply(to: items).isEmpty)
        XCTAssertEqual(FileFilter(showHidden: true, query: "hidden").apply(to: items).map(\.name), [".hidden"])
    }

    func testIsSearching() {
        XCTAssertFalse(FileFilter(query: "   ").isSearching)
        XCTAssertTrue(FileFilter(query: "a").isSearching)
    }
}
