import Foundation

/// Splits a filename into stem and extension, keeping compound archive extensions
/// together ("backup.tar.gz" → "backup" + "tar.gz"). Plain folders have no extension.
public struct FilenameParts: Equatable, Sendable {
    public let stem: String
    public let ext: String

    static let compoundExtensions = ["tar.gz", "tar.bz2", "tar.xz", "tar.zst", "tar.lz"]

    public init(stem: String, ext: String) {
        self.stem = stem
        self.ext = ext
    }

    public init(name: String, isDirectory: Bool = false) {
        if isDirectory || name.hasPrefix(".") && !name.dropFirst().contains(".") {
            stem = name
            ext = ""
            return
        }
        let lower = name.lowercased()
        for compound in Self.compoundExtensions where lower.hasSuffix("." + compound) && lower.count > compound.count + 1 {
            stem = String(name.dropLast(compound.count + 1))
            ext = String(name.suffix(compound.count))
            return
        }
        let ns = name as NSString
        let e = ns.pathExtension
        if e.isEmpty || e.contains(" ") {
            stem = name
            ext = ""
        } else {
            stem = ns.deletingPathExtension
            ext = e
        }
    }

    public func joined(stem newStem: String) -> String {
        ext.isEmpty ? newStem : "\(newStem).\(ext)"
    }
}

public enum FilenameIssue: Equatable, Sendable {
    case empty
    case tooLong
    case containsSlash
    case containsColon
    case containsNull
    case reserved
    case alreadyExists

    public var message: String {
        switch self {
        case .empty: return "The name can’t be empty."
        case .tooLong: return "The name is too long (maximum 255 bytes)."
        case .containsSlash: return "The name can’t contain “/”."
        case .containsColon: return "The name can’t contain “:”."
        case .containsNull: return "The name contains an invalid character."
        case .reserved: return "“.” and “..” are reserved names."
        case .alreadyExists: return "An item with this name already exists."
        }
    }
}

public enum FilenameWarning: Equatable, Sendable {
    case becomesHidden
    case extensionChanged(from: String, to: String)
    case surroundingWhitespace

    public var message: String {
        switch self {
        case .becomesHidden: return "Names beginning with “.” are hidden."
        case .extensionChanged(let from, let to):
            let a = from.isEmpty ? "no extension" : "“.\(from)”"
            let b = to.isEmpty ? "no extension" : "“.\(to)”"
            return "The extension changes from \(a) to \(b). The item may open in a different app."
        case .surroundingWhitespace: return "The name starts or ends with a space."
        }
    }
}

public struct FilenameValidation: Equatable, Sendable {
    public var issues: [FilenameIssue]
    public var warnings: [FilenameWarning]
    public var isValid: Bool { issues.isEmpty }
}

public enum FilenameValidator {
    public static let maxBytes = 255

    public static func validate(_ name: String) -> [FilenameIssue] {
        var issues: [FilenameIssue] = []
        if name.isEmpty { return [.empty] }
        if name == "." || name == ".." { issues.append(.reserved) }
        if name.contains("/") { issues.append(.containsSlash) }
        if name.contains(":") { issues.append(.containsColon) }
        if name.contains("\u{0}") { issues.append(.containsNull) }
        if name.utf8.count > maxBytes { issues.append(.tooLong) }
        return issues
    }

    /// Validation for renaming `original` to `proposed`. `exists` reports whether a
    /// sibling with that name is present (a case-only change of the same item is fine).
    public static func validateRename(
        original: String,
        proposed: String,
        isDirectory: Bool,
        exists: (String) -> Bool
    ) -> FilenameValidation {
        var issues = validate(proposed)
        var warnings: [FilenameWarning] = []
        if issues.isEmpty, proposed != original,
           proposed.lowercased() != original.lowercased() || !exists(original),
           exists(proposed) {
            issues.append(.alreadyExists)
        }
        if proposed.hasPrefix(".") && !original.hasPrefix(".") { warnings.append(.becomesHidden) }
        if proposed != proposed.trimmingCharacters(in: .whitespaces) { warnings.append(.surroundingWhitespace) }
        if !isDirectory {
            let before = FilenameParts(name: original).ext
            let after = FilenameParts(name: proposed).ext
            if before.lowercased() != after.lowercased() {
                warnings.append(.extensionChanged(from: before, to: after))
            }
        }
        return FilenameValidation(issues: issues, warnings: warnings)
    }
}

/// Generates non-colliding names the way Finder does.
public enum UniqueNameGenerator {
    /// "photo.jpg" → "photo 2.jpg" → "photo 3.jpg" (Keep Both).
    public static func keepBothName(for name: String, isDirectory: Bool = false, exists: (String) -> Bool) -> String {
        let parts = FilenameParts(name: name, isDirectory: isDirectory)
        var base = parts.stem
        var counter = 2
        // "photo 2" keeps counting from 3 instead of producing "photo 2 2".
        if let space = base.lastIndex(of: " "),
           let n = Int(base[base.index(after: space)...]), n >= 2, n < 100_000 {
            base = String(base[..<space])
            counter = n + 1
        }
        while true {
            let candidate = parts.joined(stem: "\(base) \(counter)")
            if !exists(candidate) { return candidate }
            counter += 1
        }
    }

    /// "report.pdf" → "report copy.pdf" → "report copy 2.pdf" (Duplicate).
    public static func duplicateName(for name: String, isDirectory: Bool = false, exists: (String) -> Bool) -> String {
        let parts = FilenameParts(name: name, isDirectory: isDirectory)
        var base = parts.stem
        if base.hasSuffix(" copy") { base = String(base.dropLast(5)) }
        else if let range = base.range(of: " copy ", options: .backwards),
                Int(base[range.upperBound...]) != nil {
            base = String(base[..<range.lowerBound])
        }
        let first = parts.joined(stem: "\(base) copy")
        if !exists(first) { return first }
        var counter = 2
        while true {
            let candidate = parts.joined(stem: "\(base) copy \(counter)")
            if !exists(candidate) { return candidate }
            counter += 1
        }
    }

    /// "untitled folder", "untitled folder 2", …
    public static func newFolderName(base: String = "untitled folder", exists: (String) -> Bool) -> String {
        if !exists(base) { return base }
        var counter = 2
        while exists("\(base) \(counter)") { counter += 1 }
        return "\(base) \(counter)"
    }
}
