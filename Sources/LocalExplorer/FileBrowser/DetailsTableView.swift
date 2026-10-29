import AppKit
import SwiftUI
import ExplorerCore

/// Default view: a native (virtualized) table with sortable, resizable, hideable
/// columns. Column layout is persisted.
struct DetailsTableView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: TabModel
    var focus: FocusState<FocusTarget?>.Binding
    @AppStorage("DetailsColumnCustomization") private var storedColumns = Data()
    @State private var columns = TableColumnCustomization<FileItem>()
    @State private var didLoadColumns = false
    @Environment(\.glass) private var glass

    var body: some View {
        Table(of: FileItem.self, selection: selection, sortOrder: sortOrder, columnCustomization: $columns) {
            TableColumn("Name", value: \FileItem.name) { item in
                NameCell(item: item, model: model)
            }
            .width(min: 160, ideal: 320)
            .customizationID("name")
            .disabledCustomizationBehavior(.visibility)

            TableColumn("Date Modified", value: \FileItem.sortModificationDate) { item in
                DateCell(date: item.modificationDate)
            }
            .width(min: 110, ideal: 160)
            .customizationID("modified")

            TableColumn("Date Created", value: \FileItem.sortCreationDate) { item in
                DateCell(date: item.creationDate)
            }
            .width(min: 110, ideal: 160)
            .customizationID("created")
            .defaultVisibility(.hidden)

            TableColumn("Type", value: \FileItem.kindDescription) { item in
                Text(item.kindDescription)
                    .foregroundStyle(glass.secondaryText)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 140)
            .customizationID("kind")

            TableColumn("Size", value: \FileItem.sortSize) { item in
                Text(item.size.map(DisplayFormat.byteCount) ?? "--")
                    .foregroundStyle(glass.secondaryText)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 90)
            .customizationID("size")
        } rows: {
            ForEach(tab.items) { item in
                TableRow(item)
                    .itemProvider { NSItemProvider(object: item.url as NSURL) }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: FileItem.ID.self) { ids in
            FileContextMenu(items: tab.items.filter { ids.contains($0.id) }, model: model, tab: tab)
        } primaryAction: { ids in
            let items = tab.items.filter { ids.contains($0.id) }
            if items.count == 1 { model.open(items[0]) } else { model.openSelection() }
        }
        .focused(focus, equals: .fileList)
        .fileListKeys(model: model, tab: tab, arrangement: nil)
        .accessibilityLabel("Files in \(tab.title)")
        .accessibilityIdentifier("fileList.details")
        .onAppear(perform: loadColumns)
        .onChange(of: columns) { _, newValue in
            guard didLoadColumns, let data = try? JSONEncoder().encode(newValue) else { return }
            storedColumns = data
        }
    }

    private var selection: Binding<Set<FileItem.ID>> {
        Binding(get: { tab.selection }, set: { tab.selection = $0 })
    }

    private var sortOrder: Binding<[KeyPathComparator<FileItem>]> {
        Binding(
            get: { [Self.comparator(for: tab.sort)] },
            set: { newValue in
                guard let first = newValue.first else { return }
                var sort = tab.sort
                sort.key = Self.key(for: first)
                sort.ascending = first.order == .forward
                model.setSort(sort)
            }
        )
    }

    static func comparator(for sort: FileSortDescriptor) -> KeyPathComparator<FileItem> {
        let order: SortOrder = sort.ascending ? .forward : .reverse
        switch sort.key {
        case .name: return KeyPathComparator(\FileItem.name, order: order)
        case .dateModified: return KeyPathComparator(\FileItem.sortModificationDate, order: order)
        case .dateCreated: return KeyPathComparator(\FileItem.sortCreationDate, order: order)
        case .size: return KeyPathComparator(\FileItem.sortSize, order: order)
        case .kind: return KeyPathComparator(\FileItem.kindDescription, order: order)
        }
    }

    static func key(for comparator: KeyPathComparator<FileItem>) -> FileSortKey {
        let path = comparator.keyPath
        if path == \FileItem.sortModificationDate as PartialKeyPath<FileItem> { return .dateModified }
        if path == \FileItem.sortCreationDate as PartialKeyPath<FileItem> { return .dateCreated }
        if path == \FileItem.sortSize as PartialKeyPath<FileItem> { return .size }
        if path == \FileItem.kindDescription as PartialKeyPath<FileItem> { return .kind }
        return .name
    }

    private func loadColumns() {
        if !storedColumns.isEmpty, let decoded = try? JSONDecoder().decode(TableColumnCustomization<FileItem>.self, from: storedColumns) {
            columns = decoded
        }
        didLoadColumns = true
    }
}

private struct NameCell: View {
    let item: FileItem
    let model: WindowModel
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: FileIconProvider.icon(for: item))
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if item.isSymbolicLink {
                Image(systemName: item.isBrokenSymbolicLink ? "link.badge.plus" : "arrow.turn.up.right")
                    .font(.system(size: 9))
                    .foregroundStyle(item.isBrokenSymbolicLink ? Color.red : Color.secondary)
                    .accessibilityLabel(item.isBrokenSymbolicLink ? "Broken alias" : "Alias")
            }
        }
        .opacity(item.isHidden ? 0.6 : 1)
        .padding(.vertical, 1)
        .background {
            RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(targeted ? 0.25 : 0))
        }
        .modifier(FolderDropTarget(item: item, model: model, targeted: $targeted))
        .help(item.name)
    }
}

private struct DateCell: View {
    let date: Date?
    @Environment(\.glass) private var glass
    var body: some View {
        Text(date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "--")
            .foregroundStyle(glass.secondaryText)
            .monospacedDigit()
            .lineLimit(1)
    }
}

/// Lets folders accept dropped files (move within a volume, copy across volumes).
struct FolderDropTarget: ViewModifier {
    let item: FileItem
    let model: WindowModel
    @Binding var targeted: Bool

    func body(content: Content) -> some View {
        if item.isNavigableDirectory {
            content.dropDestination(for: URL.self) { urls, _ in
                model.handleDrop(urls.filter { $0.standardizedFileURL != item.url }, into: item.url)
            } isTargeted: { targeted = $0 }
        } else {
            content
        }
    }
}
