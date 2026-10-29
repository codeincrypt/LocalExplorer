import AppKit
import SwiftUI
import ExplorerCore

/// The "This Mac" start page: the standard folders, then the mounted drives with how
/// full they are. Click selects, double-click (or Return) opens.
struct ThisMacView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: TabModel
    @ObservedObject var volumes: VolumeMonitor
    @State private var selectedID: String?
    @State private var collapsed: Set<Section> = []
    @Environment(\.glass) private var glass

    private enum Section: Hashable { case folders, drives }

    private struct Folder: Identifiable {
        var id: String { url.path }
        let name: String
        let url: URL
    }

    private var folders: [Folder] {
        let fm = FileManager.default
        let entries: [(String, FileManager.SearchPathDirectory)] = [
            ("Desktop", .desktopDirectory),
            ("Documents", .documentDirectory),
            ("Downloads", .downloadsDirectory),
            ("Music", .musicDirectory),
            ("Pictures", .picturesDirectory),
            ("Videos", .moviesDirectory),
        ]
        return entries.compactMap { name, directory in
            guard let url = fm.urls(for: directory, in: .userDomainMask).first,
                  fm.fileExists(atPath: url.path) else { return nil }
            return Folder(name: name, url: url.standardizedFileURL)
        }
    }

    var body: some View {
        let folders = folders
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(.folders, title: "Folders", count: folders.count) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 4) {
                        ForEach(folders) { folder in
                            FolderTile(
                                name: folder.name, url: folder.url,
                                isSelected: selectedID == folder.id,
                                select: { selectedID = folder.id },
                                open: { model.navigate(to: folder.url) },
                                model: model
                            )
                        }
                    }
                }
                section(.drives, title: "Devices and drives", count: volumes.volumes.count) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 4) {
                        ForEach(volumes.volumes) { volume in
                            DriveTile(
                                volume: volume,
                                capacity: volumes.capacities[volume.url.path],
                                isSelected: selectedID == volume.id,
                                select: { selectedID = volume.id },
                                open: { model.navigate(to: volume.url) },
                                eject: { eject(volume) },
                                model: model
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.automatic)
        .contentShape(Rectangle())
        .onTapGesture { selectedID = nil }
        .onAppear { volumes.reload() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ThisMac.title)
        .accessibilityIdentifier("thisMacPage")
    }

    private func section<Content: View>(_ id: Section, title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        let isCollapsed = collapsed.contains(id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isCollapsed { collapsed.remove(id) } else { collapsed.insert(id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        .foregroundStyle(glass.secondaryText)
                        .frame(width: 12)
                    Text("\(title) (\(count))")
                        .font(.system(size: 12, weight: .semibold))
                    Rectangle().fill(glass.hairline).frame(height: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(count)")
            .accessibilityHint(isCollapsed ? "Expand" : "Collapse")
            if !isCollapsed { content() }
        }
    }

    private func eject(_ volume: VolumeMonitor.Volume) {
        do {
            try volumes.eject(volume)
        } catch {
            model.show(error, title: "“\(volume.name)” couldn’t be ejected")
        }
    }
}

/// Shared look and behaviour of a tile on the page: hover and selection highlight,
/// double-click to open, and the context menu.
private struct TileChrome<Content: View, Menu: View>: View {
    let name: String
    let url: URL
    let isSelected: Bool
    let select: () -> Void
    let open: () -> Void
    let model: WindowModel
    @ViewBuilder var content: () -> Content
    @ViewBuilder var menu: () -> Menu
    @State private var hovering = false
    @Environment(\.glass) private var glass

    var body: some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? glass.softSelectionFill : (hovering ? glass.controlHover : .clear))
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(count: 2, perform: open)
            .onTapGesture(count: 1, perform: select)
            .contextMenu {
                Button("Open", action: open)
                Button("Open in New Tab") { model.newTab(at: url) }
                Button("Reveal in Finder") { model.revealInFinder([url]) }
                Button("Copy Path") { model.services.clipboard.copyText(url.path) }
                menu()
            }
            .help(url.path)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(name)
            .accessibilityAction(.default, open)
    }
}

private struct FolderTile: View {
    let name: String
    let url: URL
    let isSelected: Bool
    let select: () -> Void
    let open: () -> Void
    let model: WindowModel

    var body: some View {
        TileChrome(name: name, url: url, isSelected: isSelected, select: select, open: open, model: model) {
            HStack(spacing: 10) {
                Image(nsImage: FileIconProvider.icon(forPath: url.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                Text(name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        } menu: {
            Button("Add to Favorites") { model.services.addFavorite(url) }
        }
    }
}

private struct DriveTile: View {
    let volume: VolumeMonitor.Volume
    let capacity: CapacityUsage?
    let isSelected: Bool
    let select: () -> Void
    let open: () -> Void
    let eject: () -> Void
    let model: WindowModel
    @Environment(\.glass) private var glass

    var body: some View {
        TileChrome(name: volume.name, url: volume.url, isSelected: isSelected, select: select, open: open, model: model) {
            HStack(spacing: 10) {
                Image(nsImage: FileIconProvider.icon(forPath: volume.url.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(volume.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let capacity {
                        CapacityBar(usage: capacity)
                        Text(capacity.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(glass.secondaryText)
                            .lineLimit(1)
                    }
                }
                if volume.isEjectable {
                    Button(action: eject) { Image(systemName: "eject.fill").font(.system(size: 10)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(glass.secondaryText)
                        .help("Eject \(volume.name)")
                        .accessibilityLabel("Eject \(volume.name)")
                }
            }
        } menu: {
            if volume.isEjectable {
                Divider()
                Button("Eject “\(volume.name)”", action: eject)
            }
        }
        .accessibilityValue(capacity?.summary ?? "")
    }
}

/// Used-space bar; turns red when the drive is nearly full.
private struct CapacityBar: View {
    let usage: CapacityUsage
    @Environment(\.glass) private var glass

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(glass.controlFill)
                Capsule()
                    .fill(usage.isLow ? Color.red : Color.accentColor)
                    .frame(width: max(proxy.size.height, proxy.size.width * usage.usedFraction))
            }
        }
        .frame(height: 8)
        .overlay { Capsule().strokeBorder(glass.hairline, lineWidth: 0.5) }
        .accessibilityHidden(true)
    }
}
