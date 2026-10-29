import AppKit
import ExplorerCore

/// Owns security-scoped bookmarks and access lifetimes.
///
/// * Bookmarks are created with `.withSecurityScope` when the process supports it (App
///   Sandbox builds) and fall back to regular bookmarks otherwise (direct distribution).
/// * Access to authorized locations starts at launch and is released when the location
///   is removed or the app terminates.
/// * Resolution never mounts volumes or shows UI, so a disconnected drive is reported as
///   unavailable instead of triggering a network or mount attempt.
@MainActor
final class AccessManager {
    struct Resolution {
        let url: URL
        let isStale: Bool
    }

    private var activeScopes: [String: URL] = [:]

    func bookmark(for url: URL) -> Data? {
        if let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            return data
        }
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolve(_ data: Data) -> Resolution? {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) {
            return Resolution(url: url, isStale: stale)
        }
        stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) {
            return Resolution(url: url, isStale: stale)
        }
        return nil
    }

    func startAccessing(_ url: URL) {
        let key = url.standardizedFileURL.path
        guard activeScopes[key] == nil else { return }
        // Returns false for URLs that are not security scoped (non-sandboxed builds);
        // that is expected and harmless.
        if url.startAccessingSecurityScopedResource() {
            activeScopes[key] = url
        }
    }

    func stopAccessing(_ url: URL) {
        let key = url.standardizedFileURL.path
        if let scoped = activeScopes.removeValue(forKey: key) {
            scoped.stopAccessingSecurityScopedResource()
        }
    }

    func stopAll() {
        for url in activeScopes.values { url.stopAccessingSecurityScopedResource() }
        activeScopes.removeAll()
    }

    /// Native folder picker. Returns the chosen folder or `nil` if cancelled.
    func requestFolderAccess(startingAt url: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Grant Access to a Folder"
        panel.message = "Choose a folder for \(AppConfiguration.productName) to browse. Access is remembered until you remove it."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = false
        if let url { panel.directoryURL = url }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Opens System Settings › Privacy & Security › Full Disk Access. The app cannot
    /// grant itself this permission; the user decides there.
    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
