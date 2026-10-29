import Foundation

/// A snapshot of one directory entry. Values are captured at enumeration time; the
/// filesystem remains the source of truth and entries are re-read on refresh.
public struct FileItem: Identifiable, Hashable, Sendable {
    /// Stable identity within a listing: the standardized absolute path.
    public let id: String
    public let url: URL
    public let name: String
    /// True for directories, and for symbolic links that resolve to a directory.
    public let isDirectory: Bool
    /// Bundles such as `.app` that macOS presents as a single file.
    public let isPackage: Bool
    public let isSymbolicLink: Bool
    /// A symbolic link whose destination does not exist.
    public let isBrokenSymbolicLink: Bool
    /// Hidden by the dot prefix or by the filesystem hidden flag.
    public let isHidden: Bool
    /// Logical size in bytes. `nil` for directories (computed on demand).
    public let size: Int64?
    public let modificationDate: Date?
    public let creationDate: Date?
    /// Uniform Type Identifier when the platform provides one.
    public let typeIdentifier: String?
    /// Human readable kind ("PNG image", "Folder").
    public let kindDescription: String
    public let category: FileCategory
    public let isReadable: Bool
    public let isWritable: Bool

    public init(
        url: URL,
        name: String? = nil,
        isDirectory: Bool,
        isPackage: Bool = false,
        isSymbolicLink: Bool = false,
        isBrokenSymbolicLink: Bool = false,
        isHidden: Bool? = nil,
        size: Int64? = nil,
        modificationDate: Date? = nil,
        creationDate: Date? = nil,
        typeIdentifier: String? = nil,
        kindDescription: String? = nil,
        category: FileCategory? = nil,
        isReadable: Bool = true,
        isWritable: Bool = true
    ) {
        let standardized = url.standardizedFileURL
        self.url = standardized
        self.id = standardized.path
        let resolvedName = name ?? standardized.lastPathComponent
        self.name = resolvedName
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isSymbolicLink = isSymbolicLink
        self.isBrokenSymbolicLink = isBrokenSymbolicLink
        self.isHidden = isHidden ?? resolvedName.hasPrefix(".")
        self.size = isDirectory && !isPackage ? nil : size
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.typeIdentifier = typeIdentifier
        let resolvedCategory = category ?? FileTypeClassifier.category(
            forName: resolvedName,
            isDirectory: isDirectory,
            isPackage: isPackage,
            typeIdentifier: typeIdentifier
        )
        self.category = resolvedCategory
        self.kindDescription = kindDescription ?? FileTypeClassifier.fallbackKindDescription(
            forName: resolvedName,
            category: resolvedCategory
        )
        self.isReadable = isReadable
        self.isWritable = isWritable
    }

    public var pathExtension: String { url.pathExtension }

    /// Directories that the browser navigates into (packages open as files).
    public var isNavigableDirectory: Bool { isDirectory && !isPackage && !isBrokenSymbolicLink }

    /// Name without extension, used to pre-select text when renaming.
    public var nameStem: String {
        FilenameParts(name: name, isDirectory: isDirectory && !isPackage).stem
    }

    // Non-optional sort values (Comparable) for table columns.
    public var sortModificationDate: Date { modificationDate ?? .distantPast }
    public var sortCreationDate: Date { creationDate ?? .distantPast }
    public var sortSize: Int64 { size ?? -1 }
}

/// Broad buckets used for icons, filtering ("kind:image") and preview selection.
public enum FileCategory: String, Codable, CaseIterable, Sendable {
    case folder, package, application, image, video, audio, pdf, text, code
    case archive, document, spreadsheet, presentation, diskImage, font, other

    public var displayName: String {
        switch self {
        case .folder: return "Folder"
        case .package: return "Package"
        case .application: return "Application"
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .pdf: return "PDF document"
        case .text: return "Text"
        case .code: return "Source code"
        case .archive: return "Archive"
        case .document: return "Document"
        case .spreadsheet: return "Spreadsheet"
        case .presentation: return "Presentation"
        case .diskImage: return "Disk image"
        case .font: return "Font"
        case .other: return "Document"
        }
    }
}
