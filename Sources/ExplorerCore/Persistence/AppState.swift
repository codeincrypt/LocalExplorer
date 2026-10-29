import Foundation

public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system, light, dark
    public var title: String { rawValue.capitalized }
}

/// Tint behind the glass panels.
public enum GlassTint: String, Codable, CaseIterable, Sendable {
    case ocean, aurora, sunset, graphite, mint
    /// Uses `AppPreferences.glassCustomColor`.
    case custom
    public var title: String { rawValue.capitalized }
}

/// An sRGB colour chosen by the user, stored as plain components so it stays Codable
/// and free of UI types.
public struct GlassColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    public static let `default` = GlassColor(red: 0.16, green: 0.42, blue: 0.98)

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GlassColor.default
        self.init(
            red: (try? c.decode(Double.self, forKey: .red)) ?? d.red,
            green: (try? c.decode(Double.self, forKey: .green)) ?? d.green,
            blue: (try? c.decode(Double.self, forKey: .blue)) ?? d.blue
        )
    }

    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

/// How frosted the panels are.
public enum GlassIntensity: String, Codable, CaseIterable, Sendable {
    case clear, balanced, frosted
    public var title: String { rawValue.capitalized }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var defaultViewMode: ViewMode = .details
    public var sort = FileSortDescriptor()
    public var showHiddenFiles = false
    public var showPreviewPane = true
    public var showSidebar = true
    public var tileSize: Double = 112
    public var sidebarWidth: Double = 220
    public var previewPaneWidth: Double = 300
    /// Absolute path of the folder new tabs open; `nil` means the home folder.
    public var startPath: String?
    public var appearance: AppearanceMode = .system
    public var glassTint: GlassTint = .ocean
    public var glassIntensity: GlassIntensity = .balanced
    /// Colour used when `glassTint` is `.custom`.
    public var glassCustomColor = GlassColor.default
    /// How see-through the glass panels are: 0 is the normal frosted look, higher values
    /// let more of the backdrop show through.
    public var glassTransparency: Double = 0
    /// Use the system Liquid Glass material on macOS 26 and later.
    public var useLiquidGlass = true
    public var restoreTabs = true
    public var thumbnailCacheLimitMB: Int = 256

    /// Upper bound for `glassTransparency`; beyond this the panels lose their shape.
    public static let maxGlassTransparency: Double = 0.85

    public init() {}

    // Tolerant decoding: unknown or missing keys fall back to defaults so an older or
    // newer preferences file never prevents launch.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppPreferences()
        defaultViewMode = (try? c.decode(ViewMode.self, forKey: .defaultViewMode)) ?? d.defaultViewMode
        sort = (try? c.decode(FileSortDescriptor.self, forKey: .sort)) ?? d.sort
        showHiddenFiles = (try? c.decode(Bool.self, forKey: .showHiddenFiles)) ?? d.showHiddenFiles
        showPreviewPane = (try? c.decode(Bool.self, forKey: .showPreviewPane)) ?? d.showPreviewPane
        showSidebar = (try? c.decode(Bool.self, forKey: .showSidebar)) ?? d.showSidebar
        tileSize = (try? c.decode(Double.self, forKey: .tileSize)) ?? d.tileSize
        sidebarWidth = (try? c.decode(Double.self, forKey: .sidebarWidth)) ?? d.sidebarWidth
        previewPaneWidth = (try? c.decode(Double.self, forKey: .previewPaneWidth)) ?? d.previewPaneWidth
        startPath = try? c.decodeIfPresent(String.self, forKey: .startPath)
        appearance = (try? c.decode(AppearanceMode.self, forKey: .appearance)) ?? d.appearance
        glassTint = (try? c.decode(GlassTint.self, forKey: .glassTint)) ?? d.glassTint
        glassIntensity = (try? c.decode(GlassIntensity.self, forKey: .glassIntensity)) ?? d.glassIntensity
        glassCustomColor = (try? c.decode(GlassColor.self, forKey: .glassCustomColor)) ?? d.glassCustomColor
        let transparency = (try? c.decode(Double.self, forKey: .glassTransparency)) ?? d.glassTransparency
        glassTransparency = transparency.isFinite ? min(max(transparency, 0), Self.maxGlassTransparency) : d.glassTransparency
        useLiquidGlass = (try? c.decode(Bool.self, forKey: .useLiquidGlass)) ?? d.useLiquidGlass
        restoreTabs = (try? c.decode(Bool.self, forKey: .restoreTabs)) ?? d.restoreTabs
        thumbnailCacheLimitMB = (try? c.decode(Int.self, forKey: .thumbnailCacheLimitMB)) ?? d.thumbnailCacheLimitMB
    }
}

/// A user-chosen location (favorite or authorized folder). `bookmark` holds
/// security-scoped bookmark data when available so access survives relaunch.
public struct StoredLocation: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String
    public var bookmark: Data?

    public init(id: UUID = UUID(), name: String, path: String, bookmark: Data? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmark = bookmark
    }
}

/// Everything Local Explorer persists. Contains no file contents and is never treated
/// as an inventory of the filesystem.
public struct AppState: Codable, Equatable, Sendable {
    public var version = 1
    public var preferences = AppPreferences()
    public var favorites: [StoredLocation] = []
    public var authorizedLocations: [StoredLocation] = []
    public var recents = RecentLocations()
    public var openTabs: [String] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        preferences = (try? c.decode(AppPreferences.self, forKey: .preferences)) ?? AppPreferences()
        favorites = (try? c.decode([StoredLocation].self, forKey: .favorites)) ?? []
        authorizedLocations = (try? c.decode([StoredLocation].self, forKey: .authorizedLocations)) ?? []
        recents = (try? c.decode(RecentLocations.self, forKey: .recents)) ?? RecentLocations()
        openTabs = (try? c.decode([String].self, forKey: .openTabs)) ?? []
    }

    public mutating func addFavorite(_ location: StoredLocation) {
        guard !favorites.contains(where: { $0.path == location.path }) else { return }
        favorites.append(location)
    }

    public mutating func removeFavorite(id: UUID) { favorites.removeAll { $0.id == id } }

    public mutating func moveFavorite(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().map { favorites[$0] }
        for index in source.sorted(by: >) { favorites.remove(at: index) }
        let adjusted = destination - source.filter { $0 < destination }.count
        favorites.insert(contentsOf: moving, at: max(0, min(adjusted, favorites.count)))
    }
}

/// Atomic JSON persistence in Application Support. A corrupt file is moved aside and
/// defaults are used instead of failing.
public struct JSONFileStore<Value: Codable>: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public static func applicationSupportFile(appFolder: String, name: String) -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appFolder, isDirectory: true).appendingPathComponent(name)
    }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return nil
        }
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: fileURL, options: .atomic)
    }
}

/// Key for cached thumbnails. Any change to the file's identity, size or modification
/// date produces a different key, which invalidates stale entries automatically.
public struct ThumbnailCacheKey: Hashable, Sendable {
    public let path: String
    public let modificationDate: Date?
    public let size: Int64?
    public let pixelSize: Int

    public init(item: FileItem, pixelSize: Int) {
        self.path = item.id
        self.modificationDate = item.modificationDate
        self.size = item.size
        self.pixelSize = pixelSize
    }

    public var stringValue: String {
        let date = modificationDate.map { String(format: "%.3f", $0.timeIntervalSince1970) } ?? "-"
        return "\(path)|\(date)|\(size.map(String.init) ?? "-")|\(pixelSize)"
    }

    /// Rounds requested sizes into buckets so small layout changes reuse cache entries.
    public static func bucket(forPixels pixels: Double) -> Int {
        let buckets = [32, 64, 128, 256, 512, 1024, 2048]
        return buckets.first { Double($0) >= pixels } ?? 2048
    }
}
