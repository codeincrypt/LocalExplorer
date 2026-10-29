import Foundation

/// The "This Mac" start page: a virtual location that lists the standard folders and
/// the mounted drives. It is represented by a file URL that cannot exist (the root of
/// the startup volume is read-only), so history, tab persistence and the address bar
/// treat it like any other location.
public enum ThisMac {
    public static let title = "This Mac"
    public static let url = URL(fileURLWithPath: "/.this-mac")

    public static func isThisMac(_ url: URL) -> Bool {
        url.standardizedFileURL.path == self.url.path
    }
}

/// Used and free space of one volume.
public struct CapacityUsage: Equatable, Sendable {
    public let total: Int64
    public let available: Int64

    /// A volume is shown as low on space once this fraction is used (Windows turns its
    /// bar red at the same point).
    public static let lowSpaceFraction = 0.9

    public init(total: Int64, available: Int64) {
        self.total = max(0, total)
        self.available = min(max(0, available), self.total)
    }

    public var used: Int64 { total - available }

    /// 0...1; 0 when the total is unknown.
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    public var isLow: Bool { total > 0 && usedFraction >= Self.lowSpaceFraction }

    /// "18.3 GB free of 63.3 GB".
    public var summary: String {
        "\(DisplayFormat.byteCount(available)) free of \(DisplayFormat.byteCount(total))"
    }
}
