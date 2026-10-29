import Foundation

public enum DisplayFormat {
    /// Decimal units like Finder ("5.7 MB").
    public static func byteCount(_ bytes: Int64) -> String {
        if bytes < 1000 { return bytes == 1 ? "1 byte" : "\(bytes) bytes" }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes)
        var index = -1
        while value >= 1000 && index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let formatted = value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(formatted) \(units[index])"
    }

    /// `rwxr-xr-x` from POSIX permission bits, with a leading type character.
    public static func symbolicPermissions(_ mode: UInt16, isDirectory: Bool, isSymlink: Bool = false) -> String {
        let type = isSymlink ? "l" : (isDirectory ? "d" : "-")
        let flags: [(UInt16, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x"),
        ]
        var chars = flags.map { mode & $0.0 != 0 ? $0.1 : Character("-") }
        if mode & 0o4000 != 0 { chars[2] = chars[2] == "x" ? "s" : "S" }
        if mode & 0o2000 != 0 { chars[5] = chars[5] == "x" ? "s" : "S" }
        if mode & 0o1000 != 0 { chars[8] = chars[8] == "x" ? "t" : "T" }
        return type + String(chars)
    }

    public static func octalPermissions(_ mode: UInt16) -> String {
        String(format: "%04o", mode & 0o7777)
    }

    public static func itemCount(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }

    /// Status-bar text: "34 items", "1 of 34 selected, 5.7 MB".
    public static func statusSummary(total: Int, selected: Int, selectedBytes: Int64?) -> String {
        guard selected > 0 else { return itemCount(total) }
        var text = "\(selected) of \(total) selected"
        if let bytes = selectedBytes, bytes > 0 { text += ", \(byteCount(bytes))" }
        return text
    }

    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
