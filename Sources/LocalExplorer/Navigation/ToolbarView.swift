import AppKit
import SwiftUI
import ExplorerCore

struct ExplorerToolbar: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: TabModel
    var focus: FocusState<FocusTarget?>.Binding
    @Environment(\.glass) private var glass

    var body: some View {
        HStack(spacing: 8) {
            GlassGroup {
                commandButton(.goBack)
                commandButton(.goForward)
                commandButton(.goToParent)
                commandButton(.refresh)
            }
            AddressBar(model: model, tab: tab, focus: focus)
                .frame(minWidth: 160, maxWidth: .infinity)
            GlassGroup {
                commandButton(.newFolder)
            }
            if !tab.selection.isEmpty {
                GlassGroup {
                    commandButton(.copy)
                    commandButton(.cut)
                    commandButton(.rename)
                    commandButton(.moveToTrash)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            GlassGroup {
                ForEach([ViewMode.tiles, .compactList, .gallery, .details], id: \.self) { mode in
                    Button { model.setViewMode(mode) } label: { Image(systemName: mode.symbolName) }
                        .buttonStyle(GlassIconButtonStyle(isOn: tab.viewMode == mode))
                        .help("View as \(mode.title) (\(ExplorerCommand.viewCommand(for: mode).shortcut?.displayString ?? ""))")
                        .accessibilityLabel("View as \(mode.title)")
                        .accessibilityIdentifier("viewMode.\(mode.rawValue)")
                        .accessibilityAddTraits(tab.viewMode == mode ? .isSelected : [])
                }
            }
            SortMenu(model: model, tab: tab)
            GlassGroup {
                Button { model.perform(.togglePreviewPane) } label: { Image(systemName: "sidebar.right") }
                    .buttonStyle(GlassIconButtonStyle(isOn: model.showPreviewPane))
                    .help("Preview pane (⌥⌘P)")
                    .accessibilityLabel("Toggle preview pane")
                    .accessibilityIdentifier("togglePreviewPane")
            }
            SearchField(model: model, tab: tab, focus: focus)
                .frame(width: 190)
        }
        .animation(.easeOut(duration: 0.15), value: tab.selection.isEmpty)
        .frame(height: 36)
        .background(WindowDragArea())
    }

    private func commandButton(_ command: ExplorerCommand) -> some View {
        Button { model.perform(command) } label: { Image(systemName: command.symbolName) }
            .buttonStyle(GlassIconButtonStyle())
            .disabled(!model.isEnabled(command))
            .help("\(command.title)\(command.shortcut.map { " (\($0.displayString))" } ?? "")")
            .accessibilityLabel(command.title)
    }
}

/// Breadcrumbs that turn into an editable path field (click the empty area or ⌘L).
struct AddressBar: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: TabModel
    var focus: FocusState<FocusTarget?>.Binding
    @EnvironmentObject private var services: AppServices
    @Environment(\.glass) private var glass
    @State private var text = ""

    var body: some View {
        HStack(spacing: 6) {
            if model.isEditingPath {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(glass.secondaryText)
                TextField("Enter a path", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .focused(focus, equals: .path)
                    .onSubmit(commit)
                    .onExitCommand(perform: endEditing)
                    .onAppear { text = editablePath }
                    .accessibilityLabel("Path")
                    .accessibilityIdentifier("pathField")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 1) {
                            let crumbs = PathBreadcrumbs.components(for: tab.currentURL, home: AppConfiguration.home, rootName: services.volumes.rootVolumeName)
                            ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, crumb in
                                if index > 0 {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(glass.secondaryText)
                                }
                                BreadcrumbButton(crumb: crumb, isLast: index == crumbs.count - 1, isFirst: index == 0, model: model)
                                    .id(crumb.id)
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(tab.currentURL.path, anchor: .trailing) }
                    .onChange(of: tab.currentURL) { _, url in proxy.scrollTo(url.path, anchor: .trailing) }
                }
                Spacer(minLength: 0)
                Button { model.perform(.focusPath) } label: {
                    Image(systemName: "pencil.line").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(glass.secondaryText)
                .help("Edit path (⌘L)")
                .accessibilityLabel("Edit path")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background { Capsule(style: .continuous).fill(glass.controlFill) }
        .overlay { Capsule(style: .continuous).strokeBorder(model.isEditingPath ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(glass.borderGradient), lineWidth: model.isEditingPath ? 1.5 : 0.75) }
        .contentShape(Capsule())
        .onTapGesture(count: 2) { model.perform(.focusPath) }
        .onChange(of: model.isEditingPath) { _, editing in
            if editing { text = editablePath }
        }
        .onChange(of: focus.wrappedValue) { _, newValue in
            if model.isEditingPath && newValue != .path { model.isEditingPath = false }
        }
    }

    /// The "This Mac" page has no path of its own, so the field starts empty.
    private var editablePath: String { tab.isThisMac ? "" : tab.currentURL.path }

    private func commit() {
        let base = tab.isThisMac ? AppConfiguration.home : tab.currentURL
        guard let url = PathInputParser.resolve(text, relativeTo: base, home: AppConfiguration.home) else {
            NSSound.beep()
            return
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue && !FileTypeClassifier.looksLikePackage(name: url.lastPathComponent) {
                tab.navigate(to: url)
            } else {
                tab.navigate(to: url.deletingLastPathComponent(), selecting: url)
            }
            endEditing()
        } else {
            model.errorAlert = ErrorAlert(title: "Can’t find “\(text)”", message: "Check the spelling and try again. Local Explorer only opens local paths and mounted volumes.")
        }
    }

    private func endEditing() {
        model.isEditingPath = false
        model.requestFocus(.fileList)
    }
}

private struct BreadcrumbButton: View {
    let crumb: Breadcrumb
    let isLast: Bool
    let isFirst: Bool
    let model: WindowModel
    @State private var hovering = false
    @State private var targeted = false
    @Environment(\.glass) private var glass

    var body: some View {
        Button { model.navigate(to: crumb.url) } label: {
            HStack(spacing: 4) {
                if isFirst {
                    Image(systemName: crumb.url == ThisMac.url ? "desktopcomputer" : (crumb.url == AppConfiguration.home ? "house.fill" : "internaldrive"))
                        .font(.system(size: 10))
                }
                Text(crumb.name)
                    .font(.system(size: 12, weight: isLast ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(targeted ? glass.softSelectionFill : (hovering ? glass.controlHover : .clear))
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .dropDestination(for: URL.self) { urls, _ in model.handleDrop(urls, into: crumb.url) } isTargeted: { targeted = $0 }
        .help(crumb.url.path)
        .accessibilityLabel("Go to \(crumb.name)")
    }
}

struct SearchField: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: TabModel
    var focus: FocusState<FocusTarget?>.Binding
    @Environment(\.glass) private var glass

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(glass.secondaryText)
            TextField("Search \(tab.title)", text: $tab.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused(focus, equals: .search)
                .onExitCommand {
                    tab.searchQuery = ""
                    model.requestFocus(.fileList)
                }
                .onSubmit { model.requestFocus(.fileList) }
                .accessibilityLabel("Search current folder")
                .accessibilityIdentifier("searchField")
            if !tab.searchQuery.isEmpty {
                Button { tab.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(glass.secondaryText)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background { Capsule(style: .continuous).fill(glass.controlFill) }
        .overlay { Capsule(style: .continuous).strokeBorder(focus.wrappedValue == .search ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(glass.borderGradient), lineWidth: focus.wrappedValue == .search ? 1.5 : 0.75) }
        .help("Search this folder. Supports *.jpg, kind:image, ext:pdf (⌘F)")
    }
}

struct SortMenu: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: TabModel

    var body: some View {
        GlassGroup {
            Menu {
                ForEach(FileSortKey.allCases, id: \.self) { key in
                    Button {
                        var sort = tab.sort
                        if sort.key == key { sort.ascending.toggle() } else { sort.key = key; sort.ascending = key == .name || key == .kind }
                        model.setSort(sort)
                    } label: {
                        if tab.sort.key == key {
                            Label(key.title, systemImage: tab.sort.ascending ? "chevron.up" : "chevron.down")
                        } else {
                            Text(key.title)
                        }
                    }
                }
                Divider()
                Toggle("Folders on Top", isOn: Binding(
                    get: { tab.sort.directoriesFirst },
                    set: { var s = tab.sort; s.directoriesFirst = $0; model.setSort(s) }))
                Toggle("Show Hidden Files", isOn: Binding(get: { tab.showHidden }, set: { _ in model.toggleHiddenFiles() }))
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 28)
        }
        .help("Sort and display options")
        .accessibilityLabel("Sort options")
    }
}

struct TabStrip: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(model.tabs) { tab in
                TabChip(tab: tab, isActive: tab.id == model.activeTabID, canClose: model.tabs.count > 1, model: model)
            }
            Button { model.newTab() } label: { Image(systemName: "plus") }
                .buttonStyle(GlassIconButtonStyle(size: CGSize(width: 28, height: 26)))
                .help("New Tab (⌘T)")
                .accessibilityLabel("New tab")
        }
        .frame(height: 28)
    }
}

private struct TabChip: View {
    @ObservedObject var tab: TabModel
    let isActive: Bool
    let canClose: Bool
    let model: WindowModel
    @State private var hovering = false
    @State private var targeted = false
    @Environment(\.glass) private var glass

    var body: some View {
        ZStack {
            Text(tab.title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 26)
            HStack {
                if canClose && (hovering || isActive) {
                    Button { model.closeTab(tab.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Close Tab (⌘W)")
                    .accessibilityLabel("Close tab \(tab.title)")
                }
                Spacer()
            }
            .padding(.leading, 6)
        }
        .frame(maxWidth: .infinity, minHeight: 26)
        .background {
            Capsule(style: .continuous)
                .fill(isActive ? glass.controlPressed : (targeted ? glass.softSelectionFill : (hovering ? glass.controlHover : glass.controlFill)))
        }
        .overlay { Capsule(style: .continuous).strokeBorder(glass.borderGradient, lineWidth: isActive ? 1 : 0.5) }
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .onTapGesture { model.selectTab(tab.id) }
        .dropDestination(for: URL.self) { urls, _ in model.handleDrop(urls, into: tab.currentURL) } isTargeted: { targeted = $0 }
        .help(tab.currentURL.path)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("Tab \(tab.title)")
    }
}

struct StatusBar: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: TabModel
    @ObservedObject var services: AppServices
    @Environment(\.glass) private var glass

    var body: some View {
        HStack(spacing: 12) {
            Text(DisplayFormat.statusSummary(total: tab.items.count, selected: tab.selection.count, selectedBytes: tab.selectedBytes))
                .monospacedDigit()
                .accessibilityIdentifier("statusSummary")
            if !tab.searchQuery.isEmpty {
                Text("· matching “\(tab.searchQuery)”").foregroundStyle(glass.secondaryText)
            }
            let hiddenCount = tab.allItems.lazy.filter(\.isHidden).count
            if !tab.showHidden && hiddenCount > 0 && tab.searchQuery.isEmpty {
                Text("· \(hiddenCount) hidden").foregroundStyle(glass.secondaryText)
            }
            Spacer()
            if let operation = model.operation {
                OperationProgressView(status: operation) { model.cancelOperation() }
            }
            Spacer()
            if tab.viewMode == .tiles || tab.viewMode == .gallery {
                Image(systemName: "photo").font(.system(size: 9)).foregroundStyle(glass.secondaryText)
                Slider(value: Binding(get: { services.preferences.tileSize }, set: { services.preferences.tileSize = $0 }), in: 64...256)
                    .controlSize(.mini)
                    .frame(width: 90)
                    .accessibilityLabel("Icon size")
                Image(systemName: "photo").font(.system(size: 13)).foregroundStyle(glass.secondaryText)
            }
            if !tab.isFolderWritable && tab.isLoaded {
                Label("Read only", systemImage: "lock.fill").foregroundStyle(.orange)
            }
            if let capacity = tab.availableCapacity {
                Text("\(DisplayFormat.byteCount(capacity)) available").foregroundStyle(glass.secondaryText).monospacedDigit()
            }
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .glassPanel(cornerRadius: 10, shadow: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status bar")
    }
}

struct OperationProgressView: View {
    let status: OperationStatus
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ProgressView(value: status.progress?.fraction ?? 0)
                .progressViewStyle(.linear)
                .frame(width: 120)
            Text(label).lineLimit(1).truncationMode(.middle).frame(maxWidth: 220, alignment: .leading)
            Button(action: cancel) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .help("Cancel (takes effect after the current item)")
                .accessibilityLabel("Cancel operation")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private var label: String {
        guard let p = status.progress else { return "\(status.kind.progressTitle)…" }
        let count = "\(min(p.completedItems + 1, p.totalItems)) of \(p.totalItems)"
        return p.currentName.isEmpty ? "\(status.kind.progressTitle) \(count)" : "\(status.kind.progressTitle) “\(p.currentName)” (\(count))"
    }
}
