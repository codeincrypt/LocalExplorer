import AppKit
import QuickLook
import SwiftUI
import ExplorerCore

/// Hosts the active view mode plus loading, empty, error and permission states.
struct FileBrowserView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: TabModel
    var focus: FocusState<FocusTarget?>.Binding
    @EnvironmentObject private var services: AppServices
    @State private var showSpinner = false
    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            switch tab.loadState {
            case .failed(let error):
                ErrorStateView(error: error, model: model, tab: tab)
            default:
                content
                    .opacity(tab.loadState == .loading && tab.items.isEmpty ? 0 : 1)
                if tab.loadState == .loading && tab.items.isEmpty && showSpinner {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Loading folder")
                }
                if tab.loadState == .loaded && tab.items.isEmpty {
                    EmptyStateView(tab: tab)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: dropTargeted ? 2 : 0)
                .allowsHitTesting(false)
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.handleDrop(urls, into: tab.currentURL)
        } isTargeted: { dropTargeted = $0 }
        .quickLookPreview($tab.quickLookURL, in: quickLookItems)
        .task(id: tab.loadState) {
            // Only show a spinner for slow folders, to avoid flicker.
            showSpinner = false
            guard tab.loadState == .loading else { return }
            try? await Task.sleep(nanoseconds: 180_000_000)
            if !Task.isCancelled { showSpinner = true }
        }
    }

    private var quickLookItems: [URL] {
        let selected = tab.selectedURLs
        if selected.count > 1 { return selected }
        return tab.quickLookURL.map { [$0] } ?? []
    }

    @ViewBuilder
    private var content: some View {
        switch tab.viewMode {
        case .details:
            DetailsTableView(model: model, tab: tab, focus: focus)
        case .tiles:
            TilesView(model: model, tab: tab, services: services, focus: focus)
        case .compactList:
            CompactListView(model: model, tab: tab, focus: focus)
        case .gallery:
            GalleryView(model: model, tab: tab, services: services, focus: focus)
        }
    }
}

// MARK: - Keyboard

/// File-list keys: Return (rename), Control-Return (context menu), Space (Quick Look),
/// Escape (cancel), arrows (with Shift to extend), ⌘↓ (open), Home/End and
/// type-to-select. Only active while the file list has focus, so text fields and media
/// players keep their own keys.
struct FileListKeyHandling: ViewModifier {
    let model: WindowModel
    let tab: TabModel
    /// `nil` when the view handles arrows natively (the details table).
    let arrangement: ItemArrangement?
    @State private var typeAhead = ""
    @State private var typeAheadDate = Date.distantPast

    func body(content: Content) -> some View {
        content.onKeyPress(phases: [.down, .repeat]) { press in
            handle(press)
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let modifiers = press.modifiers
        let isRepeat = press.phase == .repeat
        switch press.key {
        case .return:
            guard !isRepeat else { return .handled }
            model.perform(modifiers.contains(.control) ? .showContextMenu : .rename)
            return .handled
        case .space:
            guard !isRepeat, modifiers.isEmpty else { return .ignored }
            model.perform(.quickPreview)
            return .handled
        case .escape:
            model.perform(.cancel)
            return .handled
        default:
            break
        }
        if press.key == .downArrow && modifiers.contains(.command) {
            model.openSelection()
            return .handled
        }
        if let arrangement {
            let extend = modifiers.contains(.shift)
            let direction: MoveDirection?
            switch press.key {
            case .upArrow: direction = modifiers.contains(.command) ? nil : .up
            case .downArrow: direction = .down
            case .leftArrow: direction = .left
            case .rightArrow: direction = .right
            case .home: direction = .home
            case .end: direction = .end
            default: direction = nil
            }
            if let direction {
                tab.moveSelection(direction, arrangement: arrangement, extend: extend)
                return .handled
            }
        }
        // Type-to-select: letters jump to the first matching name.
        if modifiers.subtracting(.shift).isEmpty, let typed = press.characters.first, typed.isLetter || typed.isNumber {
            let now = Date()
            typeAhead = now.timeIntervalSince(typeAheadDate) > 1.0 ? String(typed) : typeAhead + String(typed)
            typeAheadDate = now
            if let match = tab.items.first(where: { $0.name.lowercased().hasPrefix(typeAhead.lowercased()) }) {
                tab.selectionModel.click(match.id, order: tab.itemIDs)
            }
            return .handled
        }
        return .ignored
    }
}

extension View {
    func fileListKeys(model: WindowModel, tab: TabModel, arrangement: ItemArrangement?) -> some View {
        modifier(FileListKeyHandling(model: model, tab: tab, arrangement: arrangement))
    }
}

// MARK: - States

struct EmptyStateView: View {
    @ObservedObject var tab: TabModel
    @Environment(\.glass) private var glass

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: tab.searchQuery.isEmpty ? "folder" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(glass.secondaryText)
            Text(tab.searchQuery.isEmpty ? "This folder is empty" : "No items match “\(tab.searchQuery)”")
                .font(.system(size: 14, weight: .medium))
            if !tab.showHidden && tab.allItems.contains(where: \.isHidden) {
                Text("Hidden items are not shown. Press ⇧⌘. to show them.")
                    .font(.system(size: 12))
                    .foregroundStyle(glass.secondaryText)
            }
        }
        .padding()
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

struct ErrorStateView: View {
    let error: DirectoryLoadError
    let model: WindowModel
    @ObservedObject var tab: TabModel
    @Environment(\.glass) private var glass

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(error.isPermission ? Color.orange : glass.secondaryText)
            Text(error.title)
                .font(.system(size: 15, weight: .semibold))
            Text(error.recoverySuggestion)
                .font(.system(size: 12))
                .foregroundStyle(glass.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Text(error.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(glass.secondaryText)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                switch error {
                case .permissionDenied:
                    Button("Grant Access…") {
                        if let url = AppServices.shared.grantAccess(suggesting: tab.currentURL) {
                            if url == tab.currentURL { tab.refresh() } else { tab.navigate(to: url) }
                        }
                    }
                    .buttonStyle(GlassCapsuleButtonStyle(prominent: true))
                    Button("Open Full Disk Access Settings") { AccessManager.openFullDiskAccessSettings() }
                        .buttonStyle(GlassCapsuleButtonStyle())
                case .notFound, .notADirectory:
                    if let parent = tab.parentURL {
                        Button("Go to Enclosing Folder") { tab.navigate(to: parent) }
                            .buttonStyle(GlassCapsuleButtonStyle(prominent: true))
                    }
                default:
                    Button("Go Home") { tab.navigate(to: AppConfiguration.home) }
                        .buttonStyle(GlassCapsuleButtonStyle())
                }
                if tab.history.canGoBack {
                    Button("Back") { tab.goBack() }.buttonStyle(GlassCapsuleButtonStyle())
                }
                Button("Try Again") { tab.refresh() }.buttonStyle(GlassCapsuleButtonStyle())
            }
        }
        .padding(24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("errorState")
    }

    private var symbol: String {
        switch error {
        case .permissionDenied: return "lock.fill"
        case .notFound: return "questionmark.folder"
        case .volumeUnavailable: return "externaldrive.badge.exclamationmark"
        default: return "exclamationmark.triangle"
        }
    }
}

extension DirectoryLoadError {
    var isPermission: Bool {
        if case .permissionDenied = self { return true }
        return false
    }
}
