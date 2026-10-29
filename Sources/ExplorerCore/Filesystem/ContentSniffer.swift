import Foundation

/// Identifies common formats from leading bytes so preview selection does not depend
/// only on the filename extension. Reads at most `headerLength` bytes; never executes
/// or fully loads the file.
public enum ContentSniffer {
    public enum Signature: String, Sendable, Equatable {
        case png, jpeg, gif, tiff, bmp, webp, heif, pdf, zip, gzip, mp4Family, wave, aiff, mp3, flac, ogg
        case utf8Text, binary, empty
    }

    public static let headerLength = 4096

    public static func sniff(url: URL) -> Signature? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data: Data
        do {
            data = try handle.read(upToCount: headerLength) ?? Data()
        } catch {
            return nil
        }
        return sniff(data: data)
    }

    public static func sniff(data: Data) -> Signature {
        let bytes = [UInt8](data.prefix(headerLength))
        if bytes.isEmpty { return .empty }
        func starts(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
            guard bytes.count >= offset + prefix.count else { return false }
            return Array(bytes[offset..<(offset + prefix.count)]) == prefix
        }
        func ascii(_ s: String, at offset: Int = 0) -> Bool { starts(Array(s.utf8), at: offset) }

        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if starts([0xFF, 0xD8, 0xFF]) { return .jpeg }
        if ascii("GIF87a") || ascii("GIF89a") { return .gif }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
        if ascii("BM") && bytes.count >= 14 { return .bmp }
        if ascii("RIFF") && ascii("WEBP", at: 8) { return .webp }
        if ascii("RIFF") && ascii("WAVE", at: 8) { return .wave }
        if ascii("FORM") && (ascii("AIFF", at: 8) || ascii("AIFC", at: 8)) { return .aiff }
        if ascii("%PDF-") { return .pdf }
        if starts([0x50, 0x4B, 0x03, 0x04]) || starts([0x50, 0x4B, 0x05, 0x06]) { return .zip }
        if starts([0x1F, 0x8B]) { return .gzip }
        if ascii("fLaC") { return .flac }
        if ascii("OggS") { return .ogg }
        if ascii("ID3") || starts([0xFF, 0xFB]) || starts([0xFF, 0xF3]) || starts([0xFF, 0xF2]) { return .mp3 }
        if ascii("ftyp", at: 4) {
            let brand = String(decoding: bytes[8..<min(12, bytes.count)], as: UTF8.self)
            if ["heic", "heix", "hevc", "heim", "heis", "mif1", "msf1", "avif"].contains(brand) { return .heif }
            return .mp4Family
        }
        return looksLikeText(bytes) ? .utf8Text : .binary
    }

    /// Text if there are no NUL bytes and the sample decodes as UTF-8 (allowing a
    /// multi-byte sequence truncated at the end of the sample).
    static func looksLikeText(_ bytes: [UInt8]) -> Bool {
        if bytes.contains(0) { return false }
        var sample = bytes
        for _ in 0..<4 {
            if String(bytes: sample, encoding: .utf8) != nil { return true }
            if sample.isEmpty { break }
            sample.removeLast()
        }
        return false
    }

    public static func category(for signature: Signature) -> FileCategory? {
        switch signature {
        case .png, .jpeg, .gif, .tiff, .bmp, .webp, .heif: return .image
        case .pdf: return .pdf
        case .zip, .gzip: return .archive
        case .mp4Family: return .video
        case .wave, .aiff, .mp3, .flac, .ogg: return .audio
        case .utf8Text: return .text
        case .binary, .empty: return nil
        }
    }
}
