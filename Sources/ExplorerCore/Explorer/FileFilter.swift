import Foundation

/// Hidden-file visibility plus incremental current-folder search.
///
/// Query syntax (all terms must match, case and diacritic insensitive):
///   report          name contains "report"
///   *.jpg  img_??   shell-style wildcards against the whole name
///   kind:image      category (folder, image, video, audio, pdf, text, code, archive, …)
///   ext:pdf         extension
public struct FileFilter: Equatable, Sendable {
    public var showHidden: Bool
    public var query: String

    public init(showHidden: Bool = false, query: String = "") {
        self.showHidden = showHidden
        self.query = query
    }

    public var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    public func apply(to items: [FileItem]) -> [FileItem] {
        let terms = Self.parse(query)
        return items.filter { item in
            if !showHidden && item.isHidden { return false }
            return terms.allSatisfy { $0.matches(item) }
        }
    }

    public enum Term: Equatable, Sendable {
        case contains(String)
        case wildcard(String)
        case kind(String)
        case ext(String)

        func matches(_ item: FileItem) -> Bool {
            switch self {
            case .contains(let text):
                return item.name.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            case .wildcard(let pattern):
                return WildcardMatcher.matches(item.name, pattern: pattern)
            case .kind(let kind):
                let k = kind.lowercased()
                if k == "folder" || k == "dir" || k == "directory" { return item.isNavigableDirectory }
                if k == "file" { return !item.isNavigableDirectory }
                return item.category.rawValue.lowercased() == k
                    || item.category.displayName.lowercased().hasPrefix(k)
            case .ext(let ext):
                return item.pathExtension.lowercased() == ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            }
        }
    }

    public static func parse(_ query: String) -> [Term] {
        query.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { raw in
            let token = String(raw)
            let lower = token.lowercased()
            if lower.hasPrefix("kind:"), token.count > 5 { return .kind(String(token.dropFirst(5))) }
            if lower.hasPrefix("ext:"), token.count > 4 { return .ext(String(token.dropFirst(4))) }
            if token.contains("*") || token.contains("?") { return .wildcard(token) }
            return token.isEmpty ? nil : .contains(token)
        }
    }
}

/// Case-insensitive `*` / `?` matching against an entire string.
public enum WildcardMatcher {
    public static func matches(_ text: String, pattern: String) -> Bool {
        let t = Array(text.lowercased())
        let p = Array(pattern.lowercased())
        var ti = 0, pi = 0
        var starIndex = -1, matchIndex = 0
        while ti < t.count {
            if pi < p.count && (p[pi] == "?" || p[pi] == t[ti]) {
                ti += 1; pi += 1
            } else if pi < p.count && p[pi] == "*" {
                starIndex = pi; matchIndex = ti; pi += 1
            } else if starIndex != -1 {
                pi = starIndex + 1; matchIndex += 1; ti = matchIndex
            } else {
                return false
            }
        }
        while pi < p.count && p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}
