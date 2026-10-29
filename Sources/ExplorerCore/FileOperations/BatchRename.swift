import Foundation

/// Rules offered by the batch-rename sheet (modelled on Finder's Rename Items).
public enum BatchRenameRule: Equatable, Sendable {
    case replaceText(find: String, replacement: String, caseSensitive: Bool)
    case addText(String, position: TextPosition)
    case format(baseName: String, startIndex: Int, digits: Int, position: TextPosition)
    case changeCase(CaseStyle)

    public enum TextPosition: String, CaseIterable, Sendable { case before, after }
    public enum CaseStyle: String, CaseIterable, Sendable { case lower, upper, title }
}

public enum BatchRenameIssue: Equatable, Sendable {
    case invalid(FilenameIssue)
    case duplicateInBatch
    case existsOnDisk

    public var message: String {
        switch self {
        case .invalid(let issue): return issue.message
        case .duplicateInBatch: return "Two items would get the same name."
        case .existsOnDisk: return "An item with this name already exists."
        }
    }
}

public struct BatchRenameEntry: Equatable, Sendable, Identifiable {
    public var id: String { source.path }
    public let source: URL
    public let newName: String
    public var issue: BatchRenameIssue?
    public var destination: URL { source.deletingLastPathComponent().appendingPathComponent(newName) }
    public var isChange: Bool { newName != source.lastPathComponent }
}

public enum BatchRenamePlanner {
    /// Computes new names (extensions are preserved) and flags every problem so the UI
    /// can show a preview before anything is touched.
    public static func plan(
        for sources: [URL],
        rule: BatchRenameRule,
        isDirectory: (URL) -> Bool = { _ in false },
        existsOnDisk: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> [BatchRenameEntry] {
        var entries: [BatchRenameEntry] = sources.enumerated().map { index, url in
            let parts = FilenameParts(name: url.lastPathComponent, isDirectory: isDirectory(url))
            let stem = apply(rule, to: parts.stem, index: index)
            return BatchRenameEntry(source: url, newName: parts.joined(stem: stem), issue: nil)
        }
        let sourcePaths = Set(sources.map { $0.standardizedFileURL.path.lowercased() })
        var counts: [String: Int] = [:]
        for e in entries { counts[e.destination.path.lowercased(), default: 0] += 1 }
        for i in entries.indices {
            let e = entries[i]
            if let issue = FilenameValidator.validate(e.newName).first {
                entries[i].issue = .invalid(issue)
            } else if counts[e.destination.path.lowercased(), default: 0] > 1 {
                entries[i].issue = .duplicateInBatch
            } else if e.isChange,
                      !sourcePaths.contains(e.destination.standardizedFileURL.path.lowercased()),
                      existsOnDisk(e.destination) {
                entries[i].issue = .existsOnDisk
            }
        }
        return entries
    }

    static func apply(_ rule: BatchRenameRule, to stem: String, index: Int) -> String {
        switch rule {
        case .replaceText(let find, let replacement, let caseSensitive):
            guard !find.isEmpty else { return stem }
            return stem.replacingOccurrences(of: find, with: replacement, options: caseSensitive ? [] : [.caseInsensitive])
        case .addText(let text, let position):
            return position == .before ? text + stem : stem + text
        case .format(let base, let start, let digits, let position):
            let number = String(start + index)
            let padded = String(repeating: "0", count: max(0, digits - number.count)) + number
            return position == .after ? "\(base)\(padded)" : "\(padded)\(base)"
        case .changeCase(let style):
            switch style {
            case .lower: return stem.lowercased()
            case .upper: return stem.uppercased()
            case .title: return stem.capitalized
            }
        }
    }
}
