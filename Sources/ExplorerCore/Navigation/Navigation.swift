import Foundation

/// Back/forward history for one tab.
public struct NavigationHistory: Codable, Equatable, Sendable {
    public private(set) var backStack: [URL]
    public private(set) var current: URL
    public private(set) var forwardStack: [URL]
    public let limit: Int

    public init(start: URL, limit: Int = 100) {
        self.backStack = []
        self.current = start.standardizedFileURL
        self.forwardStack = []
        self.limit = max(1, limit)
    }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }

    /// Records a new location. Visiting the current location is a no-op.
    public mutating func visit(_ url: URL) {
        let target = url.standardizedFileURL
        guard target != current else { return }
        backStack.append(current)
        if backStack.count > limit { backStack.removeFirst(backStack.count - limit) }
        forwardStack.removeAll()
        current = target
    }

    @discardableResult
    public mutating func goBack() -> URL? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(current)
        current = previous
        return previous
    }

    @discardableResult
    public mutating func goForward() -> URL? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(current)
        current = next
        return next
    }

    /// Replaces the current entry without touching the stacks (used when a folder is
    /// renamed or when recovering from a vanished folder).
    public mutating func replaceCurrent(with url: URL) {
        current = url.standardizedFileURL
    }
}

public struct Breadcrumb: Hashable, Sendable, Identifiable {
    public var id: String { url.path }
    public let name: String
    public let url: URL
}

public enum PathBreadcrumbs {
    /// Components from the root (or from the home folder when `url` is inside it) to
    /// `url`. `rootName` labels "/" (for example the startup volume name).
    public static func components(for url: URL, home: URL? = nil, rootName: String = "/") -> [Breadcrumb] {
        let target = url.standardizedFileURL
        var result: [Breadcrumb] = []
        if let home = home?.standardizedFileURL, isDescendant(target, of: home, orEqual: true) {
            result.append(Breadcrumb(name: home.lastPathComponent, url: home))
            var current = home
            let homeCount = home.pathComponents.count
            for component in target.pathComponents.dropFirst(homeCount) {
                current.appendPathComponent(component)
                result.append(Breadcrumb(name: component, url: current))
            }
            return result
        }
        var current = URL(fileURLWithPath: "/")
        result.append(Breadcrumb(name: rootName, url: current))
        for component in target.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            result.append(Breadcrumb(name: component, url: current))
        }
        return result
    }

    /// True when `url` lies strictly inside `ancestor` (or equals it if `orEqual`).
    public static func isDescendant(_ url: URL, of ancestor: URL, orEqual: Bool = false) -> Bool {
        let a = ancestor.standardizedFileURL.pathComponents
        let u = url.standardizedFileURL.pathComponents
        if u.count < a.count { return false }
        if u.count == a.count { return orEqual && u == a }
        return Array(u.prefix(a.count)) == a
    }

    /// `~/Documents` style display path.
    public static func abbreviated(_ url: URL, home: URL) -> String {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if path == homePath { return "~" }
        if isDescendant(url, of: home) { return "~" + path.dropFirst(homePath.count) }
        return path
    }
}

/// Resolves text typed in the editable path field.
public enum PathInputParser {
    /// Accepts absolute paths, `~`, `~/sub`, `file://` URLs and paths relative to
    /// `base`. Returns `nil` for empty input or unsupported URL schemes.
    public static func resolve(_ input: String, relativeTo base: URL, home: URL) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if text.hasPrefix("\"") && text.hasSuffix("\"") && text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }
        if text.lowercased().hasPrefix("file://") {
            return URL(string: text).flatMap { $0.isFileURL ? $0.standardizedFileURL : nil }
        }
        if text.contains("://") { return nil }
        if text == "~" { return home.standardizedFileURL }
        if text.hasPrefix("~/") {
            return home.appendingPathComponent(String(text.dropFirst(2))).standardizedFileURL
        }
        if text.hasPrefix("/") { return URL(fileURLWithPath: text).standardizedFileURL }
        return base.appendingPathComponent(text).standardizedFileURL
    }
}

/// Most-recently-visited folders, newest first, de-duplicated.
public struct RecentLocations: Codable, Equatable, Sendable {
    public private(set) var paths: [String]
    public let limit: Int

    public init(paths: [String] = [], limit: Int = 12) {
        self.limit = limit
        self.paths = Array(paths.prefix(limit))
    }

    public mutating func record(_ url: URL) {
        let path = url.standardizedFileURL.path
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > limit { paths.removeLast(paths.count - limit) }
    }

    public mutating func remove(_ path: String) { paths.removeAll { $0 == path } }
    public mutating func clear() { paths.removeAll() }
}
