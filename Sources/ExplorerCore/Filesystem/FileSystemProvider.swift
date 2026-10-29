import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Errors surfaced when a directory cannot be listed. Each case maps to an actionable
/// state in the UI rather than a crash.
public enum DirectoryLoadError: Error, Equatable, Sendable {
    case permissionDenied(path: String)
    case notFound(path: String)
    case notADirectory(path: String)
    case volumeUnavailable(path: String)
    case other(path: String, message: String)

    public var path: String {
        switch self {
        case .permissionDenied(let p), .notFound(let p), .notADirectory(let p), .volumeUnavailable(let p):
            return p
        case .other(let p, _):
            return p
        }
    }

    public var title: String {
        switch self {
        case .permissionDenied: return "You don’t have permission to view this folder"
        case .notFound: return "This folder no longer exists"
        case .notADirectory: return "This location is not a folder"
        case .volumeUnavailable: return "The volume is not available"
        case .other: return "The folder couldn’t be opened"
        }
    }

    public var recoverySuggestion: String {
        switch self {
        case .permissionDenied:
            return "Grant access to this folder, or allow Local Explorer in System Settings › Privacy & Security › Full Disk Access. Some locations are protected by macOS and cannot be opened."
        case .notFound:
            return "It may have been moved, renamed or deleted. Go to the enclosing folder or refresh."
        case .notADirectory:
            return "Open the item instead of browsing into it."
        case .volumeUnavailable:
            return "Reconnect the drive or network share, then refresh."
        case .other(_, let message):
            return message
        }
    }

    /// Classifies a Foundation/POSIX error raised while reading `path`.
    public static func classify(_ error: Error, path: String) -> DirectoryLoadError {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return .permissionDenied(path: path)
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
                return .notFound(path: path)
            default:
                break
            }
        }
        if let posix = posixCode(of: ns) {
            switch posix {
            case EACCES, EPERM: return .permissionDenied(path: path)
            case ENOENT: return .notFound(path: path)
            case ENOTDIR: return .notADirectory(path: path)
            case ENXIO, ENODEV, EIO, ESTALE: return .volumeUnavailable(path: path)
            default: break
            }
        }
        return .other(path: path, message: ns.localizedDescription)
    }

    static func posixCode(of error: NSError) -> Int32? {
        if error.domain == NSPOSIXErrorDomain { return Int32(error.code) }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return posixCode(of: underlying)
        }
        return nil
    }
}

/// Abstraction over directory enumeration so views and tests do not depend on the
/// real filesystem.
public protocol FileSystemProviding: Sendable {
    /// Lists the immediate children of `directory`, including hidden entries (the
    /// caller filters). Never recurses.
    func contents(of directory: URL) throws -> [FileItem]
    /// Reads metadata for a single item.
    func item(at url: URL) throws -> FileItem
}

public struct LocalFileSystem: FileSystemProviding {
    public init() {}

    static var resourceKeys: [URLResourceKey] {
        var keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey, .fileSizeKey,
            .contentModificationDateKey, .creationDateKey, .isReadableKey, .isWritableKey,
            .isRegularFileKey,
        ]
        #if os(macOS)
        keys += [.isPackageKey, .typeIdentifierKey, .localizedTypeDescriptionKey]
        #endif
        return keys
    }

    public func contents(of directory: URL) throws -> [FileItem] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let path = directory.standardizedFileURL.path
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            throw DirectoryLoadError.notFound(path: path)
        }
        guard isDir.boolValue else { throw DirectoryLoadError.notADirectory(path: path) }
        // When the folder itself is reached through a symbolic link, list the link's
        // destination but keep presenting children under the path the user navigated.
        let isLink = (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        let listingURL = isLink ? directory.resolvingSymlinksInPath() : directory
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(
                at: listingURL,
                includingPropertiesForKeys: Self.resourceKeys,
                options: []
            )
        } catch {
            throw DirectoryLoadError.classify(error, path: path)
        }
        var result: [FileItem] = []
        result.reserveCapacity(urls.count)
        for url in urls {
            let presented = isLink ? directory.appendingPathComponent(url.lastPathComponent) : url
            // An entry can vanish between listing and stat; skip it rather than fail.
            if let item = try? makeItem(presented) { result.append(item) }
        }
        return result
    }

    public func item(at url: URL) throws -> FileItem {
        do {
            return try makeItem(url)
        } catch {
            throw DirectoryLoadError.classify(error, path: url.path)
        }
    }

    func makeItem(_ url: URL) throws -> FileItem {
        let values = try url.resourceValues(forKeys: Set(Self.resourceKeys))
        let isSymlink = values.isSymbolicLink ?? false
        var isDirectory = values.isDirectory ?? false
        var broken = false
        var isPackage = false
        var size = values.fileSize.map(Int64.init)
        var modified = values.contentModificationDate
        var typeIdentifier: String?
        var kind: String?
        #if os(macOS)
        isPackage = values.isPackage ?? false
        typeIdentifier = values.typeIdentifier
        kind = values.localizedTypeDescription
        #endif

        if isSymlink {
            // Describe the link by its destination without modifying anything.
            // `fileExists` follows the link; a dangling link resolves to itself, so the
            // existence check is what detects it.
            let resolved = url.resolvingSymlinksInPath()
            if FileManager.default.fileExists(atPath: url.path),
               let target = try? resolved.resourceValues(forKeys: Set(Self.resourceKeys)) {
                isDirectory = target.isDirectory ?? false
                if isDirectory { size = nil }
                modified = target.contentModificationDate ?? modified
                #if os(macOS)
                isPackage = target.isPackage ?? false
                typeIdentifier = target.typeIdentifier ?? typeIdentifier
                #endif
                kind = "Alias (\(kind ?? (isDirectory ? "Folder" : "File")))"
            } else {
                broken = true
                kind = "Broken alias"
            }
        }
        #if !os(macOS)
        if isDirectory && FileTypeClassifier.looksLikePackage(name: url.lastPathComponent) {
            isPackage = true
        }
        #endif

        return FileItem(
            url: url,
            isDirectory: isDirectory,
            isPackage: isPackage,
            isSymbolicLink: isSymlink,
            isBrokenSymbolicLink: broken,
            isHidden: (values.isHidden ?? false) || url.lastPathComponent.hasPrefix("."),
            size: size,
            modificationDate: modified,
            creationDate: values.creationDate,
            typeIdentifier: typeIdentifier,
            kindDescription: kind,
            isReadable: values.isReadable ?? true,
            isWritable: values.isWritable ?? true
        )
    }
}

/// Small filesystem facts used by the UI and the operation engine.
public enum FileSystemFacts {
    /// Device identifier of the volume containing `url` (lstat, so links are not
    /// followed). Used to choose between rename and copy+delete for moves.
    public static func deviceID(of url: URL) -> UInt64? {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { return -1 }
            return lstat(pointer, &info)
        }
        guard result == 0 else { return nil }
        return UInt64(info.st_dev)
    }

    public static func isSameVolume(_ a: URL, _ b: URL) -> Bool {
        guard let da = deviceID(of: a), let db = deviceID(of: b) else { return false }
        return da == db
    }

    /// POSIX permission bits and owner names.
    public static func permissions(of url: URL) -> (mode: UInt16, owner: String?, group: String?)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        return (mode, attributes[.ownerAccountName] as? String, attributes[.groupOwnerAccountName] as? String)
    }

    /// Available capacity of the volume containing `url`, when the platform reports it.
    public static func availableCapacity(at url: URL) -> Int64? {
        #if os(macOS)
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        #endif
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let capacity = values.volumeAvailableCapacity {
            return Int64(capacity)
        }
        return nil
    }

    /// Total logical size of a file or directory tree. Symbolic links are counted as
    /// links (not followed). Checks for task cancellation between entries.
    public static func totalSize(of url: URL) throws -> Int64 {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        let values = try url.resourceValues(forKeys: Set(keys))
        if values.isSymbolicLink == true || values.isDirectory != true {
            return Int64(values.fileSize ?? 0)
        }
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return 0 }
        var counter = 0
        while let child = enumerator.nextObject() as? URL {
            counter += 1
            if counter % 256 == 0, Task.isCancelled { throw CancellationError() }
            if let v = try? child.resourceValues(forKeys: Set(keys)), v.isDirectory != true || v.isSymbolicLink == true {
                total += Int64(v.fileSize ?? 0)
            }
        }
        return total
    }
}
