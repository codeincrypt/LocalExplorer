import AppKit
import SwiftUI
import ExplorerCore

extension Shortcut {
    /// SwiftUI equivalent of the platform-neutral shortcut in ExplorerCore.
    var keyboardShortcut: KeyboardShortcut {
        let key: KeyEquivalent
        switch self.key {
        case .character(let c): key = KeyEquivalent(c)
        case .returnKey: key = .return
        case .delete: key = .delete
        case .escape: key = .escape
        case .space: key = .space
        case .upArrow: key = .upArrow
        case .downArrow: key = .downArrow
        case .leftArrow: key = .leftArrow
        case .rightArrow: key = .rightArrow
        }
        var modifiers: EventModifiers = []
        if self.modifiers.contains(.command) { modifiers.insert(.command) }
        if self.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if self.modifiers.contains(.option) { modifiers.insert(.option) }
        if self.modifiers.contains(.control) { modifiers.insert(.control) }
        return KeyboardShortcut(key, modifiers: modifiers)
    }
}

/// Menu bar. Every item is generated from `ExplorerCommand`, so titles and shortcuts are
/// defined once (ExplorerCore) and routed through `WindowModel.perform`.
struct ExplorerCommands: Commands {
    @FocusedObject private var model: WindowModel?
    @FocusedObject private var tab: TabModel?

    var body: some Commands {
        CommandGroup(after: .newItem) {
            item(.newTab)
            item(.newFolder)
            Divider()
            item(.open)
            item(.getInfo)
            item(.rename, note: "↩ in the file list")
            item(.duplicate)
            item(.batchRename)
            Divider()
            item(.addToFavorites)
            item(.grantAccess)
        }
        CommandGroup(replacing: .saveItem) {
            item(.closeTab)
            Button("Close Window") { model?.window?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .pasteboard) {
            item(.cut)
            item(.copy)
            item(.paste)
            item(.copyPath)
            Divider()
            item(.selectAll)
            Divider()
            item(.moveToTrash)
            item(.deletePermanently)
        }
        CommandGroup(replacing: .textEditing) {
            item(.search)
        }
        CommandGroup(before: .toolbar) {
            item(.viewTiles)
            item(.viewCompactList)
            item(.viewGallery)
            item(.viewDetails)
            Divider()
            Menu("Sort By") {
                ForEach(FileSortKey.allCases, id: \.self) { key in
                    Button {
                        guard let model else { return }
                        var sort = model.activeTab.sort
                        if sort.key == key { sort.ascending.toggle() } else { sort.key = key; sort.ascending = true }
                        model.setSort(sort)
                    } label: {
                        if tab?.sort.key == key {
                            Label(key.title, systemImage: (tab?.sort.ascending ?? true) ? "chevron.up" : "chevron.down")
                        } else {
                            Text(key.title)
                        }
                    }
                }
                Divider()
                Toggle("Folders on Top", isOn: Binding(
                    get: { tab?.sort.directoriesFirst ?? true },
                    set: { value in
                        guard let model else { return }
                        var sort = model.activeTab.sort
                        sort.directoriesFirst = value
                        model.setSort(sort)
                    }))
            }
            .disabled(model == nil)
            Divider()
            toggle(.toggleHiddenFiles, isOn: tab?.showHidden ?? false)
            toggle(.togglePreviewPane, isOn: model?.showPreviewPane ?? false)
            toggle(.toggleSidebar, isOn: model?.showSidebar ?? false)
            item(.quickPreview, note: "Space in the file list")
            item(.refresh)
            Divider()
        }
        CommandMenu("Go") {
            item(.goBack)
            item(.goForward)
            item(.goToParent)
            Divider()
            item(.goThisMac)
            item(.goHome)
            item(.goDesktop)
            item(.goDocuments)
            item(.goDownloads)
            item(.goApplications)
            Divider()
            item(.focusPath)
            Divider()
            Button("Show Next Tab") { model?.selectAdjacentTab(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled((model?.tabs.count ?? 0) < 2)
            Button("Show Previous Tab") { model?.selectAdjacentTab(offset: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled((model?.tabs.count ?? 0) < 2)
        }
    }

    /// A menu item for a command. File-list-scoped keys (Return, Space, Escape) are
    /// not bound as menu equivalents so they never steal keys from text fields or
    /// media players; their key is shown in the title instead.
    @ViewBuilder
    private func item(_ command: ExplorerCommand, note: String? = nil) -> some View {
        let title = note.map { "\(command.title)  (\($0))" } ?? command.title
        let button = Button(title) { model?.perform(command) }
            .disabled(!(model?.isEnabled(command) ?? false))
        if let shortcut = command.shortcut, command.shortcutScope == .menu {
            button.keyboardShortcut(shortcut.keyboardShortcut)
        } else {
            button
        }
    }

    @ViewBuilder
    private func toggle(_ command: ExplorerCommand, isOn: Bool) -> some View {
        let label = isOn ? command.title.replacingOccurrences(of: "Show", with: "Hide") : command.title
        if let shortcut = command.shortcut {
            Button(label) { model?.perform(command) }
                .keyboardShortcut(shortcut.keyboardShortcut)
                .disabled(model == nil)
        } else {
            Button(label) { model?.perform(command) }.disabled(model == nil)
        }
    }
}
