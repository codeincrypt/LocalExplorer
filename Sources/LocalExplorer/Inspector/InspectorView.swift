import AppKit
import AVFoundation
import ImageIO
import SwiftUI
import ExplorerCore

/// Preview and properties pane (Get Info).
struct InspectorView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: TabModel
    @ObservedObject var services: AppServices
    @Environment(\.glass) private var glass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let selected = tab.selectedItems
                if selected.count == 1, let item = selected.first {
                    // Gallery already shows the full preview; avoid a second player/document.
                    SingleItemInspector(item: item, model: model, services: services, showsPreview: tab.viewMode != .gallery)
                        .id(item.id + "\(item.modificationDate?.timeIntervalSince1970 ?? 0)")
                } else if selected.count > 1 {
                    MultipleItemsInspector(items: selected)
                } else {
                    FolderSummary(tab: tab)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.automatic)
        .accessibilityLabel("Preview and properties")
        .accessibilityIdentifier("previewPane")
    }
}

private struct SingleItemInspector: View {
    let item: FileItem
    let model: WindowModel
    let services: AppServices
    let showsPreview: Bool
    @State private var metadata: [(String, String)] = []
    @State private var folderSize: Int64?
    @State private var calculating = false
    @Environment(\.glass) private var glass

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsPreview {
                PreviewHost(item: item, style: .compact, services: services, open: { model.open(item) })
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(glass.controlFill.opacity(0.6)))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(glass.borderGradient, lineWidth: 0.75)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .topTrailing) {
                        Button { model.setViewMode(.gallery) } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(GlassIconButtonStyle(size: CGSize(width: 24, height: 22)))
                        .background(Circle().fill(.ultraThinMaterial))
                        .padding(6)
                        .help("Show in Gallery (⌘3)")
                        .accessibilityLabel("Show larger preview in Gallery")
                    }
                    .contextMenu {
                        Button("Quick Look") { model.perform(.quickPreview) }
                        Button("Show in Gallery") { model.setViewMode(.gallery) }
                        Button("Open") { model.open(item) }
                    }
            } else {
                Image(nsImage: FileIconProvider.icon(for: item))
                    .resizable()
                    .frame(width: 64, height: 64)
                    .frame(maxWidth: .infinity)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(3)
                        .textSelection(.enabled)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(glass.secondaryText)
                }
                Spacer()
                Button("Open") { model.open(item) }
                    .buttonStyle(GlassCapsuleButtonStyle())
            }

            InfoSection(rows: generalRows)
            if item.isNavigableDirectory {
                HStack {
                    Text("Folder size").foregroundStyle(glass.secondaryText)
                    Spacer()
                    if let folderSize {
                        Text(DisplayFormat.byteCount(folderSize)).monospacedDigit()
                    } else if calculating {
                        ProgressView().controlSize(.mini)
                    } else {
                        Button("Calculate") { calculateFolderSize() }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                    }
                }
                .font(.system(size: 11))
            }
            if !metadata.isEmpty { InfoSection(rows: metadata) }
            InfoSection(rows: permissionRows)
        }
        .task(id: item.id) { await loadMetadata() }
    }

    private var subtitle: String {
        var parts = [item.kindDescription]
        if let size = item.size { parts.append(DisplayFormat.byteCount(size)) }
        return parts.joined(separator: " · ")
    }

    private var generalRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let created = item.creationDate { rows.append(("Created", created.formatted(date: .abbreviated, time: .shortened))) }
        if let modified = item.modificationDate { rows.append(("Modified", modified.formatted(date: .abbreviated, time: .shortened))) }
        if let size = item.size { rows.append(("Size", "\(DisplayFormat.byteCount(size)) (\(size.formatted()) bytes)")) }
        rows.append(("Where", item.url.deletingLastPathComponent().path))
        if item.isSymbolicLink {
            let destination = (try? FileManager.default.destinationOfSymbolicLink(atPath: item.url.path)) ?? "—"
            rows.append(("Original", item.isBrokenSymbolicLink ? "\(destination) (missing)" : destination))
        }
        if let tags = try? item.url.resourceValues(forKeys: [.tagNamesKey]).tagNames, !tags.isEmpty {
            rows.append(("Tags", tags.joined(separator: ", ")))
        }
        return rows
    }

    private var permissionRows: [(String, String)] {
        guard let p = FileSystemFacts.permissions(of: item.url) else { return [] }
        var rows = [("Permissions", "\(DisplayFormat.symbolicPermissions(p.mode, isDirectory: item.isDirectory, isSymlink: item.isSymbolicLink)) (\(DisplayFormat.octalPermissions(p.mode)))")]
        if let owner = p.owner { rows.append(("Owner", p.group.map { "\(owner) : \($0)" } ?? owner)) }
        rows.append(("You can", [item.isReadable ? "read" : nil, item.isWritable ? "write" : nil].compactMap { $0 }.joined(separator: " & ").ifEmpty("not access")))
        return rows
    }

    private func calculateFolderSize() {
        calculating = true
        let url = item.url
        Task {
            let size = await Task.detached(priority: .utility) { try? FileSystemFacts.totalSize(of: url) }.value
            folderSize = size
            calculating = false
        }
    }

    /// Image and media details, read without decoding full images.
    private func loadMetadata() async {
        let url = item.url
        switch item.category {
        case .image:
            metadata = await Task.detached(priority: .utility) { ImageMetadata.rows(for: url) }.value
        case .video, .audio:
            metadata = await MediaMetadata.rows(for: url)
        default:
            metadata = []
        }
    }
}

private struct MultipleItemsInspector: View {
    let items: [FileItem]
    @Environment(\.glass) private var glass

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { index, item in
                    Image(nsImage: FileIconProvider.icon(for: item))
                        .resizable()
                        .frame(width: 96, height: 96)
                        .rotationEffect(.degrees(Double(index - 1) * 8))
                        .offset(x: CGFloat(index - 1) * 14)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            Text("\(items.count) items selected")
                .font(.system(size: 15, weight: .semibold))
            let files = items.filter { !$0.isNavigableDirectory }
            let folders = items.count - files.count
            InfoSection(rows: [
                ("Files", "\(files.count)"),
                ("Folders", "\(folders)"),
                ("Total size", DisplayFormat.byteCount(files.compactMap(\.size).reduce(0, +)) + (folders > 0 ? " + folders" : "")),
            ])
        }
    }
}

private struct FolderSummary: View {
    @ObservedObject var tab: TabModel
    @Environment(\.glass) private var glass

    var body: some View {
        if tab.isThisMac {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(glass.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                Text(ThisMac.title).font(.system(size: 15, weight: .semibold))
                Text("Open a folder or drive to see its contents.")
                    .font(.system(size: 11))
                    .foregroundStyle(glass.secondaryText)
            }
        } else {
            folderBody
        }
    }

    private var folderBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(nsImage: FileIconProvider.icon(forPath: tab.currentURL.path))
                .resizable()
                .frame(width: 96, height: 96)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            Text(tab.title).font(.system(size: 15, weight: .semibold))
            InfoSection(rows: [
                ("Items", "\(tab.items.count)"),
                ("Location", tab.currentURL.path),
                ("Available", tab.availableCapacity.map(DisplayFormat.byteCount) ?? "—"),
                ("Access", tab.isFolderWritable ? "Read & write" : "Read only"),
            ])
            Text("Select an item to see its preview and properties.")
                .font(.system(size: 11))
                .foregroundStyle(glass.secondaryText)
        }
    }
}

struct InfoSection: View {
    let rows: [(String, String)]
    @Environment(\.glass) private var glass

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.0)
                        .foregroundStyle(glass.secondaryText)
                        .frame(width: 92, alignment: .leading)
                    Text(row.1)
                        .fontWeight(.medium)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
                .font(.system(size: 11))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { Rectangle().fill(glass.hairline).frame(height: 1) }
    }
}

enum ImageMetadata {
    /// Dimensions, colour model and EXIF camera details via ImageIO (header only).
    static func rows(for url: URL) -> [(String, String)] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return [("Preview", "Not available for this file")]
        }
        var rows: [(String, String)] = []
        if let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            rows.append(("Dimensions", "\(w) × \(h)"))
        }
        if let dpi = props[kCGImagePropertyDPIWidth] as? Double { rows.append(("DPI", "\(Int(dpi))")) }
        if let model = props[kCGImagePropertyColorModel] as? String {
            let profile = props[kCGImagePropertyProfileName] as? String
            rows.append(("Colour", profile.map { "\(model), \($0)" } ?? model))
        }
        if let alpha = props[kCGImagePropertyHasAlpha] as? Bool, alpha { rows.append(("Transparency", "Yes")) }
        let frames = CGImageSourceGetCount(source)
        if frames > 1 { rows.append(("Frames", "\(frames)")) }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            if let make = tiff[kCGImagePropertyTIFFMake] as? String { rows.append(("Camera make", make)) }
            if let model = tiff[kCGImagePropertyTIFFModel] as? String { rows.append(("Camera model", model)) }
        }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let lens = exif[kCGImagePropertyExifLensModel] as? String { rows.append(("Lens", lens)) }
            if let focal = exif[kCGImagePropertyExifFocalLength] as? Double {
                let eq = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int
                rows.append(("Focal length", eq.map { "\(formatNumber(focal)) mm (\($0) mm eq.)" } ?? "\(formatNumber(focal)) mm"))
            }
            if let f = exif[kCGImagePropertyExifFNumber] as? Double { rows.append(("Aperture", "ƒ/\(formatNumber(f))")) }
            if let t = exif[kCGImagePropertyExifExposureTime] as? Double {
                rows.append(("Exposure", t >= 1 ? "\(formatNumber(t)) s" : "1/\(Int((1 / t).rounded())) s"))
            }
            if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first { rows.append(("ISO", "\(iso)")) }
            if let date = exif[kCGImagePropertyExifDateTimeOriginal] as? String { rows.append(("Taken", date)) }
        }
        return rows
    }

    private static func formatNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

enum MediaMetadata {
    static func rows(for url: URL) async -> [(String, String)] {
        let asset = AVURLAsset(url: url)
        var rows: [(String, String)] = []
        do {
            let duration = try await asset.load(.duration)
            if duration.seconds.isFinite { rows.append(("Duration", DisplayFormat.duration(duration.seconds))) }
            if let video = try await asset.loadTracks(withMediaType: .video).first {
                let size = try await video.load(.naturalSize)
                rows.append(("Dimensions", "\(Int(abs(size.width))) × \(Int(abs(size.height)))"))
                let rate = try await video.load(.nominalFrameRate)
                if rate > 0 { rows.append(("Frame rate", String(format: "%.2f fps", rate))) }
            }
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if !audioTracks.isEmpty { rows.append(("Audio tracks", "\(audioTracks.count)")) }
            let playable = try await asset.load(.isPlayable)
            if !playable { rows.append(("Playback", "Not supported by macOS (codec unavailable)")) }
        } catch {
            rows.append(("Media", "Couldn’t read this file: \(error.localizedDescription)"))
        }
        return rows
    }
}

private extension String {
    func ifEmpty(_ replacement: String) -> String { isEmpty ? replacement : self }
}
