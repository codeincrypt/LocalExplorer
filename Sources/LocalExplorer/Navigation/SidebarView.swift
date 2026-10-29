import AppKit
import SwiftUI
import ExplorerCore

struct SidebarView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: TabModel
    @ObservedObject var services: AppServices
    @ObservedObject var volumes: VolumeMonitor
    @Environment(\.glass) private var glass
    @AppStorage("SidebarCollapsedSections") private var collapsedRaw = ""
    @StateObject private var tree = SidebarTree()

    private struct Place: Identifiable {
        var id: String { url.path }
        let name: String
        let symbol: String
        let tint: Color
        let url: URL
    }

    private var standardPlaces: [Place] {
        let fm = FileManager.default
        func user(_ d: FileManager.SearchPathDirectory) -> URL? { fm.urls(for: d, in: .userDomainMask).first }
        var places: [Place] = [Place(name: "Home", symbol: "house.fill", tint: .blue, url: AppConfiguration.home)]
        let entries: [(String, String, Color, URL?)] = [
            ("Desktop", "menubar.dock.rectangle", .cyan, user(.desktopDirectory)),
            ("Documents", "doc.fill", .indigo, user(.documentDirectory)),
            ("Downloads", "arrow.down.circle.fill", .green, user(.downloadsDirectory)),
            ("Pictures", "photo.fill", .pink, user(.picturesDirectory)),
            ("Videos", "film.fill", .orange, user(.moviesDirectory)),
            ("Music", "music.note", .red, user(.musicDirectory)),
            ("Applications", "square.grid.3x3.fill", .purple, URL(fileURLWithPath: "/Applications")),
        ]
        for (name, symbol, tint, url) in entries {
            if let url, fm.fileExists(atPath: url.path) {
                places.append(Place(name: name, symbol: symbol, tint: tint, url: url.standardizedFileURL))
            }
        }
        return places
    }

    var body: some View {
        VStack(spacing: 0) {
            // Room for the window's traffic-light buttons.
            Color.clear.frame(height: 40)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    SidebarRow(name: ThisMac.title, symbol: "desktopcomputer", tint: .gray, url: ThisMac.url,
                               isCurrent: tab.isThisMac, model: model) {}
                    section("Favorites", id: "favorites", dropAction: addFavorites) {
                        if services.state.favorites.isEmpty {
                            Text("Drag folders here")
                                .font(.system(size: 11))
                                .foregroundStyle(glass.secondaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                        }
                        ForEach(services.state.favorites) { favorite in
                            node(section: "favorites", name: favorite.name, symbol: "star.fill", tint: .yellow,
                                 url: URL(fileURLWithPath: favorite.path),
                                 isUnavailable: services.unavailableLocationIDs.contains(favorite.id)) {
                                Button("Remove from Favorites") { services.removeFavorite(favorite.id) }
                            }
                        }
                    }
                    section("Locations", id: "locations") {
                        ForEach(standardPlaces) { place in
                            node(section: "locations", name: place.name, symbol: place.symbol, tint: place.tint, url: place.url) {
                                Button("Add to Favorites") { services.addFavorite(place.url) }
                            }
                        }
                    }
                    if !services.state.recents.paths.isEmpty {
                        section("Recent", id: "recent") {
                            ForEach(services.state.recents.paths.prefix(8), id: \.self) { path in
                                SidebarRow(name: FileManager.default.displayName(atPath: path), symbol: "clock.arrow.circlepath",
                                           tint: .gray, url: URL(fileURLWithPath: path),
                                           isCurrent: tab.currentURL.path == path,
                                           isUnavailable: !FileManager.default.fileExists(atPath: path), model: model) {
                                    Button("Remove from Recent") { services.state.recents.remove(path) }
                                    Button("Clear Recent") { services.clearRecents() }
                                }
                            }
                        }
                    }
                    section("Volumes", id: "volumes") {
                        ForEach(volumes.volumes) { volume in
                            node(section: "volumes", name: volume.name, symbol: volume.symbolName, tint: .secondary, url: volume.url,
                                 accessory: volume.isEjectable ? AnyView(ejectButton(volume)) : nil) {
                                if volume.isEjectable { Button("Eject “\(volume.name)”") { eject(volume) } }
                            }
                        }
                    }
                    if !services.state.authorizedLocations.isEmpty {
                        section("Authorized", id: "authorized") {
                            ForEach(services.state.authorizedLocations) { location in
                                node(section: "authorized", name: location.name, symbol: "lock.open.fill", tint: .teal,
                                     url: URL(fileURLWithPath: location.path),
                                     isUnavailable: services.unavailableLocationIDs.contains(location.id)) {
                                    Button("Remove Access") { services.removeAuthorizedLocation(location.id) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
            Rectangle().fill(glass.hairline).frame(height: 1)
            Button { model.perform(.grantAccess) } label: {
                Label("Grant Folder Access…", systemImage: "lock.open")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassCapsuleButtonStyle())
            .padding(10)
            .help("Choose a folder to browse. Access is remembered across launches.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar")
        .onAppear {
            tree.setShowHidden(tab.showHidden)
            tree.loadExpanded()
            reveal(tab.currentURL)
        }
        .onChange(of: tab.currentURL) { _, url in reveal(url) }
        .onChange(of: tab.showHidden) { _, value in tree.setShowHidden(value) }
        // A listing finishing means the folder may have gained or lost subfolders.
        .onChange(of: tab.loadState) { _, state in
            if state == .loaded, !tab.isThisMac { tree.refresh(tab.currentURL) }
        }
    }

    /// Every top-level row that can hold a folder tree, in display order.
    private var treeRoots: [(section: String, url: URL)] {
        services.state.favorites.map { ("favorites", URL(fileURLWithPath: $0.path)) }
            + standardPlaces.map { ("locations", $0.url) }
            + volumes.volumes.map { ("volumes", $0.url) }
            + services.state.authorizedLocations.map { ("authorized", URL(fileURLWithPath: $0.path)) }
    }

    private func reveal(_ url: URL) {
        guard !ThisMac.isThisMac(url) else { return }
        tree.reveal(url, roots: treeRoots)
    }

    /// A top-level row plus, when expanded, its subfolders.
    private func node<Menu: View>(
        section: String, name: String, symbol: String, tint: Color, url: URL,
        isUnavailable: Bool = false, accessory: AnyView? = nil,
        @ViewBuilder menu: @escaping () -> Menu
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            SidebarRow(
                name: name, symbol: symbol, tint: tint, url: url,
                isCurrent: tab.currentURL.standardizedFileURL.path == url.standardizedFileURL.path,
                isUnavailable: isUnavailable, model: model, accessory: accessory,
                disclosure: isUnavailable ? nil : SidebarDisclosure(tree: tree, section: section, url: url),
                menu: menu
            )
            SidebarChildren(tree: tree, tab: tab, services: services, model: model,
                            section: section, url: url, depth: 1)
        }
    }

    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }

    private func toggle(_ id: String) {
        var set = collapsed
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        collapsedRaw = set.sorted().joined(separator: ",")
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, id: String, dropAction: (([URL]) -> Bool)? = nil, @ViewBuilder content: () -> Content) -> some View {
        let isCollapsed = collapsed.contains(id)
        VStack(alignment: .leading, spacing: 1) {
            Button { withAnimation(.easeOut(duration: 0.15)) { toggle(id) } } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .frame(width: 10)
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                    Spacer()
                }
                .foregroundStyle(glass.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) section, \(isCollapsed ? "collapsed" : "expanded")")
            if !isCollapsed { content() }
        }
        .modifier(OptionalDrop(action: dropAction))
    }

    private func addFavorites(_ urls: [URL]) -> Bool {
        let folders = urls.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
        folders.forEach(services.addFavorite)
        return !folders.isEmpty
    }

    private func ejectButton(_ volume: VolumeMonitor.Volume) -> some View {
        Button { eject(volume) } label: {
            Image(systemName: "eject.fill").font(.system(size: 9))
        }
        .buttonStyle(.plain)
        .foregroundStyle(glass.secondaryText)
        .help("Eject \(volume.name)")
        .accessibilityLabel("Eject \(volume.name)")
    }

    private func eject(_ volume: VolumeMonitor.Volume) {
        if PathBreadcrumbs.isDescendant(tab.currentURL, of: volume.url, orEqual: true) {
            tab.navigate(to: AppConfiguration.home)
        }
        do {
            try volumes.eject(volume)
        } catch {
            model.show(error, title: "“\(volume.name)” couldn’t be ejected")
        }
    }
}

private struct OptionalDrop: ViewModifier {
    let action: (([URL]) -> Bool)?
    @State private var targeted = false
    @Environment(\.glass) private var glass

    func body(content: Content) -> some View {
        if let action {
            content
                .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: targeted ? 1.5 : 0))
                .dropDestination(for: URL.self) { urls, _ in action(urls) } isTargeted: { targeted = $0 }
        } else {
            content
        }
    }
}

enum SidebarMetrics {
    static let indent: CGFloat = 14
    static let chevronWidth: CGFloat = 16
}

struct SidebarRow<MenuContent: View>: View {
    let name: String
    let symbol: String
    let tint: Color
    let url: URL
    let isCurrent: Bool
    var isUnavailable = false
    let model: WindowModel
    var accessory: AnyView? = nil
    /// Expand/collapse control for folders that can show subfolders; nil keeps the slot empty.
    var disclosure: SidebarDisclosure? = nil
    /// Nesting level; each level indents the row.
    var depth = 0
    @ViewBuilder var menu: () -> MenuContent

    @State private var hovering = false
    @State private var dropTargeted = false
    @Environment(\.glass) private var glass

    var body: some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: CGFloat(depth) * SidebarMetrics.indent, height: 1)
            if let disclosure {
                DisclosureChevron(disclosure: disclosure, isCurrent: isCurrent, name: name)
            } else {
                Color.clear.frame(width: SidebarMetrics.chevronWidth, height: 1)
            }
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
                .frame(width: 18)
                .padding(.trailing, 4)
            Text(name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            Spacer(minLength: 0)
            if isUnavailable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .help("This location is not available")
            }
            if let accessory { accessory }
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isCurrent ? AnyShapeStyle(glass.selectionFill)
                      : AnyShapeStyle(dropTargeted ? glass.softSelectionFill : (hovering ? glass.controlHover : .clear)))
        }
        .contentShape(Rectangle())
        .opacity(isUnavailable ? 0.55 : 1)
        .onHover { hovering = $0 }
        .onTapGesture { model.navigate(to: url) }
        .dropDestination(for: URL.self) { urls, _ in model.handleDrop(urls, into: url) } isTargeted: { dropTargeted = $0 }
        .contextMenu {
            Button("Open in New Tab") { model.newTab(at: url) }
            Button("Reveal in Finder") { model.revealInFinder([url]) }
            Button("Copy Path") { AppServices.shared.clipboard.copyText(url.path) }
            Divider()
            menu()
        }
        .help(url.path)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(name)
        .accessibilityAction { model.navigate(to: url) }
        .accessibilityAction(named: disclosure?.isExpanded == true ? "Collapse" : "Expand") { disclosure?.toggle() }
    }
}

/// Binds a sidebar row to its expanded state in the shared `SidebarTree`.
@MainActor
struct SidebarDisclosure {
    let tree: SidebarTree
    let section: String
    let url: URL

    var isExpanded: Bool { tree.isExpanded(section: section, url: url) }
    var isEnabled: Bool { tree.canExpand(url) }

    func toggle() {
        withAnimation(.easeOut(duration: 0.15)) { tree.toggle(section: section, url: url) }
    }
}

/// The arrow at the left of a row. Its own hit target, so clicking it expands without navigating.
private struct DisclosureChevron: View {
    let disclosure: SidebarDisclosure
    let isCurrent: Bool
    let name: String
    @Environment(\.glass) private var glass

    var body: some View {
        Group {
            if disclosure.isEnabled {
                Button { disclosure.toggle() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(disclosure.isExpanded ? 90 : 0))
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(glass.secondaryText))
                        .frame(width: SidebarMetrics.chevronWidth, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(disclosure.isExpanded ? "Collapse" : "Expand") \(name)")
            } else {
                Color.clear.frame(width: SidebarMetrics.chevronWidth, height: 1)
            }
        }
    }
}

/// Subfolders of an expanded row, nested one level deeper. Each child can itself expand.
struct SidebarChildren: View {
    @ObservedObject var tree: SidebarTree
    @ObservedObject var tab: TabModel
    @ObservedObject var services: AppServices
    let model: WindowModel
    let section: String
    let url: URL
    let depth: Int

    var body: some View {
        if tree.isExpanded(section: section, url: url), let folders = tree.children[url.path] {
            ForEach(folders) { folder in
                SidebarRow(
                    name: folder.name, symbol: "folder", tint: .blue, url: folder.url,
                    isCurrent: tab.currentURL.standardizedFileURL.path == folder.url.standardizedFileURL.path,
                    model: model,
                    disclosure: SidebarDisclosure(tree: tree, section: section, url: folder.url),
                    depth: depth
                ) {
                    Button("Add to Favorites") { services.addFavorite(folder.url) }
                }
                SidebarChildren(tree: tree, tab: tab, services: services, model: model,
                                section: section, url: folder.url, depth: depth + 1)
            }
        }
    }
}
