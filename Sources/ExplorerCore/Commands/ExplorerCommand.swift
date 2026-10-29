import Foundation

/// Platform-neutral key description. The app maps it to SwiftUI `KeyEquivalent`.
public enum ShortcutKey: Hashable, Sendable {
    case character(Character)
    case returnKey, delete, escape, space, upArrow, downArrow, leftArrow, rightArrow

    public var symbol: String {
        switch self {
        case .character(let c): return String(c).uppercased()
        case .returnKey: return "↩"
        case .delete: return "⌫"
        case .escape: return "⎋"
        case .space: return "Space"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        }
    }
}

public struct ShortcutModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let shift = ShortcutModifiers(rawValue: 1 << 1)
    public static let option = ShortcutModifiers(rawValue: 1 << 2)
    public static let control = ShortcutModifiers(rawValue: 1 << 3)

    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

public struct Shortcut: Hashable, Sendable {
    public let key: ShortcutKey
    public let modifiers: ShortcutModifiers
    public init(_ key: ShortcutKey, _ modifiers: ShortcutModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
    public var displayString: String { modifiers.symbols + key.symbol }
}

/// Where a shortcut is handled.
public enum ShortcutScope: Sendable, Equatable {
    /// Bound as a menu key equivalent (shown in the menu bar).
    case menu
    /// Handled by the focused file list only, so it never steals keys from text fields
    /// or media players (Return, Space, Escape, Control-Return).
    case fileList
}

public enum CommandCategory: String, Sendable, CaseIterable {
    case file, edit, view, go, window
}

/// Every user-invocable command. Menus, context menus, toolbar buttons and key presses
/// all route through this table so shortcuts are defined in exactly one place.
public enum ExplorerCommand: String, CaseIterable, Sendable {
    // File
    case newTab, newFolder, open, closeTab, getInfo, rename, duplicate, batchRename
    case moveToTrash, deletePermanently, addToFavorites, grantAccess
    // Edit
    case copy, cut, paste, selectAll, copyPath, search, cancel
    // View
    case viewTiles, viewCompactList, viewGallery, viewDetails
    case toggleHiddenFiles, togglePreviewPane, toggleSidebar, quickPreview, refresh
    // Go
    case goBack, goForward, goToParent, focusPath
    case goThisMac, goHome, goDesktop, goDocuments, goDownloads, goApplications
    // Context
    case showContextMenu

    public var title: String {
        switch self {
        case .newTab: return "New Tab"
        case .newFolder: return "New Folder"
        case .open: return "Open"
        case .closeTab: return "Close Tab"
        case .getInfo: return "Get Info"
        case .rename: return "Rename"
        case .duplicate: return "Duplicate"
        case .batchRename: return "Rename Items…"
        case .moveToTrash: return "Move to Trash"
        case .deletePermanently: return "Delete Immediately…"
        case .addToFavorites: return "Add to Favorites"
        case .grantAccess: return "Grant Access to Folder…"
        case .copy: return "Copy"
        case .cut: return "Cut"
        case .paste: return "Paste"
        case .selectAll: return "Select All"
        case .copyPath: return "Copy Path"
        case .search: return "Find…"
        case .cancel: return "Cancel"
        case .viewTiles: return "as Tiles"
        case .viewCompactList: return "as Compact List"
        case .viewGallery: return "as Gallery"
        case .viewDetails: return "as Details"
        case .toggleHiddenFiles: return "Show Hidden Files"
        case .togglePreviewPane: return "Show Preview Pane"
        case .toggleSidebar: return "Show Sidebar"
        case .quickPreview: return "Quick Look"
        case .refresh: return "Refresh"
        case .goBack: return "Back"
        case .goForward: return "Forward"
        case .goToParent: return "Enclosing Folder"
        case .focusPath: return "Go to Path…"
        case .goThisMac: return ThisMac.title
        case .goHome: return "Home"
        case .goDesktop: return "Desktop"
        case .goDocuments: return "Documents"
        case .goDownloads: return "Downloads"
        case .goApplications: return "Applications"
        case .showContextMenu: return "Show Context Menu"
        }
    }

    public var symbolName: String {
        switch self {
        case .newTab: return "plus.square.on.square"
        case .newFolder: return "folder.badge.plus"
        case .open: return "arrow.up.forward.app"
        case .closeTab: return "xmark.square"
        case .getInfo: return "info.circle"
        case .rename: return "pencil"
        case .duplicate: return "plus.square.on.square"
        case .batchRename: return "character.cursor.ibeam"
        case .moveToTrash: return "trash"
        case .deletePermanently: return "trash.slash"
        case .addToFavorites: return "star"
        case .grantAccess: return "lock.open"
        case .copy: return "doc.on.doc"
        case .cut: return "scissors"
        case .paste: return "doc.on.clipboard"
        case .selectAll: return "checklist"
        case .copyPath: return "link"
        case .search: return "magnifyingglass"
        case .cancel: return "xmark"
        case .viewTiles: return "square.grid.2x2"
        case .viewCompactList: return "list.bullet"
        case .viewGallery: return "rectangle.bottomthird.inset.filled"
        case .viewDetails: return "tablecells"
        case .toggleHiddenFiles: return "eye.slash"
        case .togglePreviewPane: return "sidebar.right"
        case .toggleSidebar: return "sidebar.left"
        case .quickPreview: return "eye"
        case .refresh: return "arrow.clockwise"
        case .goBack: return "chevron.left"
        case .goForward: return "chevron.right"
        case .goToParent: return "arrow.turn.left.up"
        case .focusPath: return "character.cursor.ibeam"
        case .goThisMac: return "desktopcomputer"
        case .goHome: return "house"
        case .goDesktop: return "menubar.dock.rectangle"
        case .goDocuments: return "doc"
        case .goDownloads: return "arrow.down.circle"
        case .goApplications: return "square.grid.3x3"
        case .showContextMenu: return "contextualmenu.and.cursorarrow"
        }
    }

    public var category: CommandCategory {
        switch self {
        case .newTab, .newFolder, .open, .closeTab, .getInfo, .rename, .duplicate, .batchRename,
             .moveToTrash, .deletePermanently, .addToFavorites, .grantAccess:
            return .file
        case .copy, .cut, .paste, .selectAll, .copyPath, .search, .cancel:
            return .edit
        case .viewTiles, .viewCompactList, .viewGallery, .viewDetails, .toggleHiddenFiles,
             .togglePreviewPane, .toggleSidebar, .quickPreview, .refresh:
            return .view
        case .goBack, .goForward, .goToParent, .focusPath, .goThisMac, .goHome, .goDesktop, .goDocuments,
             .goDownloads, .goApplications:
            return .go
        case .showContextMenu:
            return .window
        }
    }

    /// The single source of truth for keyboard shortcuts.
    public var shortcut: Shortcut? {
        switch self {
        case .copy: return Shortcut(.character("c"), .command)
        case .cut: return Shortcut(.character("x"), .command)
        case .paste: return Shortcut(.character("v"), .command)
        case .rename: return Shortcut(.returnKey)
        case .open: return Shortcut(.character("o"), .command)
        case .moveToTrash: return Shortcut(.delete, .command)
        case .getInfo: return Shortcut(.character("i"), .command)
        case .selectAll: return Shortcut(.character("a"), .command)
        case .newFolder: return Shortcut(.character("n"), [.command, .shift])
        case .toggleHiddenFiles: return Shortcut(.character("."), [.command, .shift])
        case .viewTiles: return Shortcut(.character("1"), .command)
        case .viewCompactList: return Shortcut(.character("2"), .command)
        case .viewGallery: return Shortcut(.character("3"), .command)
        case .viewDetails: return Shortcut(.character("4"), .command)
        case .quickPreview: return Shortcut(.space)
        case .cancel: return Shortcut(.escape)
        case .search: return Shortcut(.character("f"), .command)
        case .focusPath: return Shortcut(.character("l"), .command)
        case .goToParent: return Shortcut(.upArrow, .command)
        case .goBack: return Shortcut(.character("["), .command)
        case .goForward: return Shortcut(.character("]"), .command)
        case .newTab: return Shortcut(.character("t"), .command)
        case .closeTab: return Shortcut(.character("w"), .command)
        case .refresh: return Shortcut(.character("r"), .command)
        case .showContextMenu: return Shortcut(.returnKey, .control)
        case .duplicate: return Shortcut(.character("d"), .command)
        case .copyPath: return Shortcut(.character("c"), [.command, .option])
        case .togglePreviewPane: return Shortcut(.character("p"), [.command, .option])
        case .toggleSidebar: return Shortcut(.character("s"), [.command, .control])
        case .goThisMac: return Shortcut(.character("c"), [.command, .shift])
        case .goHome: return Shortcut(.character("h"), [.command, .shift])
        case .goDesktop: return Shortcut(.character("d"), [.command, .shift])
        case .goDocuments: return Shortcut(.character("o"), [.command, .shift])
        case .goDownloads: return Shortcut(.character("l"), [.command, .option])
        case .goApplications: return Shortcut(.character("a"), [.command, .shift])
        // Deliberately unbound: permanent deletion is menu-only with confirmation.
        case .deletePermanently, .batchRename, .addToFavorites, .grantAccess:
            return nil
        }
    }

    public var shortcutScope: ShortcutScope {
        switch self {
        case .rename, .quickPreview, .cancel, .showContextMenu: return .fileList
        default: return .menu
        }
    }

    /// Commands that act on the selection.
    public var requiresSelection: Bool {
        switch self {
        case .open, .getInfo, .rename, .duplicate, .batchRename, .moveToTrash, .deletePermanently,
             .copy, .cut, .copyPath, .quickPreview, .showContextMenu:
            return true
        default:
            return false
        }
    }

    /// Commands that modify the current folder.
    public var requiresWritableFolder: Bool {
        switch self {
        case .newFolder, .paste, .duplicate, .rename, .batchRename, .moveToTrash, .deletePermanently, .cut:
            return true
        default:
            return false
        }
    }

    /// When a text field has focus, these are forwarded to it as the standard editing
    /// action instead of acting on files.
    public var textEditingAction: String? {
        switch self {
        case .copy: return "copy:"
        case .cut: return "cut:"
        case .paste: return "paste:"
        case .selectAll: return "selectAll:"
        case .moveToTrash: return "deleteToBeginningOfLine:"
        default: return nil
        }
    }

    public static func command(for shortcut: Shortcut, scope: ShortcutScope) -> ExplorerCommand? {
        allCases.first { $0.shortcut == shortcut && $0.shortcutScope == scope }
    }

    public static func viewCommand(for mode: ViewMode) -> ExplorerCommand {
        switch mode {
        case .tiles: return .viewTiles
        case .compactList: return .viewCompactList
        case .gallery: return .viewGallery
        case .details: return .viewDetails
        }
    }
}

/// Snapshot of the state that decides which commands are enabled.
public struct CommandContext: Equatable, Sendable {
    public var selectionCount: Int = 0
    public var canPaste: Bool = false
    public var canGoBack: Bool = false
    public var canGoForward: Bool = false
    public var canGoUp: Bool = false
    public var isFolderLoaded: Bool = true
    public var isFolderWritable: Bool = true
    public var isEditingText: Bool = false
    public var tabCount: Int = 1

    public init(
        selectionCount: Int = 0, canPaste: Bool = false, canGoBack: Bool = false,
        canGoForward: Bool = false, canGoUp: Bool = false, isFolderLoaded: Bool = true,
        isFolderWritable: Bool = true, isEditingText: Bool = false, tabCount: Int = 1
    ) {
        self.selectionCount = selectionCount
        self.canPaste = canPaste
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.canGoUp = canGoUp
        self.isFolderLoaded = isFolderLoaded
        self.isFolderWritable = isFolderWritable
        self.isEditingText = isEditingText
        self.tabCount = tabCount
    }
}

public enum CommandRouting {
    public enum Decision: Equatable, Sendable {
        /// Perform the file-manager action.
        case perform
        /// Send the named standard action to the focused text editor.
        case forwardToTextEditor(String)
        /// Not applicable right now (the app beeps).
        case unavailable
    }

    public static func isEnabled(_ command: ExplorerCommand, in context: CommandContext) -> Bool {
        if command.requiresSelection && context.selectionCount == 0 { return false }
        switch command {
        case .rename: return context.selectionCount == 1 && context.isFolderWritable
        case .paste: return context.canPaste && context.isFolderLoaded && context.isFolderWritable
        case .newFolder: return context.isFolderLoaded && context.isFolderWritable
        case .goBack: return context.canGoBack
        case .goForward: return context.canGoForward
        case .goToParent: return context.canGoUp
        case .selectAll: return context.isFolderLoaded
        case .cut, .moveToTrash, .deletePermanently, .duplicate, .batchRename:
            return context.isFolderWritable
        default: return true
        }
    }

    /// Text-editing commands are always routable so the field editor keeps working;
    /// everything else follows `isEnabled`.
    public static func decide(_ command: ExplorerCommand, in context: CommandContext) -> Decision {
        if context.isEditingText, let action = command.textEditingAction {
            return .forwardToTextEditor(action)
        }
        return isEnabled(command, in: context) ? .perform : .unavailable
    }

    /// Commands bound in the menu bar, which must never be disabled there because
    /// their key equivalents also serve text fields.
    public static var alwaysEnabledInMenu: Set<ExplorerCommand> {
        Set(ExplorerCommand.allCases.filter { $0.textEditingAction != nil })
    }
}

public enum ViewMode: String, Codable, CaseIterable, Sendable {
    case details, tiles, compactList, gallery

    public var title: String {
        switch self {
        case .details: return "Details"
        case .tiles: return "Tiles"
        case .compactList: return "Compact List"
        case .gallery: return "Gallery"
        }
    }

    public var symbolName: String { ExplorerCommand.viewCommand(for: self).symbolName }
}
