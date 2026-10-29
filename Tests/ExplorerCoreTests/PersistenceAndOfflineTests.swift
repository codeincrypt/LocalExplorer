import XCTest
@testable import ExplorerCore

final class PersistenceTests: XCTestCase {
    func testRoundTripAcrossRelaunch() throws {
        let dir = try TempDirectory()
        let store = JSONFileStore<AppState>(fileURL: dir.url.appendingPathComponent("Support/state.json"))
        var state = AppState()
        state.preferences.defaultViewMode = .tiles
        state.preferences.showHiddenFiles = true
        state.preferences.sort = FileSortDescriptor(key: .size, ascending: false, directoriesFirst: false)
        state.addFavorite(StoredLocation(name: "Projects", path: "/Users/k/Projects", bookmark: Data([1, 2, 3])))
        state.addFavorite(StoredLocation(name: "Projects dup", path: "/Users/k/Projects"))
        state.recents.record(URL(fileURLWithPath: "/tmp"))
        state.openTabs = ["/Users/k", "/tmp"]
        try store.save(state)

        // A fresh store instance simulates the next launch.
        let reloaded = try XCTUnwrap(JSONFileStore<AppState>(fileURL: store.fileURL).load())
        XCTAssertEqual(reloaded, state)
        XCTAssertEqual(reloaded.favorites.count, 1, "duplicate favorites are ignored")
    }

    func testCorruptFileFallsBackAndIsMovedAside() throws {
        let dir = try TempDirectory()
        let url = dir.url.appendingPathComponent("state.json")
        try Data("{ not json".utf8).write(to: url)
        XCTAssertNil(JSONFileStore<AppState>(fileURL: url).load())
        XCTAssertTrue(dir.exists("state.corrupt.json"))
        XCTAssertFalse(dir.exists("state.json"))
    }

    func testTolerantDecodingOfOlderOrNewerFiles() throws {
        let json = #"{"preferences":{"defaultViewMode":"gallery","futureSetting":42,"glassTint":"unknown-tint"},"favorites":[]}"#
        let state = try JSONDecoder().decode(AppState.self, from: Data(json.utf8))
        XCTAssertEqual(state.preferences.defaultViewMode, .gallery)
        XCTAssertEqual(state.preferences.glassTint, .ocean)
        XCTAssertEqual(state.preferences.sort, FileSortDescriptor())
    }

    func testGlassColorAndTransparencyRoundTrip() throws {
        var state = AppState()
        state.preferences.glassTint = .custom
        state.preferences.glassCustomColor = GlassColor(red: 0.9, green: 0.2, blue: 0.4)
        state.preferences.glassTransparency = 0.4
        let data = try JSONEncoder().encode(state)
        let reloaded = try JSONDecoder().decode(AppState.self, from: data)
        XCTAssertEqual(reloaded.preferences.glassTint, .custom)
        XCTAssertEqual(reloaded.preferences.glassCustomColor, GlassColor(red: 0.9, green: 0.2, blue: 0.4))
        XCTAssertEqual(reloaded.preferences.glassTransparency, 0.4)
    }

    func testGlassSettingsDefaultAndClampWhenMissingOrOutOfRange() throws {
        let older = try JSONDecoder().decode(AppState.self, from: Data(#"{"preferences":{"glassTint":"mint"}}"#.utf8))
        XCTAssertEqual(older.preferences.glassTransparency, 0)
        XCTAssertEqual(older.preferences.glassCustomColor, GlassColor.default)

        let wild = #"{"preferences":{"glassTransparency":7,"glassCustomColor":{"red":2,"green":-1}}}"#
        let state = try JSONDecoder().decode(AppState.self, from: Data(wild.utf8))
        XCTAssertEqual(state.preferences.glassTransparency, AppPreferences.maxGlassTransparency)
        XCTAssertEqual(state.preferences.glassCustomColor.red, 1)
        XCTAssertEqual(state.preferences.glassCustomColor.green, 0)
        XCTAssertEqual(state.preferences.glassCustomColor.blue, GlassColor.default.blue)
    }

    func testFavoriteReordering() {
        var state = AppState()
        for n in ["a", "b", "c"] { state.addFavorite(StoredLocation(name: n, path: "/" + n)) }
        state.moveFavorite(from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(state.favorites.map(\.name), ["b", "c", "a"])
    }

    func testThumbnailKeyInvalidatesOnChange() {
        let url = URL(fileURLWithPath: "/p/photo.jpg")
        let original = FileItem(url: url, isDirectory: false, size: 100, modificationDate: Date(timeIntervalSince1970: 1))
        let edited = FileItem(url: url, isDirectory: false, size: 100, modificationDate: Date(timeIntervalSince1970: 2))
        let resized = FileItem(url: url, isDirectory: false, size: 101, modificationDate: Date(timeIntervalSince1970: 1))
        let same = FileItem(url: url, isDirectory: false, size: 100, modificationDate: Date(timeIntervalSince1970: 1))
        let k = ThumbnailCacheKey(item: original, pixelSize: 256)
        XCTAssertEqual(k, ThumbnailCacheKey(item: same, pixelSize: 256))
        XCTAssertNotEqual(k.stringValue, ThumbnailCacheKey(item: edited, pixelSize: 256).stringValue)
        XCTAssertNotEqual(k.stringValue, ThumbnailCacheKey(item: resized, pixelSize: 256).stringValue)
        XCTAssertNotEqual(k.stringValue, ThumbnailCacheKey(item: original, pixelSize: 512).stringValue)
        XCTAssertEqual(ThumbnailCacheKey.bucket(forPixels: 100), 128)
        XCTAssertEqual(ThumbnailCacheKey.bucket(forPixels: 5000), 2048)
    }
}

/// Static guard for the offline requirement: no source file may use networking APIs or
/// reference remote resources. Runtime instrumentation is documented in docs/PRIVACY.md.
final class OfflineSourceScanTests: XCTestCase {
    static let forbidden = [
        "URLSession", "NSURLConnection", "NWConnection", "NWPathMonitor", "NWBrowser", "NWListener",
        "CFStream", "WKWebView", "SFSafariViewController", "http://", "https://", "CFSocket", "getaddrinfo",
        "import Network", "import WebKit", "import FirebaseCore", "import Sentry", "TelemetryDeck",
    ]

    func testSourcesContainNoNetworkingAPIs() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = packageRoot.appendingPathComponent("Sources")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var scanned = 0
        var violations: [String] = []
        while let url = enumerator.nextObject() as? URL {
            guard ["swift", "plist", "m", "h"].contains(url.pathExtension) else { continue }
            scanned += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            for (lineNumber, line) in text.components(separatedBy: .newlines).enumerated() {
                for token in Self.forbidden where line.contains(token) {
                    violations.append("\(url.lastPathComponent):\(lineNumber + 1) uses \(token)")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 10)
        XCTAssertEqual(violations, [], violations.joined(separator: "\n"))
    }
}
