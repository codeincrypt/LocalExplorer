import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Classifies files into `FileCategory`. On Apple platforms the Uniform Type Identifier
/// (content type) wins; the extension table is the cross-platform fallback.
public enum FileTypeClassifier {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp", "svg",
        "ico", "icns", "psd", "raw", "cr2", "cr3", "nef", "arw", "dng", "orf", "raf", "avif", "jxl",
    ]
    static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "avi", "mkv", "webm", "mpg", "mpeg", "3gp", "wmv", "flv", "mts", "m2ts",
    ]
    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aif", "aiff", "aifc", "caf", "flac", "ogg", "opus", "wma", "alac",
    ]
    static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "log", "csv", "tsv", "rtf", "ini", "cfg", "conf", "yaml", "yml",
        "toml", "json", "xml", "plist", "env", "gitignore",
    ]
    static let codeExtensions: Set<String> = [
        "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "cs", "java", "kt", "kts", "go", "rs",
        "py", "rb", "php", "js", "mjs", "cjs", "ts", "tsx", "jsx", "html", "htm", "css", "scss",
        "sass", "less", "sh", "bash", "zsh", "fish", "sql", "lua", "pl", "r", "dart", "scala",
        "vue", "svelte", "gradle", "make", "cmake", "dockerfile",
    ]
    static let archiveExtensions: Set<String> = [
        "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst", "lz", "lzma", "cpio", "xip",
    ]
    static let documentExtensions: Set<String> = ["doc", "docx", "pages", "odt", "epub"]
    static let spreadsheetExtensions: Set<String> = ["xls", "xlsx", "numbers", "ods"]
    static let presentationExtensions: Set<String> = ["ppt", "pptx", "key", "odp"]
    static let diskImageExtensions: Set<String> = ["dmg", "iso", "img", "sparseimage", "sparsebundle"]
    static let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "woff", "woff2", "dfont"]
    static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "xcodeproj", "xcworkspace", "playground",
        "photoslibrary", "rtfd", "pages", "numbers", "key", "sparsebundle", "pkg",
    ]

    public static func category(
        forName name: String,
        isDirectory: Bool,
        isPackage: Bool,
        typeIdentifier: String? = nil
    ) -> FileCategory {
        let ext = (name as NSString).pathExtension.lowercased()
        if isDirectory {
            if ext == "app" { return .application }
            if isPackage { return extensionCategory(ext) ?? .package }
            return .folder
        }
        #if canImport(UniformTypeIdentifiers)
        if let identifier = typeIdentifier, let type = UTType(identifier) {
            if let category = category(for: type) { return category }
        }
        #endif
        return extensionCategory(ext) ?? .other
    }

    static func extensionCategory(_ ext: String) -> FileCategory? {
        if ext.isEmpty { return nil }
        if ext == "pdf" { return .pdf }
        if ext == "app" { return .application }
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if codeExtensions.contains(ext) { return .code }
        if textExtensions.contains(ext) { return .text }
        if archiveExtensions.contains(ext) { return .archive }
        if documentExtensions.contains(ext) { return .document }
        if spreadsheetExtensions.contains(ext) { return .spreadsheet }
        if presentationExtensions.contains(ext) { return .presentation }
        if diskImageExtensions.contains(ext) { return .diskImage }
        if fontExtensions.contains(ext) { return .font }
        return nil
    }

    #if canImport(UniformTypeIdentifiers)
    static func category(for type: UTType) -> FileCategory? {
        if type.conforms(to: .application) || type.conforms(to: .applicationBundle) { return .application }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) || type.conforms(to: .html) { return .code }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .diskImage) { return .diskImage }
        if type.conforms(to: .font) { return .font }
        if type.conforms(to: .spreadsheet) { return .spreadsheet }
        if type.conforms(to: .presentation) { return .presentation }
        if type.conforms(to: .text) || type.conforms(to: .json) || type.conforms(to: .xml)
            || type.conforms(to: .propertyList) || type.conforms(to: .commaSeparatedText) {
            return .text
        }
        // Dynamic types (unknown extensions) carry no information; fall back.
        if type.isDynamic { return nil }
        return nil
    }
    #endif

    /// Kind text used when the platform does not supply a localized description.
    public static func fallbackKindDescription(forName name: String, category: FileCategory) -> String {
        let ext = (name as NSString).pathExtension
        switch category {
        case .folder, .application:
            return category.displayName
        default:
            if ext.isEmpty { return category == .other ? "Document" : category.displayName }
            if category == .other { return "\(ext.uppercased()) file" }
            return "\(ext.uppercased()) \(category.displayName.lowercased())"
        }
    }

    /// Whether a directory with this name should be treated as an opaque package on
    /// platforms that do not report `isPackage`.
    public static func looksLikePackage(name: String) -> Bool {
        packageExtensions.contains((name as NSString).pathExtension.lowercased())
    }
}
