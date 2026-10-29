import AppKit
import SwiftUI
import ExplorerCore

// MARK: - Shared cell behaviour

/// Click, double-click, context menu and drag for custom (non-table) layouts.
struct ItemInteraction: ViewModifier {
    let item: FileItem
    let model: WindowModel
    let tab: TabModel
    var focus: FocusState<FocusTarget?>.Binding

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.open(item) }
            .simultaneousGesture(TapGesture().onEnded {
                tab.click(item, modifiers: NSEvent.modifierFlags)
                focus.wrappedValue = .fileList
            })
            .contextMenu {
                let targets = tab.selection.contains(item.id) ? tab.selectedItems : [item]
                FileContextMenu(items: targets, model: model, tab: tab)
            }
            .onDrag {
                // Dragging an unselected item drags just that item.
                NSItemProvider(object: item.url as NSURL)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(tab.selection.contains(item.id) ? [.isSelected] : [])
            .accessibilityAction { model.open(item) }
            .accessibilityAction(named: "Rename") {
                tab.selectionModel.click(item.id, order: tab.itemIDs)
                model.perform(.rename)
            }
    }
}

/// Thumbnail when the content type has one, file icon otherwise. Generation is
/// cancelled automatically when the cell scrolls away.
struct FileThumbnailView: View {
    let item: FileItem
    let size: CGFloat
    let services: AppServices
    @Environment(\.displayScale) private var scale
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: max(3, size * 0.03), style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            } else {
                Image(nsImage: FileIconProvider.icon(for: item))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .task(id: ThumbnailCacheKey(item: item, pixelSize: ThumbnailCacheKey.bucket(forPixels: Double(size * scale)))) {
            if let cached = services.thumbnails.cachedThumbnail(for: item, pointSize: size, scale: scale) {
                image = cached
                return
            }
            image = nil
            image = await services.thumbnails.thumbnail(for: item, pointSize: size, scale: scale)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Tiles

struct TilesView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: TabModel
    @ObservedObject var services: AppServices
    var focus: FocusState<FocusTarget?>.Binding
    @State private var columns = 1
    @Environment(\.glass) private var glass

    private let spacing: CGFloat = 10
    private let padding: CGFloat = 14
    private var tileSize: CGFloat { CGFloat(services.preferences.tileSize) }
    private var cellWidth: CGFloat { tileSize + 24 }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: cellWidth, maximum: cellWidth), spacing: spacing)], spacing: spacing) {
                        ForEach(tab.items) { item in
                            TileCell(item: item, isSelected: tab.selection.contains(item.id), tileSize: tileSize, model: model, services: services)
                                .frame(width: cellWidth)
                                .modifier(ItemInteraction(item: item, model: model, tab: tab, focus: focus))
                                .id(item.id)
                        }
                    }
                    .padding(padding)
                }
                .onChange(of: tab.selectionModel.cursor) { _, cursor in
                    if let cursor { scroller.scrollTo(cursor) }
                }
            }
            .onAppear { columns = columnCount(proxy.size.width) }
            .onChange(of: proxy.size.width) { _, width in columns = columnCount(width) }
            .onChange(of: tileSize) { _, _ in columns = columnCount(proxy.size.width) }
        }
        .background(BackgroundClickCatcher(tab: tab, model: model, focus: focus))
        .focusable()
        .focusEffectDisabled()
        .focused(focus, equals: .fileList)
        .fileListKeys(model: model, tab: tab, arrangement: .rowMajor(columns: columns))
        .accessibilityLabel("Files in \(tab.title), tiles")
        .accessibilityIdentifier("fileList.tiles")
    }

    private func columnCount(_ width: CGFloat) -> Int {
        GridLayoutMath.columns(availableWidth: Double(width), itemWidth: Double(cellWidth), spacing: Double(spacing), padding: Double(padding))
    }
}

private struct TileCell: View {
    let item: FileItem
    let isSelected: Bool
    let tileSize: CGFloat
    let model: WindowModel
    let services: AppServices
    @State private var targeted = false
    @State private var hovering = false
    @Environment(\.glass) private var glass

    var body: some View {
        VStack(spacing: 6) {
            FileThumbnailView(item: item, size: tileSize * 0.78, services: services)
                .frame(height: tileSize * 0.82)
            Text(item.name)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(glass.selectionFill) : AnyShapeStyle(Color.clear))
                }
            if !item.isNavigableDirectory {
                Text(item.size.map(DisplayFormat.byteCount) ?? item.kindDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(glass.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected || targeted ? AnyShapeStyle(glass.softSelectionFill) : AnyShapeStyle(hovering ? glass.controlFill : .clear))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isSelected ? 0.7 : 0), lineWidth: 1)
        }
        .opacity(item.isHidden ? 0.6 : 1)
        .onHover { hovering = $0 }
        .modifier(FolderDropTarget(item: item, model: model, targeted: $targeted))
        .help(item.name)
        .accessibilityLabel("\(item.name), \(item.kindDescription)")
    }
}

// MARK: - Compact list

/// Dense names flowing in columns (like Windows "List"); scrolls horizontally.
struct CompactListView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: TabModel
    var focus: FocusState<FocusTarget?>.Binding
    @State private var rows = 1

    private let rowHeight: CGFloat = 22
    private let rowSpacing: CGFloat = 2
    private let padding: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroller in
                ScrollView(.horizontal) {
                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(rowHeight), spacing: rowSpacing), count: max(1, rows)), alignment: .top, spacing: 18) {
                        ForEach(tab.items) { item in
                            CompactRow(item: item, isSelected: tab.selection.contains(item.id), model: model)
                                .frame(width: 250, alignment: .leading)
                                .modifier(ItemInteraction(item: item, model: model, tab: tab, focus: focus))
                                .id(item.id)
                        }
                    }
                    .padding(padding)
                }
                .onChange(of: tab.selectionModel.cursor) { _, cursor in
                    if let cursor { scroller.scrollTo(cursor) }
                }
            }
            .onAppear { rows = rowCount(proxy.size.height) }
            .onChange(of: proxy.size.height) { _, height in rows = rowCount(height) }
        }
        .background(BackgroundClickCatcher(tab: tab, model: model, focus: focus))
        .focusable()
        .focusEffectDisabled()
        .focused(focus, equals: .fileList)
        .fileListKeys(model: model, tab: tab, arrangement: .columnMajor(rows: rows))
        .accessibilityLabel("Files in \(tab.title), compact list")
        .accessibilityIdentifier("fileList.compactList")
    }

    private func rowCount(_ height: CGFloat) -> Int {
        // Leave room for the horizontal scroller.
        GridLayoutMath.rows(availableHeight: Double(height - 14), rowHeight: Double(rowHeight), spacing: Double(rowSpacing), padding: Double(padding))
    }
}

private struct CompactRow: View {
    let item: FileItem
    let isSelected: Bool
    let model: WindowModel
    @State private var targeted = false
    @Environment(\.glass) private var glass

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: FileIconProvider.icon(for: item))
                .resizable()
                .frame(width: 16, height: 16)
            Text(item.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(glass.selectionFill) : AnyShapeStyle(targeted ? glass.softSelectionFill : .clear))
        }
        .opacity(item.isHidden ? 0.6 : 1)
        .modifier(FolderDropTarget(item: item, model: model, targeted: $targeted))
        .help(item.name)
    }
}

// MARK: - Gallery

/// Large preview with neighbouring items in a filmstrip.
struct GalleryView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: TabModel
    @ObservedObject var services: AppServices
    var focus: FocusState<FocusTarget?>.Binding
    @Environment(\.glass) private var glass

    private var current: FileItem? { tab.focusedItem ?? tab.items.first }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                stepButton("chevron.left", .left)
                ZStack {
                    if let current {
                        // Full viewer: zoom/rotate images, PDF pages and search, media
                        // playback, text, Quick Look documents.
                        PreviewHost(item: current, style: .full, services: services, open: { model.open(current) })
                            .id(current.id)
                    } else {
                        Text("No items").foregroundStyle(glass.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                stepButton("chevron.right", .right)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            if let current {
                HStack(spacing: 8) {
                    Text(current.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text(current.kindDescription).foregroundStyle(glass.secondaryText)
                    if let size = current.size { Text(DisplayFormat.byteCount(size)).foregroundStyle(glass.secondaryText) }
                }
                .font(.system(size: 11))
                .padding(.vertical, 6)
            }
            Rectangle().fill(glass.hairline).frame(height: 1)
            ScrollViewReader { scroller in
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(spacing: 8) {
                        ForEach(tab.items) { item in
                            let selected = tab.selection.contains(item.id)
                            VStack(spacing: 4) {
                                FileThumbnailView(item: item, size: 64, services: services)
                                    .padding(6)
                                    .background {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(selected ? AnyShapeStyle(glass.softSelectionFill) : AnyShapeStyle(Color.clear))
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(Color.accentColor.opacity(selected ? 0.9 : 0), lineWidth: 2)
                                    }
                                Text(item.name)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(width: 84)
                            }
                            .modifier(ItemInteraction(item: item, model: model, tab: tab, focus: focus))
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(height: 118)
                .onChange(of: tab.selectionModel.cursor) { _, cursor in
                    if let cursor { withAnimation(.easeOut(duration: 0.15)) { scroller.scrollTo(cursor, anchor: .center) } }
                }
            }
            // Keys belong to the filmstrip only, so the viewer's own controls (PDF
            // search, media player, text selection) keep their keys.
            .focusable()
            .focusEffectDisabled()
            .focused(focus, equals: .fileList)
            .fileListKeys(model: model, tab: tab, arrangement: .strip)
        }
        .onAppear {
            if tab.selection.isEmpty, let first = tab.items.first {
                tab.selectionModel.click(first.id, order: tab.itemIDs)
            }
        }
        .accessibilityLabel("Gallery of \(tab.title)")
        .accessibilityIdentifier("fileList.gallery")
    }

    private func stepButton(_ symbol: String, _ direction: MoveDirection) -> some View {
        Button { tab.moveSelection(direction, arrangement: .strip, extend: false) } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).frame(width: 34, height: 34)
        }
        .buttonStyle(GlassIconButtonStyle(size: CGSize(width: 34, height: 34)))
        .accessibilityLabel(direction == .left ? "Previous item" : "Next item")
    }
}

/// Clicking empty space clears the selection and focuses the list; right-clicking it
/// shows folder actions.
struct BackgroundClickCatcher: View {
    @ObservedObject var tab: TabModel
    let model: WindowModel
    var focus: FocusState<FocusTarget?>.Binding

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                tab.selectionModel.clear()
                focus.wrappedValue = .fileList
            }
            .contextMenu { FileContextMenu(items: [], model: model, tab: tab) }
    }
}
