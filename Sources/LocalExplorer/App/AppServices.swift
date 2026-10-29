import AppKit
import SwiftUI
import ExplorerCore

/// Product configuration. The name comes from the bundle so it can be changed at build
/// time (see scripts/build-app.sh) without touching code.
enum AppConfiguration {
    static var productName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Local Explorer"
    }

    static var supportFolderName: String { Bundle.main.bundleIdentifier ?? "LocalExplorer" }
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL }

    /// Testing hooks (used by the UI tests; harmless otherwise):
    /// `LOCAL_EXPLORER_START_PATH` opens that folder instead of the saved start folder,
    /// `LOCAL_EXPLORER_STATE_FILE` stores state in that file instead of Application Support.
    static var environmentStartPath: String? {
        ProcessInfo.processInfo.environment["LOCAL_EXPLORER_START_PATH"]
    }

    static var stateFileURL: URL {
        if let path = ProcessInfo.processInfo.environment["LOCAL_EXPLORER_STATE_FILE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return JSONFileStore<AppState>.applicationSupportFile(appFolder: supportFolderName, name: "State.json")
    }
}

/// Shared, app-wide services. Owned by the main actor; heavy work happens in the
/// filesystem and operation layers off the main thread.
@MainActor
final class AppServices: ObservableObject {
    static let shared = AppServices()

    @Published var state: AppState {
        didSet { if state != oldValue { scheduleSave() } }
    }
    /// Availability of authorized locations and favorites after bookmark resolution.
    @Published private(set) var unavailableLocationIDs: Set<UUID> = []

    let store: JSONFileStore<AppState>
    let access = AccessManager()
    let volumes = VolumeMonitor()
    let thumbnails = ThumbnailService()
    let clipboard = FileClipboard()
    let engine = FileOperationEngine()
    let fileSystem: FileSystemProviding = LocalFileSystem()
    private var saveWorkItem: DispatchWorkItem?

    private init() {
        store = JSONFileStore(fileURL: AppConfiguration.stateFileURL)
        state = store.load() ?? AppState()
        thumbnails.setLimit(megabytes: state.preferences.thumbnailCacheLimitMB)
        restoreLocations()
    }

    var preferences: AppPreferences {
        get { state.preferences }
        set { state.preferences = newValue }
    }

    var startURL: URL {
        if let path = AppConfiguration.environmentStartPath ?? preferences.startPath {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: path)
            }
        }
        return ThisMac.url
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        do {
            try store.save(state)
        } catch {
            NSLog("Local Explorer: could not save state: \(error.localizedDescription)")
        }
    }

    // MARK: Places

    func recordVisit(_ url: URL) {
        state.recents.record(url)
    }

    func clearRecents() { state.recents.clear() }

    func isFavorite(_ url: URL) -> Bool {
        state.favorites.contains { $0.path == url.standardizedFileURL.path }
    }

    func addFavorite(_ url: URL) {
        let standardized = url.standardizedFileURL
        let location = StoredLocation(
            name: FileManager.default.displayName(atPath: standardized.path),
            path: standardized.path,
            bookmark: access.bookmark(for: standardized)
        )
        state.addFavorite(location)
    }

    func removeFavorite(_ id: UUID) { state.removeFavorite(id: id) }

    func moveFavorites(from source: IndexSet, to destination: Int) {
        state.moveFavorite(from: source, to: destination)
    }

    /// Asks the user to pick a folder and remembers access to it across launches.
    @discardableResult
    func grantAccess(suggesting url: URL? = nil) -> URL? {
        guard let picked = access.requestFolderAccess(startingAt: url) else { return nil }
        let standardized = picked.standardizedFileURL
        if !state.authorizedLocations.contains(where: { $0.path == standardized.path }) {
            state.authorizedLocations.append(StoredLocation(
                name: FileManager.default.displayName(atPath: standardized.path),
                path: standardized.path,
                bookmark: access.bookmark(for: standardized)
            ))
        }
        access.startAccessing(standardized)
        unavailableLocationIDs.subtract(state.authorizedLocations.filter { $0.path == standardized.path }.map(\.id))
        return standardized
    }

    func removeAuthorizedLocation(_ id: UUID) {
        if let location = state.authorizedLocations.first(where: { $0.id == id }) {
            access.stopAccessing(URL(fileURLWithPath: location.path))
        }
        state.authorizedLocations.removeAll { $0.id == id }
    }

    /// Resolves stored bookmarks, follows moved folders, refreshes stale bookmarks and
    /// starts security-scoped access for authorized locations.
    func restoreLocations() {
        var unavailable = Set<UUID>()
        func resolve(_ list: inout [StoredLocation], startAccess: Bool) {
            for index in list.indices {
                var location = list[index]
                if let data = location.bookmark, let resolution = access.resolve(data) {
                    location.path = resolution.url.standardizedFileURL.path
                    if resolution.isStale { location.bookmark = access.bookmark(for: resolution.url) ?? data }
                    if startAccess { access.startAccessing(resolution.url) }
                }
                if !FileManager.default.fileExists(atPath: location.path) { unavailable.insert(location.id) }
                list[index] = location
            }
        }
        var authorized = state.authorizedLocations
        var favorites = state.favorites
        resolve(&authorized, startAccess: true)
        resolve(&favorites, startAccess: true)
        state.authorizedLocations = authorized
        state.favorites = favorites
        unavailableLocationIDs = unavailable
    }

    // MARK: Appearance

    func applyAppearance() {
        switch preferences.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
