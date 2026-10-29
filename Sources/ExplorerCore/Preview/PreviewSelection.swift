import Foundation

/// The kind of preview a file gets. Chosen from the file's leading bytes first and its
/// type/extension second, so a mislabelled file is not handed to the wrong renderer.
public enum PreviewKind: String, Sendable, Equatable, CaseIterable {
    /// Still or animated image rendered with ImageIO / NSImage.
    case image
    case video
    case audio
    /// PDFKit document.
    case pdf
    /// Plain text and source code, decoded safely with a size limit.
    case text
    /// Rich documents the system Quick Look generators render (Office, iWork, RTF,
    /// fonts, SVG). Used only for those types, never as a blanket default.
    case quickLook
    case folder
    /// Icon and properties with an "Open" action.
    case fallback
}

public enum PreviewSelector {
    /// Extensions whose rendering needs a Quick Look generator rather than a text view
    /// even though their bytes look like text.
    static let quickLookTextExtensions: Set<String> = ["rtf", "svg"]

    /// Picks the preview for `item`. `signature` is the result of
    /// `ContentSniffer.sniff(url:)`; `nil` means the header could not be read.
    public static func kind(for item: FileItem, signature: ContentSniffer.Signature?) -> PreviewKind {
        if item.isBrokenSymbolicLink { return .fallback }
        if item.isNavigableDirectory { return .folder }
        if item.isDirectory || item.category == .application || item.category == .package {
            // Bundles: rich documents (Pages, Keynote, RTFD) are Quick Look's job; apps and
            // other packages show their icon.
            switch item.category {
            case .document, .spreadsheet, .presentation: return .quickLook
            default: return .fallback
            }
        }
        let ext = item.pathExtension.lowercased()
        guard let signature else { return .fallback }

        switch signature {
        case .png, .jpeg, .gif, .tiff, .bmp, .webp, .heif:
            // TIFF-based camera RAW files are images too; HEIF brands include AVIF.
            return .image
        case .pdf:
            return .pdf
        case .mp4Family:
            // ISO base media covers both .mp4/.mov and .m4a/.m4b.
            return item.category == .audio ? .audio : .video
        case .wave, .aiff, .mp3, .flac, .ogg:
            return .audio
        case .zip, .gzip:
            // Office Open XML and OpenDocument files are zip containers.
            switch item.category {
            case .document, .spreadsheet, .presentation: return .quickLook
            default: return .fallback
            }
        case .utf8Text:
            if quickLookTextExtensions.contains(ext) { return .quickLook }
            return .text
        case .empty:
            return .text
        case .binary:
            switch item.category {
            case .image: return .image
            case .video: return .video
            case .audio: return .audio
            case .pdf: return .fallback  // claims to be PDF but has no PDF header
            case .document, .spreadsheet, .presentation, .font: return .quickLook
            case .text, .code:
                // A non-UTF-8 text file (UTF-16, Latin-1) is still worth decoding; the
                // text loader rejects real binaries.
                return .text
            default: return .fallback
            }
        }
    }
}

// MARK: - Text

public struct TextPreviewContent: Equatable, Sendable {
    public let text: String
    /// Human-readable encoding name ("UTF-8", "UTF-16 LE", "Western (Windows 1252)").
    public let encodingName: String
    /// True when only the first `limit` bytes were read.
    public let isTruncated: Bool
    public let totalBytes: Int64
    public let lineCount: Int
}

public enum TextPreviewResult: Equatable, Sendable {
    case text(TextPreviewContent)
    case binary
    case unreadable(String)
}

/// Reads at most `limit` bytes of a file and decodes them for display. Never executes or
/// interprets the content; files that look binary are reported as such.
public enum TextPreviewLoader {
    public static let defaultLimit = 512 * 1024

    public static func load(url: URL, limit: Int = defaultLimit) -> TextPreviewResult {
        let total: Int64
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            total = Int64(values.fileSize ?? 0)
        } catch {
            return .unreadable(error.localizedDescription)
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            return .unreadable(error.localizedDescription)
        }
        defer { try? handle.close() }
        let data: Data
        do {
            data = try handle.read(upToCount: limit) ?? Data()
        } catch {
            return .unreadable(error.localizedDescription)
        }
        return decode(data, totalBytes: max(total, Int64(data.count)))
    }

    public static func decode(_ data: Data, totalBytes: Int64) -> TextPreviewResult {
        let truncated = Int64(data.count) < totalBytes
        let bytes = [UInt8](data)

        // Byte-order marks decide the encoding outright.
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return utf8(Array(bytes.dropFirst(3)), truncated: truncated, total: totalBytes, name: "UTF-8")
        }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            let little = bytes[0] == 0xFF
            var body = Array(bytes.dropFirst(2))
            if body.count % 2 == 1 { body.removeLast() }
            let encoding: String.Encoding = little ? .utf16LittleEndian : .utf16BigEndian
            guard let text = String(bytes: body, encoding: encoding) else { return .binary }
            return .text(make(text, name: little ? "UTF-16 LE" : "UTF-16 BE", truncated: truncated, total: totalBytes))
        }

        if looksBinary(bytes) { return .binary }
        if case .text(let content) = utf8(bytes, truncated: truncated, total: totalBytes, name: "UTF-8") {
            return .text(content)
        }
        // Legacy 8-bit text. Windows-1252 is a superset of Latin-1 for printable text.
        if let text = String(bytes: bytes, encoding: .windowsCP1252) {
            return .text(make(text, name: "Western (Windows 1252)", truncated: truncated, total: totalBytes))
        }
        if let text = String(bytes: bytes, encoding: .isoLatin1) {
            return .text(make(text, name: "Western (ISO Latin 1)", truncated: truncated, total: totalBytes))
        }
        return .binary
    }

    /// NUL bytes, or more than 10% control characters other than tab, newline,
    /// carriage return, form feed and escape, mean "not text".
    static func looksBinary(_ bytes: [UInt8]) -> Bool {
        if bytes.isEmpty { return false }
        let sample = bytes.prefix(8192)
        if sample.contains(0) { return true }
        let control = sample.filter { b in
            b < 0x20 && b != 0x09 && b != 0x0A && b != 0x0D && b != 0x0C && b != 0x1B
        }.count
        return control * 10 > sample.count
    }

    private static func utf8(_ bytes: [UInt8], truncated: Bool, total: Int64, name: String) -> TextPreviewResult {
        // A multi-byte character may be cut at the read limit; drop up to 3 bytes.
        var sample = bytes
        for attempt in 0...3 {
            if let text = String(bytes: sample, encoding: .utf8) {
                return .text(make(text, name: name, truncated: truncated, total: total))
            }
            guard truncated, attempt < 3, !sample.isEmpty else { break }
            sample.removeLast()
        }
        return .binary
    }

    private static func make(_ text: String, name: String, truncated: Bool, total: Int64) -> TextPreviewContent {
        var lines = 0
        for scalar in text.unicodeScalars where scalar == "\n" { lines += 1 }
        if !text.isEmpty && !text.hasSuffix("\n") { lines += 1 }
        return TextPreviewContent(text: text, encodingName: name, isTruncated: truncated, totalBytes: total, lineCount: lines)
    }
}

// MARK: - Image viewer maths

/// Zoom steps and fit calculations for the image viewer, kept free of UI types.
public enum ZoomMath {
    public static let steps: [Double] = [0.05, 0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8, 16]
    public static let range: ClosedRange<Double> = 0.02...16

    /// Scale that fits `content` inside `container` without upscaling past 100%
    /// unless `allowUpscale` is set.
    public static func fitScale(content: (width: Double, height: Double), container: (width: Double, height: Double), allowUpscale: Bool = false) -> Double {
        guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else { return 1 }
        let scale = min(container.width / content.width, container.height / content.height)
        return allowUpscale ? scale : min(scale, 1)
    }

    public static func zoomIn(from scale: Double) -> Double {
        steps.first { $0 > scale + 0.0001 } ?? range.upperBound
    }

    public static func zoomOut(from scale: Double) -> Double {
        steps.last { $0 < scale - 0.0001 } ?? range.lowerBound
    }

    /// "9.6%", "100%", "250%".
    public static func percent(_ scale: Double) -> String {
        let value = scale * 100
        if value >= 10 { return "\(Int(value.rounded()))%" }
        return String(format: "%.1f%%", value)
    }

    /// Size after a rotation by `quarterTurns` × 90°.
    public static func rotatedSize(width: Double, height: Double, quarterTurns: Int) -> (width: Double, height: Double) {
        quarterTurns % 2 == 0 ? (width, height) : (height, width)
    }

    /// Normalizes any number of quarter turns to 0...3.
    public static func normalizedTurns(_ turns: Int) -> Int {
        ((turns % 4) + 4) % 4
    }
}
