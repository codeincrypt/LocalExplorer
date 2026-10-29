import AppKit
import SwiftUI
import ExplorerCore

/// One description of the context menu, rendered either as SwiftUI (right-click) or as
/// an NSMenu (Control-Return from the keyboard), so both stay identical.
enum ContextMenuEntry {
    case command(ExplorerCommand, title: String? = nil)
    case action(String, symbol: String, () -> Void)
    case openWith([URL])
    case viewModes
    case divider
}

@MainActor
enum FileContextMenuBuilder {
    static func entries(for items: [FileItem], model: WindowModel) -> [ContextMenuEntry] {
        let tab = model.activeTab
        if items.isEmpty {
            return [
                .command(.newFolder),
                .command(.paste),
                .divider,
                .viewModes,
                .command(.toggleHiddenFiles, title: tab.showHidden ? "Hide Hidden Files" : "Show Hidden Files"),
                .command(.refresh),
                .divider,
                .action("Add “\(tab.title)” to Favorites", symbol: "star") { model.services.addFavorite(tab.currentURL) },
                .action("Copy Folder Path", symbol: "link") { model.services.clipboard.copyText(tab.currentURL.path) },
                .action("Reveal in Finder", symbol: "magnifyingglass") { model.revealInFinder([tab.currentURL]) },
            ]
        }
        var result: [ContextMenuEntry] = [.command(.open)]
        let folders = items.filter(\.isNavigableDirectory)
        if !folders.isEmpty {
            result.append(.action(folders.count == 1 ? "Open in New Tab" : "Open in New Tabs", symbol: "plus.square.on.square") {
                for folder in folders { model.newTab(at: folder.url) }
            })
        }
        let files = items.filter { !$0.isNavigableDirectory }
        if items.count == 1, let file = files.first, !file.isBrokenSymbolicLink {
            result.append(.openWith([file.url]))
        }
        if items.count == 1, let package = items.first, package.isPackage {
            result.append(.action("Show Package Contents", symbol: "shippingbox") { model.showPackageContents(package) })
        }
        result += [
            .command(.quickPreview),
            .divider,
            .command(.getInfo),
            .command(.rename),
        ]
        if items.count > 1 { result.append(.command(.batchRename)) }
        result += [
            .command(.duplicate),
            .command(.moveToTrash),
            .divider,
            .command(.copy),
            .command(.cut),
            .command(.copyPath),
            .divider,
        ]
        if !folders.isEmpty { result.append(.command(.addToFavorites)) }
        result += [
            .action("Reveal in Finder", symbol: "magnifyingglass") { model.revealInFinder(items.map(\.url)) },
            .divider,
            .command(.deletePermanently),
        ]
        return result
    }

    /// Makes `items` the selection so selection-based commands act on them.
    static func prepare(_ items: [FileItem], model: WindowModel) {
        let tab = model.activeTab
        if !items.isEmpty && Set(items.map(\.id)) != tab.selection {
            tab.select(urls: items.map(\.url))
        }
    }

    static func nsMenu(for items: [FileItem], model: WindowModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries(for: items, model: model) {
            switch entry {
            case .divider:
                menu.addItem(.separator())
            case .command(let command, let title):
                let item = ClosureMenuItem(title: title ?? command.title, symbol: command.symbolName) {
                    prepare(items, model: model)
                    model.perform(command)
                }
                item.isEnabled = model.isEnabled(command) || !items.isEmpty
                menu.addItem(item)
            case .action(let title, let symbol, let action):
                menu.addItem(ClosureMenuItem(title: title, symbol: symbol, action: action))
            case .openWith(let urls):
                let parent = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                for app in OpenWith.applications(for: urls) {
                    let item = ClosureMenuItem(title: app.name, symbol: nil) { OpenWith.open(urls, with: app.url, model: model) }
                    item.image = app.icon
                    item.image?.size = NSSize(width: 16, height: 16)
                    submenu.addItem(item)
                }
                parent.submenu = submenu
                menu.addItem(parent)
            case .viewModes:
                let parent = NSMenuItem(title: "View As", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                for mode in ViewMode.allCases {
                    let item = ClosureMenuItem(title: mode.title, symbol: mode.symbolName) { model.setViewMode(mode) }
                    item.state = model.activeTab.viewMode == mode ? .on : .off
                    submenu.addItem(item)
                }
                parent.submenu = submenu
                menu.addItem(parent)
            }
        }
        return menu
    }
}

struct FileContextMenu: View {
    let items: [FileItem]
    let model: WindowModel
    @ObservedObject var tab: TabModel

    var body: some View {
        let entries = FileContextMenuBuilder.entries(for: items, model: model)
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            switch entry {
            case .divider:
                Divider()
            case .command(let command, let title):
                Button {
                    FileContextMenuBuilder.prepare(items, model: model)
                    model.perform(command)
                } label: {
                    Label(title ?? command.title, systemImage: command.symbolName)
                }
            case .action(let title, let symbol, let action):
                Button(action: action) { Label(title, systemImage: symbol) }
            case .openWith(let urls):
                Menu("Open With") {
                    ForEach(OpenWith.applications(for: urls), id: \.url) { app in
                        Button {
                            OpenWith.open(urls, with: app.url, model: model)
                        } label: {
                            Label { Text(app.name) } icon: { Image(nsImage: app.icon) }
                        }
                    }
                }
            case .viewModes:
                Menu("View As") {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Button { model.setViewMode(mode) } label: {
                            if tab.viewMode == mode { Label(mode.title, systemImage: "checkmark") } else { Text(mode.title) }
                        }
                    }
                }
            }
        }
    }
}

@MainActor
enum OpenWith {
    struct App {
        let url: URL
        let name: String
        let icon: NSImage
    }

    static func applications(for urls: [URL]) -> [App] {
        guard let first = urls.first else { return [] }
        let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: first)
        var apps = NSWorkspace.shared.urlsForApplications(toOpen: first)
        if let defaultApp {
            apps.removeAll { $0 == defaultApp }
            apps.insert(defaultApp, at: 0)
        }
        return apps.prefix(20).map { url in
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return App(url: url, name: url == defaultApp ? "\(name) (default)" : name, icon: NSWorkspace.shared.icon(forFile: url.path))
        }
    }

    static func open(_ urls: [URL], with app: URL, model: WindowModel) {
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Task { @MainActor in model.show(error, title: "The item couldn’t be opened") }
            }
        }
    }
}

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, symbol: String?, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}
