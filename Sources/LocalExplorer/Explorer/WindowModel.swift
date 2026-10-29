import AppKit
import SwiftUI
import ExplorerCore

/// Prompts shown as sheets/alerts. Each conflict prompt resumes its operation exactly
/// once, whichever way the sheet is dismissed.
struct ConflictPrompt: Identifiable {
    let id: UUID
    let conflict: FileConflict
    let respond: (ConflictResolution) -> Void
}

struct DeleteConfirmation: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct BatchRenameRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct ErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct OperationStatus: Equatable {
    let kind: FileOperationKind
    var progress: OperationProgress?
}

enum FocusTarget: Hashable {
    case fileList, path, search
}

struct FocusRequest: Equatable {
    let target: FocusTarget
    let token: Int
}

/// Resumes a continuation at most once.
private final class ResumeOnce<T>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Never>?
    private let lock = NSLock()
    init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }
    func resume(_ value: T) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}

/// State and actions for one window: its tabs, panes, prompts and running operation.
/// All commands are executed here through `perform(_:)`.
@MainActor
final class WindowModel: ObservableObject {
    let services: AppServices
    @Published private(set) var tabs: [TabModel] = []
    @Published var activeTabID: UUID
    @Published var showSidebar: Bool { didSet { services.preferences.showSidebar = showSidebar } }
    @Published var showPreviewPane: Bool { didSet { services.preferences.showPreviewPane = showPreviewPane } }

    @Published var renameTarget: FileItem?
    @Published var conflictPrompt: ConflictPrompt?
    @Published var deleteConfirmation: DeleteConfirmation?
    @Published var batchRename: BatchRenameRequest?
    @Published var errorAlert: ErrorAlert?
    @Published private(set) var operation: OperationStatus?
    /// Incremented focus requests; views observe and move focus.
    @Published var focusRequest = FocusRequest(target: .fileList, token: 0)
    @Published var isEditingPath = false
    /// The in-window photo viewer covers the window while true.
    @Published private(set) var isShowingPhotoViewer = false

    weak var window: NSWindow?
    var undoManager: UndoManager?
    private var operationTask: Task<Void, Never>?

    init(services: AppServices = .shared, initialURLs: [URL]? = nil) {
        self.services = services
        self.showSidebar = services.preferences.showSidebar
        self.showPreviewPane = services.preferences.showPreviewPane
        let urls = (initialURLs?.isEmpty == false ? initialURLs! : [services.startURL])
        let first = TabModel(url: urls[0], preferences: services.preferences, fileSystem: services.fileSystem)
        self.activeTabID = first.id
        add(first)
        for url in urls.dropFirst() {
            add(TabModel(url: url, preferences: services.preferences, fileSystem: services.fileSystem))
        }
        first.start()
    }

    var activeTab: TabModel {
        tabs.first { $0.id == activeTabID } ?? tabs[0]
    }

    // MARK: Tabs

    private func add(_ tab: TabModel, after index: Int? = nil) {
        // Views observe the active tab directly; the window only republishes which tab
        // is active, so a selection change does not re-render the whole window.
        tab.showsHiddenFiles = { [weak self] url in
            self?.services.preferences.showsHiddenFiles(in: url) ?? false
        }
        tab.onVisit = { [weak self] url in
            if !ThisMac.isThisMac(url) { self?.services.recordVisit(url) }
            self?.persistTabs()
        }
        if let index { tabs.insert(tab, at: min(index + 1, tabs.count)) } else { tabs.append(tab) }
    }

    func newTab(at url: URL? = nil) {
        let tab = TabModel(url: url ?? activeTab.currentURL, preferences: services.preferences, fileSystem: services.fileSystem)
        add(tab, after: tabs.firstIndex { $0.id == activeTabID })
        activeTabID = tab.id
        tab.start()
        persistTabs()
    }

    func selectTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        activeTabID = id
        tab.start()
        requestFocus(.fileList)
    }

    /// Closes the active tab; closing the last tab closes the window.
    func closeTab(_ id: UUID? = nil) {
        let target = id ?? activeTabID
        guard tabs.count > 1 else {
            window?.performClose(nil)
            return
        }
        guard let index = tabs.firstIndex(where: { $0.id == target }) else { return }
        tabs.remove(at: index)
        if activeTabID == target {
            activeTabID = tabs[min(index, tabs.count - 1)].id
            activeTab.start()
        }
        persistTabs()
    }

    func selectAdjacentTab(offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }), !tabs.isEmpty else { return }
        selectTab(tabs[(index + offset + tabs.count) % tabs.count].id)
    }

    func persistTabs() {
        services.state.openTabs = tabs.map { $0.currentURL.path }
    }

    // MARK: Focus

    func requestFocus(_ target: FocusTarget) {
        focusRequest = FocusRequest(target: target, token: focusRequest.token + 1)
    }

    var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if let textView = responder as? NSTextView { return textView.isEditable || textView.isFieldEditor }
        return responder is NSTextField
    }

    // MARK: Commands

    var commandContext: CommandContext {
        let tab = activeTab
        return CommandContext(
            selectionCount: tab.selection.count,
            canPaste: services.clipboard.hasFiles,
            canGoBack: tab.history.canGoBack,
            canGoForward: tab.history.canGoForward,
            canGoUp: tab.parentURL != nil,
            isFolderLoaded: tab.isLoaded,
            isFolderWritable: tab.isFolderWritable,
            isEditingText: isEditingText,
            tabCount: tabs.count
        )
    }

    func isEnabled(_ command: ExplorerCommand) -> Bool {
        if CommandRouting.alwaysEnabledInMenu.contains(command) { return true }
        var context = commandContext
        context.isEditingText = false
        return CommandRouting.isEnabled(command, in: context)
    }

    /// The single entry point for menu items, toolbar buttons, context menus and key
    /// presses.
    func perform(_ command: ExplorerCommand) {
        switch CommandRouting.decide(command, in: commandContext) {
        case .forwardToTextEditor(let action):
            NSApp.sendAction(Selector(action), to: nil, from: nil)
            return
        case .unavailable:
            NSSound.beep()
            return
        case .perform:
            break
        }
        let tab = activeTab
        switch command {
        case .newTab: newTab()
        case .closeTab: closeTab()
        case .newFolder: createFolder()
        case .open: openSelection()
        case .getInfo:
            showPreviewPane = true
        case .rename:
            if let item = tab.focusedItem { renameTarget = item }
        case .duplicate: duplicateSelection()
        case .batchRename: batchRename = BatchRenameRequest(urls: tab.selectedURLs)
        case .moveToTrash: trashSelection()
        case .deletePermanently: deleteConfirmation = DeleteConfirmation(urls: tab.selectedURLs)
        case .addToFavorites:
            let targets = tab.selectedItems.filter(\.isNavigableDirectory).map(\.url)
            for url in targets.isEmpty && !tab.isThisMac ? [tab.currentURL] : targets { services.addFavorite(url) }
        case .grantAccess:
            if let url = services.grantAccess(suggesting: tab.isThisMac ? nil : tab.currentURL) { tab.navigate(to: url) }
        case .copy: services.clipboard.write(tab.selectedURLs, cut: false)
        case .cut: services.clipboard.write(tab.selectedURLs, cut: true)
        case .paste: paste()
        case .selectAll: tab.selectAll()
        case .copyPath:
            services.clipboard.copyText(tab.selectedURLs.map(\.path).joined(separator: "\n"))
        case .search: requestFocus(.search)
        case .cancel: cancelInteraction()
        case .viewTiles, .viewCompactList, .viewGallery, .viewDetails:
            setViewMode(Self.mode(for: command))
        case .toggleHiddenFiles: toggleHiddenFiles()
        case .togglePreviewPane: showPreviewPane.toggle()
        case .toggleSidebar: showSidebar.toggle()
        case .quickPreview: toggleQuickLook()
        case .refresh:
            if tab.isThisMac { services.volumes.reload() } else { tab.refresh() }
        case .goBack: tab.goBack()
        case .goForward: tab.goForward()
        case .goToParent: tab.goUp()
        case .focusPath:
            isEditingPath = true
            requestFocus(.path)
        case .goThisMac: tab.navigate(to: ThisMac.url)
        case .goHome: tab.navigate(to: AppConfiguration.home)
        case .goDesktop: go(.desktopDirectory)
        case .goDocuments: go(.documentDirectory)
        case .goDownloads: go(.downloadsDirectory)
        case .goApplications: go(.applicationDirectory, domain: .localDomainMask)
        case .showContextMenu: showContextMenuForSelection()
        }
    }

    static func mode(for command: ExplorerCommand) -> ViewMode {
        switch command {
        case .viewTiles: return .tiles
        case .viewCompactList: return .compactList
        case .viewGallery: return .gallery
        default: return .details
        }
    }

    private func go(_ directory: FileManager.SearchPathDirectory, domain: FileManager.SearchPathDomainMask = .userDomainMask) {
        if let url = FileManager.default.urls(for: directory, in: domain).first {
            activeTab.navigate(to: url)
        }
    }

    func setViewMode(_ mode: ViewMode) {
        activeTab.viewMode = mode
        services.preferences.defaultViewMode = mode
        requestFocus(.fileList)
    }

    func setSort(_ sort: FileSortDescriptor) {
        activeTab.sort = sort
        services.preferences.sort = sort
    }

    func toggleHiddenFiles() {
        // The choice belongs to the folder being viewed; other folders keep their own.
        let tab = activeTab
        guard !tab.isThisMac else { return }
        tab.showHidden.toggle()
        services.preferences.setShowsHiddenFiles(tab.showHidden, in: tab.currentURL)
    }

    func toggleQuickLook() {
        let tab = activeTab
        if tab.quickLookURL != nil {
            tab.quickLookURL = nil
        } else {
            tab.quickLookURL = tab.focusedItem?.url
        }
    }

    private func cancelInteraction() {
        if isShowingPhotoViewer { closePhotoViewer(); return }
        let tab = activeTab
        if tab.quickLookURL != nil { tab.quickLookURL = nil; return }
        if isEditingPath { isEditingPath = false; requestFocus(.fileList); return }
        if !tab.searchQuery.isEmpty { tab.searchQuery = ""; requestFocus(.fileList); return }
        if operation != nil { cancelOperation(); return }
        tab.selectionModel.clear()
    }

    // MARK: Opening

    /// Photos open in the built-in viewer; everything else opens as `openExternally`.
    func open(_ item: FileItem) {
        if item.category == .image, !item.isDirectory, !item.isBrokenSymbolicLink, item.isReadable {
            openPhotoViewer(item)
        } else {
            openExternally(item)
        }
    }

    func openPhotoViewer(_ item: FileItem) {
        let tab = activeTab
        tab.selectionModel.click(item.id, order: tab.itemIDs)
        isShowingPhotoViewer = true
    }

    func closePhotoViewer() {
        guard isShowingPhotoViewer else { return }
        isShowingPhotoViewer = false
        requestFocus(.fileList)
    }

    func openExternally(_ item: FileItem) {
        if item.isNavigableDirectory {
            activeTab.navigate(to: item.url)
        } else if item.isBrokenSymbolicLink {
            errorAlert = ErrorAlert(title: "The alias “\(item.name)” can’t be opened", message: "The original item can’t be found.")
        } else if !NSWorkspace.shared.open(item.url) {
            errorAlert = ErrorAlert(title: "“\(item.name)” couldn’t be opened", message: "No application is available to open this item.")
        }
    }

    func openSelection() {
        let items = activeTab.selectedItems
        if items.count == 1 { open(items[0]); return }
        // Several folders open in new tabs; files open with their default apps.
        for item in items {
            if item.isNavigableDirectory { newTab(at: item.url) } else { openExternally(item) }
        }
    }

    func showPackageContents(_ item: FileItem) {
        activeTab.navigate(to: item.url)
    }

    func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func navigate(to url: URL) {
        activeTab.navigate(to: url)
        requestFocus(.fileList)
    }

    // MARK: File operations

    private func createFolder() {
        let tab = activeTab
        do {
            let url = try services.engine.createFolder(in: tab.currentURL)
            registerUndo(.created([url]))
            tab.refresh(selecting: [url])
            // Offer an immediate rename, as Finder does.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard let self else { return }
                if let item = tab.items.first(where: { $0.url == url }) { self.renameTarget = item }
            }
        } catch {
            show(error, title: "The folder couldn’t be created")
        }
    }

    func rename(_ item: FileItem, to newName: String) {
        guard newName != item.name else { return }
        do {
            let url = try services.engine.rename(item.url, to: newName)
            registerUndo(.renamed([Transfer(source: item.url, destination: url)]))
            activeTab.refresh(selecting: [url])
        } catch {
            show(error, title: "“\(item.name)” couldn’t be renamed")
        }
    }

    func applyBatchRename(_ plan: [BatchRenameEntry]) {
        let report = services.engine.applyBatchRename(plan)
        finish(report)
    }

    private func duplicateSelection() {
        let urls = activeTab.selectedURLs
        run(.duplicate) { engine, progress in await engine.duplicate(urls, progress: progress) }
    }

    private func trashSelection() {
        let urls = activeTab.selectedURLs
        run(.trash) { engine, _ in await engine.moveToTrash(urls) }
    }

    func confirmDeletePermanently(_ urls: [URL]) {
        run(.delete) { engine, _ in await engine.deletePermanently(urls) }
    }

    private func paste() {
        let urls = services.clipboard.fileURLs()
        guard !urls.isEmpty else { NSSound.beep(); return }
        let destination = activeTab.currentURL
        if services.clipboard.isCut {
            services.clipboard.finishCut()
            transfer(urls, into: destination, move: true)
        } else {
            transfer(urls, into: destination, move: false)
        }
    }

    /// Copies or moves `urls` into `destination` (paste and drag-and-drop).
    func transfer(_ urls: [URL], into destination: URL, move: Bool) {
        let conflicts = makeConflictHandler()
        run(move ? .move : .copy) { engine, progress in
            move
                ? await engine.move(urls, into: destination, conflicts: conflicts, progress: progress)
                : await engine.copy(urls, into: destination, conflicts: conflicts, progress: progress)
        }
    }

    /// Finder semantics for drops: move within a volume, copy across volumes, and
    /// Option forces a copy.
    func handleDrop(_ urls: [URL], into destination: URL) -> Bool {
        guard !ThisMac.isThisMac(destination) else { return false }
        let sources = urls.filter { $0.standardizedFileURL != destination.standardizedFileURL }
        guard !sources.isEmpty else { return false }
        let optionDown = NSEvent.modifierFlags.contains(.option)
        let sameVolume = sources.allSatisfy { FileSystemFacts.isSameVolume($0, destination) }
        transfer(sources, into: destination, move: !optionDown && sameVolume)
        return true
    }

    private func run(_ kind: FileOperationKind, _ body: @escaping (FileOperationEngine, @escaping ProgressHandler) async -> FileOperationReport) {
        guard operation == nil else {
            errorAlert = ErrorAlert(title: "Another operation is in progress", message: "Wait for it to finish or cancel it, then try again.")
            return
        }
        operation = OperationStatus(kind: kind, progress: nil)
        let engine = services.engine
        let progress: ProgressHandler = { [weak self] value in
            Task { @MainActor in
                guard let self, self.operation != nil else { return }
                self.operation?.progress = value
            }
        }
        operationTask = Task { [weak self] in
            let report = await body(engine, progress)
            guard let self else { return }
            self.operation = nil
            self.operationTask = nil
            self.finish(report)
        }
    }

    func cancelOperation() {
        operationTask?.cancel()
        conflictPrompt?.respond(ConflictResolution(.cancel))
    }

    private func finish(_ report: FileOperationReport) {
        if let record = report.record { registerUndo(record) }
        if let summary = report.failureSummary {
            errorAlert = ErrorAlert(title: "\(report.kind.progressTitle) didn’t fully complete", message: summary)
        }
        let destinations = report.destinations
        let tab = activeTab
        let selectable = destinations.filter { $0.deletingLastPathComponent().standardizedFileURL == tab.currentURL }
        tab.refresh(selecting: report.kind == .trash || report.kind == .delete ? [] : selectable)
        for other in tabs where other.id != tab.id { other.refresh() }
    }

    private func makeConflictHandler() -> ConflictHandler {
        { [weak self] conflict in
            await withCheckedContinuation { continuation in
                let once = ResumeOnce(continuation)
                Task { @MainActor in
                    guard let self else { once.resume(ConflictResolution(.cancel)); return }
                    let promptID = UUID()
                    self.conflictPrompt = ConflictPrompt(id: promptID, conflict: conflict) { [weak self] resolution in
                        // Only clear our own prompt; a late dismissal must not close the next one.
                        if self?.conflictPrompt?.id == promptID { self?.conflictPrompt = nil }
                        once.resume(resolution)
                    }
                }
            }
        }
    }

    // MARK: Undo

    private func registerUndo(_ record: FileOperationRecord) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.performUndo(record) }
        }
        undoManager.setActionName(record.undoTitle)
    }

    private func performUndo(_ record: FileOperationRecord) {
        run(.undo) { engine, _ in await engine.undo(record) }
    }

    // MARK: Errors

    func show(_ error: Error, title: String) {
        let message = (error as? FileOperationError)?.message ?? (error as NSError).localizedDescription
        errorAlert = ErrorAlert(title: title, message: message)
    }

    // MARK: Context menu from the keyboard (Control-Return)

    private func showContextMenuForSelection() {
        guard let window, let contentView = window.contentView else { return }
        let menu = FileContextMenuBuilder.nsMenu(for: activeTab.selectedItems, model: self)
        let location = window.mouseLocationOutsideOfEventStream
        let point = contentView.bounds.contains(location)
            ? location
            : NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        menu.popUp(positioning: nil, at: point, in: contentView)
    }
}
