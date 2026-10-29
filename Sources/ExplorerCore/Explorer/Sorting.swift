import Foundation

public enum FileSortKey: String, Codable, CaseIterable, Sendable {
    case name, dateModified, dateCreated, size, kind

    public var title: String {
        switch self {
        case .name: return "Name"
        case .dateModified: return "Date Modified"
        case .dateCreated: return "Date Created"
        case .size: return "Size"
        case .kind: return "Type"
        }
    }
}

public struct FileSortDescriptor: Codable, Hashable, Sendable {
    public var key: FileSortKey
    public var ascending: Bool
    /// Keeps folders above files regardless of direction (Windows Explorer behaviour).
    public var directoriesFirst: Bool

    public init(key: FileSortKey = .name, ascending: Bool = true, directoriesFirst: Bool = true) {
        self.key = key
        self.ascending = ascending
        self.directoriesFirst = directoriesFirst
    }
}

public enum FileSorter {
    public static func sorted(_ items: [FileItem], by descriptor: FileSortDescriptor) -> [FileItem] {
        items.sorted { areInIncreasingOrder($0, $1, descriptor) }
    }

    public static func areInIncreasingOrder(_ a: FileItem, _ b: FileItem, _ d: FileSortDescriptor) -> Bool {
        if d.directoriesFirst {
            let aFolder = a.isNavigableDirectory
            let bFolder = b.isNavigableDirectory
            if aFolder != bFolder { return aFolder }
        }
        let primary = compare(a, b, key: d.key)
        if primary != .orderedSame {
            return d.ascending ? primary == .orderedAscending : primary == .orderedDescending
        }
        // Stable, direction-independent tie-breakers.
        let byName = compareNames(a.name, b.name)
        if byName != .orderedSame { return byName == .orderedAscending }
        return a.id < b.id
    }

    static func compare(_ a: FileItem, _ b: FileItem, key: FileSortKey) -> ComparisonResult {
        switch key {
        case .name:
            return compareNames(a.name, b.name)
        case .dateModified:
            return compareValues(a.sortModificationDate, b.sortModificationDate)
        case .dateCreated:
            return compareValues(a.sortCreationDate, b.sortCreationDate)
        case .size:
            return compareValues(a.sortSize, b.sortSize)
        case .kind:
            let r = a.kindDescription.localizedCaseInsensitiveCompare(b.kindDescription)
            if r != .orderedSame { return r }
            return compareValues(a.pathExtension.lowercased(), b.pathExtension.lowercased())
        }
    }

    /// Finder-style ordering: case-insensitive, numbers compared numerically
    /// ("file2" < "file10").
    public static func compareNames(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [.caseInsensitive, .numeric, .diacriticInsensitive, .widthInsensitive])
    }

    static func compareValues<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        if a < b { return .orderedAscending }
        if a > b { return .orderedDescending }
        return .orderedSame
    }
}
