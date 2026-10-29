import AppKit
import SwiftUI
import ExplorerCore

/// One browsing tab: location, history, listing, filter, sort, view mode and selection.
/// Enumeration runs off the main actor; results are applied only if the tab is still
/// showing the folder that was requested.
@MainActor
final class TabModel: ObservableObject, Identifiable {
    enum LoadState: Equatable {
        case idle, loading, loaded
        case failed(DirectoryLoadError)
    }

    let id = UUID()
    @Published private(set) var history: NavigationHistory
    @Published private(set) var allItems: [FileItem] = []
    @Published private(set) var items: [FileItem] = []
    @Published private(set) var loadState: LoadState = .idle
    @Published var selectionModel = SelectionModel()
    @Published var sort: FileSortDescriptor { didSet { if sort != oldValue { applyFilterAndSort() } } }
    @Published var viewMode: ViewMode
    @Published var showHidden: Bool { didSet { if showHidden != oldValue { applyFilterAndSort() } } }
    @Published var searchQuery = "" { didSet { if searchQuery != oldValue { applyFilterAndSort() } } }
    @Published private(set) var isFolderWritable = true
    @Published private(set) var availableCapacity: Int64?
    /// Drives the system Quick Look panel (Space).
    @Published var quickLookURL: URL?

    private let fileSystem: FileSystemProviding
    private var watcher: DirectoryWatcher?
    private var loadTask: Task<Void, Never>?
    /// Called after a successful navigation (not on refresh), e.g. to record recents.
    var onVisit: ((URL) -> Void)?
    /// Hidden-file visibility for a folder; consulted whenever the tab enters one.
    var showsHiddenFiles: ((URL) -> Bool)?

    init(url: URL, preferences: AppPreferences, fileSystem: FileSystemProviding) {
        self.history = NavigationHistory(start: url)
        self.sort = preferences.sort
        self.viewMode = preferences.defaultViewMode
        self.showHidden = preferences.showHiddenFiles
        self.fileSystem = fileSystem
    }

    // MARK: Derived state

    var currentURL: URL { history.current }

    /// True while showing the "This Mac" start page instead of a folder.
    var isThisMac: Bool { ThisMac.isThisMac(currentURL) }

    var title: String {
        if isThisMac { return ThisMac.title }
        return currentURL.path == "/" ? "Computer" : FileManager.default.displayName(atPath: currentURL.path)
    }

    var itemIDs: [String] { items.map(\.id) }

    var selection: Set<String> {
        get { selectionModel.selected }
        set { selectionModel.replace(with: newValue, order: itemIDs) }
    }

    var selectedItems: [FileItem] {
        let selected = selectionModel.selected
        return items.filter { selected.contains($0.id) }
    }

    var selectedURLs: [URL] { selectedItems.map(\.url) }

    /// The item the keyboard cursor is on, or the single selected item.
    var focusedItem: FileItem? {
        if let cursor = selectionModel.cursor, let item = items.first(where: { $0.id == cursor }), selection.contains(cursor) {
            return item
        }
        return selectedItems.first
    }

    /// The enclosing folder; the top of the filesystem leads up to the "This Mac" page.
    var parentURL: URL? {
        if isThisMac { return nil }
        if currentURL.path == "/" { return ThisMac.url }
        return currentURL.deletingLastPathComponent().standardizedFileURL
    }

    var selectedBytes: Int64? {
        let sizes = selectedItems.compactMap(\.size)
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }

    var isLoaded: Bool { loadState == .loaded }

    // MARK: Navigation

    func start() {
        if loadState == .idle { load(visit: true) }
    }

    func navigate(to url: URL, selecting: URL? = nil) {
        let target = url.standardizedFileURL
        guard target != currentURL || loadState != .loaded else {
            if let selecting { select(urls: [selecting]) }
            return
        }
        history.visit(target)
        searchQuery = ""
        load(visit: true, selecting: selecting.map { [$0] })
    }

    func goBack() {
        let leaving = currentURL
        guard history.goBack() != nil else { return }
        searchQuery = ""
        // Returning to a parent selects the folder we came from, like Finder.
        load(visit: true, selecting: PathBreadcrumbs.isDescendant(leaving, of: currentURL) ? [childOnPath(to: leaving)] : nil)
    }

    func goForward() {
        guard history.goForward() != nil else { return }
        searchQuery = ""
        load(visit: true)
    }

    func goUp() {
        guard let parent = parentURL else { return }
        navigate(to: parent, selecting: currentURL)
    }

    func refresh() {
        load(visit: false, preserveSelection: true)
    }

    /// Re-reads the folder after an operation, selecting the given items if present.
    func refresh(selecting urls: [URL]) {
        load(visit: false, preserveSelection: urls.isEmpty, selecting: urls.isEmpty ? nil : urls)
    }

    private func childOnPath(to descendant: URL) -> URL {
        let depth = currentURL.pathComponents.count
        let components = descendant.pathComponents.prefix(depth + 1)
        return URL(fileURLWithPath: NSString.path(withComponents: Array(components)))
    }

    // MARK: Loading

    private func load(visit: Bool, preserveSelection: Bool = false, selecting: [URL]? = nil) {
        loadTask?.cancel()
        let url = currentURL
        if visit, let showsHiddenFiles { showHidden = showsHiddenFiles(url) }
        if isThisMac {
            // Nothing to enumerate: the page builds itself from the standard folders and
            // mounted volumes.
            allItems = []
            items = []
            watcher = nil
            selectionModel.clear()
            isFolderWritable = false
            availableCapacity = nil
            loadState = .loaded
            if visit { onVisit?(url) }
            return
        }
        let previous = selectionModel
        if !preserveSelection {
            selectionModel.clear()
            if visit {
                allItems = []
                items = []
                watcher = nil
            }
        }
        if !isLoaded || visit { loadState = .loading }

        let fileSystem = self.fileSystem
        loadTask = Task { [weak self] in
            let result: Result<[FileItem], DirectoryLoadError> = await Task.detached(priority: .userInitiated) {
                do {
                    return .success(try fileSystem.contents(of: url))
                } catch let error as DirectoryLoadError {
                    return .failure(error)
                } catch {
                    return .failure(.classify(error, path: url.path))
                }
            }.value
            guard let self, !Task.isCancelled, url == self.currentURL else { return }
            switch result {
            case .success(let list):
                self.allItems = list
                self.loadState = .loaded
                self.applyFilterAndSort()
                if let selecting {
                    self.select(urls: selecting)
                } else if preserveSelection {
                    self.selectionModel = previous
                    self.selectionModel.reconcile(with: self.itemIDs)
                }
                self.updateFolderFacts()
                if self.watcher == nil || visit {
                    self.watcher = DirectoryWatcher(url: url) { [weak self] in self?.refresh() }
                }
                if visit { self.onVisit?(url) }
            case .failure(let error):
                self.allItems = []
                self.items = []
                self.watcher = nil
                self.loadState = .failed(error)
            }
        }
    }

    private func applyFilterAndSort() {
        let filtered = FileFilter(showHidden: showHidden, query: searchQuery).apply(to: allItems)
        items = FileSorter.sorted(filtered, by: sort)
        selectionModel.reconcile(with: itemIDs)
    }

    private func updateFolderFacts() {
        let url = currentURL
        isFolderWritable = FileManager.default.isWritableFile(atPath: url.path)
        Task { [weak self] in
            let capacity = await Task.detached(priority: .utility) {
                FileSystemFacts.availableCapacity(at: url)
            }.value
            guard let self, self.currentURL == url else { return }
            self.availableCapacity = capacity
        }
    }

    // MARK: Selection helpers

    func select(urls: [URL]) {
        let ids = Set(urls.map { $0.standardizedFileURL.path }).intersection(itemIDs)
        guard !ids.isEmpty else { return }
        selectionModel = SelectionModel(selected: ids, anchor: itemIDs.first { ids.contains($0) }, cursor: itemIDs.last { ids.contains($0) })
    }

    func click(_ item: FileItem, modifiers: NSEvent.ModifierFlags) {
        var m: SelectionModifiers = []
        if modifiers.contains(.command) { m.insert(.toggle) }
        if modifiers.contains(.shift) { m.insert(.extend) }
        selectionModel.click(item.id, order: itemIDs, modifiers: m)
    }

    func moveSelection(_ direction: MoveDirection, arrangement: ItemArrangement, extend: Bool) {
        selectionModel.move(direction, order: itemIDs, arrangement: arrangement, extend: extend)
    }

    func selectAll() { selectionModel.selectAll(order: itemIDs) }
}
