import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import ExplorerCore

/// Asynchronous, cancellable thumbnails via QuickLookThumbnailing with a bounded
/// in-memory cache. Keys include modification date and size, so edited files get new
/// thumbnails automatically.
@MainActor
final class ThumbnailService {
    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 4000
        setLimit(megabytes: 256)
    }

    func setLimit(megabytes: Int) {
        cache.totalCostLimit = max(16, megabytes) * 1024 * 1024
    }

    func clear() { cache.removeAllObjects() }

    /// Categories for which a content thumbnail is worth generating. Everything else
    /// shows its file icon, which is cheaper and what Finder shows anyway.
    static func wantsThumbnail(_ item: FileItem) -> Bool {
        switch item.category {
        case .image, .video, .pdf, .document, .presentation, .spreadsheet, .text, .code, .font, .audio:
            return true
        default:
            return false
        }
    }

    func cachedThumbnail(for item: FileItem, pointSize: CGFloat, scale: CGFloat) -> NSImage? {
        cache.object(forKey: key(item, pointSize, scale))
    }

    func thumbnail(for item: FileItem, pointSize: CGFloat, scale: CGFloat) async -> NSImage? {
        guard Self.wantsThumbnail(item), !item.isNavigableDirectory else { return nil }
        let cacheKey = key(item, pointSize, scale)
        if let hit = cache.object(forKey: cacheKey) { return hit }

        let pixels = CGFloat(ThumbnailCacheKey.bucket(forPixels: Double(pointSize * scale)))
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: pixels / scale, height: pixels / scale),
            scale: scale,
            representationTypes: [.lowQualityThumbnail, .thumbnail]
        )
        let generator = QLThumbnailGenerator.shared
        do {
            let representation = try await withTaskCancellationHandler {
                try await generator.generateBestRepresentation(for: request)
            } onCancel: {
                generator.cancel(request)
            }
            if Task.isCancelled { return nil }
            let image = representation.nsImage
            cache.setObject(image, forKey: cacheKey, cost: Int(pixels * pixels * 4))
            return image
        } catch {
            return nil
        }
    }

    private func key(_ item: FileItem, _ pointSize: CGFloat, _ scale: CGFloat) -> NSString {
        let bucket = ThumbnailCacheKey.bucket(forPixels: Double(pointSize * scale))
        return ThumbnailCacheKey(item: item, pixelSize: bucket).stringValue as NSString
    }
}

/// Icons from the system, cached by content type (files) or path (folders, apps, and
/// packages, which can have custom icons).
@MainActor
enum FileIconProvider {
    private static var cache: [String: NSImage] = [:]

    static func icon(for item: FileItem) -> NSImage {
        let key: String
        let make: () -> NSImage
        if item.isDirectory || item.isPackage || item.category == .application || item.isSymbolicLink {
            key = "path:" + item.id
            make = { NSWorkspace.shared.icon(forFile: item.url.path) }
        } else if let identifier = item.typeIdentifier, let type = UTType(identifier) {
            key = "type:" + identifier
            make = { NSWorkspace.shared.icon(for: type) }
        } else {
            key = "ext:" + item.pathExtension.lowercased()
            make = { NSWorkspace.shared.icon(for: UTType(filenameExtension: item.pathExtension) ?? .data) }
        }
        if let cached = cache[key] { return cached }
        if cache.count > 3000 { cache.removeAll(keepingCapacity: true) }
        let image = make()
        cache[key] = image
        return image
    }

    static func icon(forPath path: String) -> NSImage {
        let key = "path:" + path
        if let cached = cache[key] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[key] = image
        return image
    }
}
