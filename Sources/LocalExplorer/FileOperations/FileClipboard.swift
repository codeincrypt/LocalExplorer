import AppKit

/// File clipboard on the general pasteboard, interoperable with Finder.
///
/// Files are written as file URLs, so "Copy" here and "Paste" in Finder works (and the
/// reverse). macOS has no system-wide "cut" for files, so cut state is tracked by this
/// app: a paste turns into a move only if the pasteboard still holds exactly what was
/// cut (verified with `changeCount`).
@MainActor
final class FileClipboard {
    private let pasteboard = NSPasteboard.general
    private var cutChangeCount: Int?
    private static let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

    func write(_ urls: [URL], cut: Bool) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        cutChangeCount = cut ? pasteboard.changeCount : nil
    }

    func fileURLs() -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: Self.fileOptions) as? [URL]) ?? []
    }

    var hasFiles: Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: Self.fileOptions)
    }

    /// True when the current pasteboard contents came from a Cut in this app.
    var isCut: Bool {
        guard let cutChangeCount else { return false }
        return cutChangeCount == pasteboard.changeCount
    }

    func finishCut() { cutChangeCount = nil }

    func copyText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        cutChangeCount = nil
    }
}
