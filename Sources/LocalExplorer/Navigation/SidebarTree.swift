import SwiftUI
import ExplorerCore

/// Expansion state and lazily loaded subfolders for the sidebar's folder tree.
/// Listing runs off the main actor; a folder is only enumerated once it is expanded.
@MainActor
final class SidebarTree: ObservableObject {
    struct Folder: Identifiable, Equatable {
        var id: String { url.path }
        let name: String
        let url: URL
    }

    private static let defaultsKey = "SidebarExpandedFolders"

    /// Keys are `"<section>|<path>"` so the same folder can be open in one section
    /// (e.g. Favorites) and closed in another (Locations).
    @Published private(set) var expanded: Set<String>
    /// Subfolders by directory path. Absent means not loaded yet.
    @Published private(set) var children: [String: [Folder]] = [:]

    private let fileSystem: FileSystemProviding
    private var inFlight: Set<String> = []
    private var showHidden = false

    init(fileSystem: FileSystemProviding = LocalFileSystem()) {
        self.fileSystem = fileSystem
        expanded = Set(UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    static func key(section: String, url: URL) -> String { "\(section)|\(url.path)" }

    func isExpanded(section: String, url: URL) -> Bool {
        expanded.contains(Self.key(section: section, url: url))
    }

    /// Whether the row should offer a disclosure arrow. Unknown (not yet listed) counts
    /// as expandable; a folder found to have no subfolders does not.
    func canExpand(_ url: URL) -> Bool {
        children[url.path].map { !$0.isEmpty } ?? true
    }

    func toggle(section: String, url: URL) {
        let key = Self.key(section: section, url: url)
        if expanded.remove(key) == nil {
            expanded.insert(key)
            load(url, force: true)
        }
        persist()
    }

    /// Lists `url`'s subfolders unless they are already cached (or `force`d).
    func load(_ url: URL, force: Bool = false) {
        let path = url.path
        guard !inFlight.contains(path), force || children[path] == nil else { return }
        inFlight.insert(path)
        let fileSystem = fileSystem
        let showHidden = showHidden
        Task.detached(priority: .userInitiated) { [weak self] in
            let folders = Self.subfolders(of: url, using: fileSystem, showHidden: showHidden)
            await MainActor.run {
                guard let self else { return }
                self.inFlight.remove(path)
                if self.children[path] != folders { self.children[path] = folders }
            }
        }
    }

    /// Makes sure every expanded folder has its subfolders loaded (e.g. after launch).
    func loadExpanded() {
        for key in expanded {
            guard let separator = key.firstIndex(of: "|") else { continue }
            load(URL(fileURLWithPath: String(key[key.index(after: separator)...])))
        }
    }

    /// Hidden folders appear only when the file list shows them too.
    func setShowHidden(_ value: Bool) {
        guard value != showHidden else { return }
        showHidden = value
        for path in children.keys { load(URL(fileURLWithPath: path), force: true) }
    }

    /// Expands the chain from the closest root above `target` down to its parent, so the
    /// current folder is visible in the tree. Only the deepest root is used, so
    /// `~/Documents/Notes` opens under Documents rather than also under Home. A target that
    /// is itself a root is already visible as a top-level row, so nothing is expanded.
    func reveal(_ target: URL, roots: [(section: String, url: URL)]) {
        let target = target.standardizedFileURL
        if roots.contains(where: { $0.url.standardizedFileURL == target }) { return }
        let candidates = roots.filter { PathBreadcrumbs.isDescendant(target, of: $0.url) }
        guard let best = candidates.max(by: { $0.url.pathComponents.count < $1.url.pathComponents.count }) else { return }
        var changed = false
        var ancestor = best.url.standardizedFileURL
        for component in target.pathComponents.dropFirst(ancestor.pathComponents.count) {
            if expanded.insert(Self.key(section: best.section, url: ancestor)).inserted { changed = true }
            load(ancestor)
            ancestor.appendPathComponent(component)
        }
        if changed { persist() }
    }

    /// Re-lists a folder whose contents changed (new/renamed/deleted subfolder).
    func refresh(_ url: URL) {
        if children[url.path] != nil { load(url, force: true) }
    }

    private func persist() {
        UserDefaults.standard.set(expanded.sorted(), forKey: Self.defaultsKey)
    }

    nonisolated private static func subfolders(of url: URL, using fileSystem: FileSystemProviding, showHidden: Bool) -> [Folder] {
        guard let items = try? fileSystem.contents(of: url) else { return [] }
        return items
            .filter { $0.isNavigableDirectory && (showHidden || !$0.isHidden) }
            .sorted { FileSorter.compareNames($0.name, $1.name) == .orderedAscending }
            .map { Folder(name: $0.name, url: $0.url) }
    }
}
