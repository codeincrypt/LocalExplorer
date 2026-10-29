import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum FileOperationKind: String, Sendable {
    case copy, move, duplicate, rename, newFolder, trash, delete, batchRename, undo

    public var progressTitle: String {
        switch self {
        case .copy: return "Copying"
        case .move: return "Moving"
        case .duplicate: return "Duplicating"
        case .rename: return "Renaming"
        case .newFolder: return "Creating folder"
        case .trash: return "Moving to Trash"
        case .delete: return "Deleting"
        case .batchRename: return "Renaming"
        case .undo: return "Undoing"
        }
    }
}

public enum FileOperationError: Error, Equatable, Sendable {
    case permissionDenied(path: String)
    case notFound(path: String)
    case alreadyExists(path: String)
    case insufficientSpace(required: Int64, available: Int64)
    case destinationInsideSource(path: String)
    case replacingAncestor(path: String)
    case invalidName(FilenameIssue)
    case volumeUnavailable(path: String)
    case readOnlyVolume(path: String)
    case sourceNotRemoved(path: String)
    case trashUnavailable(path: String)
    case cannotUndo(reason: String)
    case other(path: String, message: String)

    public var message: String {
        switch self {
        case .permissionDenied(let p): return "You don’t have permission to access “\(Self.name(p))”."
        case .notFound(let p): return "“\(Self.name(p))” couldn’t be found. It may have been moved or deleted."
        case .alreadyExists(let p): return "An item named “\(Self.name(p))” already exists."
        case .insufficientSpace(let required, let available):
            return "There isn’t enough space. \(DisplayFormat.byteCount(required)) is needed but only \(DisplayFormat.byteCount(available)) is available."
        case .destinationInsideSource(let p): return "“\(Self.name(p))” can’t be copied or moved into itself."
        case .replacingAncestor(let p): return "“\(Self.name(p))” can’t be replaced because it contains the item being moved."
        case .invalidName(let issue): return issue.message
        case .volumeUnavailable(let p): return "The volume containing “\(Self.name(p))” is not available."
        case .readOnlyVolume(let p): return "“\(Self.name(p))” is on a read-only volume."
        case .sourceNotRemoved(let p): return "“\(Self.name(p))” was copied but the original couldn’t be removed."
        case .trashUnavailable(let p): return "“\(Self.name(p))” can’t be moved to the Trash on this volume."
        case .cannotUndo(let reason): return "The operation can’t be undone: \(reason)"
        case .other(let p, let m): return p.isEmpty ? m : "“\(Self.name(p))”: \(m)"
        }
    }

    static func name(_ path: String) -> String { (path as NSString).lastPathComponent }

    public static func classify(_ error: Error, path: String) -> FileOperationError {
        if let e = error as? FileOperationError { return e }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return .permissionDenied(path: path)
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError: return .notFound(path: path)
            case NSFileWriteFileExistsError: return .alreadyExists(path: path)
            case NSFileWriteOutOfSpaceError: return .insufficientSpace(required: 0, available: 0)
            case NSFileWriteVolumeReadOnlyError: return .readOnlyVolume(path: path)
            default: break
            }
        }
        if let posix = DirectoryLoadError.posixCode(of: ns) {
            switch posix {
            case EACCES, EPERM: return .permissionDenied(path: path)
            case ENOENT: return .notFound(path: path)
            case EEXIST, ENOTEMPTY: return .alreadyExists(path: path)
            case ENOSPC, EDQUOT: return .insufficientSpace(required: 0, available: 0)
            case EROFS: return .readOnlyVolume(path: path)
            case ENXIO, ENODEV, EIO, ESTALE: return .volumeUnavailable(path: path)
            default: break
            }
        }
        return .other(path: path, message: ns.localizedDescription)
    }
}

public enum ConflictAction: String, Sendable, CaseIterable {
    case replace, keepBoth, skip, cancel
}

public struct ConflictResolution: Sendable, Equatable {
    public var action: ConflictAction
    /// Apply the same action to the remaining conflicts in this batch.
    public var applyToRemaining: Bool
    public init(_ action: ConflictAction, applyToRemaining: Bool = false) {
        self.action = action
        self.applyToRemaining = applyToRemaining
    }
}

public struct FileConflict: Sendable, Equatable {
    public let operation: FileOperationKind
    public let source: URL
    public let existing: URL
    public let sourceIsDirectory: Bool
    public let existingIsDirectory: Bool
    /// Items left to process after this one (to offer "apply to all").
    public let remainingItems: Int
}

public typealias ConflictHandler = @Sendable (FileConflict) async -> ConflictResolution

public struct OperationProgress: Sendable, Equatable {
    public var kind: FileOperationKind
    public var completedItems: Int
    public var totalItems: Int
    public var completedBytes: Int64
    public var totalBytes: Int64
    public var currentName: String

    public var fraction: Double {
        if totalBytes > 0 { return min(1, Double(completedBytes) / Double(totalBytes)) }
        guard totalItems > 0 else { return 0 }
        return min(1, Double(completedItems) / Double(totalItems))
    }
}

public typealias ProgressHandler = @Sendable (OperationProgress) -> Void

public struct Transfer: Sendable, Equatable {
    public let source: URL
    public let destination: URL
    public init(source: URL, destination: URL) {
        self.source = source
        self.destination = destination
    }
}

/// A reversible operation with enough information to undo it safely.
public enum FileOperationRecord: Sendable, Equatable {
    /// Items that did not exist before (new folder, copies, duplicates).
    case created([URL])
    case renamed([Transfer])
    case moved([Transfer])
    /// `source` is the original location, `destination` the item's place in the Trash.
    case trashed([Transfer])

    public var undoTitle: String {
        switch self {
        case .created(let urls): return urls.count == 1 ? "Create “\(urls[0].lastPathComponent)”" : "Create \(urls.count) Items"
        case .renamed: return "Rename"
        case .moved(let t): return t.count == 1 ? "Move “\(t[0].source.lastPathComponent)”" : "Move \(t.count) Items"
        case .trashed(let t): return t.count == 1 ? "Move to Trash" : "Move \(t.count) Items to Trash"
        }
    }
}

public struct FileOperationReport: Sendable {
    public struct Failure: Sendable, Equatable {
        public let url: URL
        public let error: FileOperationError
    }

    public let kind: FileOperationKind
    public var completed: [Transfer] = []
    public var skipped: [URL] = []
    public var failures: [Failure] = []
    public var replacedItems: [URL] = []
    public var cancelled = false
    /// Present when every completed step can be reversed.
    public var record: FileOperationRecord?

    public init(kind: FileOperationKind) { self.kind = kind }

    public var succeeded: Bool { failures.isEmpty && !cancelled }
    public var destinations: [URL] { completed.map(\.destination) }

    /// One-line summary for alerts when something went wrong.
    public var failureSummary: String? {
        guard !failures.isEmpty else { return nil }
        if failures.count == 1 { return failures[0].error.message }
        let done = completed.count
        return "\(failures.count) items couldn’t be processed\(done > 0 ? " (\(done) succeeded)" : ""). First error: \(failures[0].error.message)"
    }
}

/// Moves items to the Trash. Injected so tests never touch the real Trash.
public protocol Trashing: Sendable {
    /// Returns the item's new location in the Trash when known.
    func trashItem(at url: URL) throws -> URL?
}

public struct SystemTrash: Trashing {
    public init() {}
    public func trashItem(at url: URL) throws -> URL? {
        #if os(macOS)
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
        #else
        throw FileOperationError.trashUnavailable(path: url.path)
        #endif
    }
}

/// A Trash implemented as a plain folder; used by tests and as a documented fallback.
public struct FolderTrash: Trashing {
    public let folder: URL
    public init(folder: URL) { self.folder = folder }
    public func trashItem(at url: URL) throws -> URL? {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = UniqueNameGenerator.keepBothName(for: url.lastPathComponent) {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        let candidate = folder.appendingPathComponent(url.lastPathComponent)
        let target = FileManager.default.fileExists(atPath: candidate.path) ? folder.appendingPathComponent(name) : candidate
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }
}
