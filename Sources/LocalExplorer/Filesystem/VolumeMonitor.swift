import AppKit
import ExplorerCore

/// Mounted volumes, kept current through NSWorkspace mount notifications.
@MainActor
final class VolumeMonitor: ObservableObject {
    struct Volume: Identifiable, Hashable {
        var id: String { url.path }
        let url: URL
        let name: String
        let isEjectable: Bool
        let isInternal: Bool
        let isRoot: Bool
        let isLocal: Bool

        var symbolName: String {
            if isRoot || isInternal { return "internaldrive" }
            if !isLocal { return "server.rack" }
            return isEjectable ? "externaldrive" : "externaldrive.fill"
        }
    }

    @Published private(set) var volumes: [Volume] = []
    /// Used/free space by volume path. Read off the main thread because a network
    /// volume can be slow to answer.
    @Published private(set) var capacities: [String: CapacityUsage] = [:]
    private var capacityTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init() {
        reload()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reload() }
            })
        }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
    }

    var rootVolumeName: String {
        volumes.first(where: \.isRoot)?.name ?? "Macintosh HD"
    }

    func reload() {
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey,
            .volumeIsInternalKey, .volumeIsRootFileSystemKey, .volumeIsLocalKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        volumes = urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return Volume(
                url: url.standardizedFileURL,
                name: v.volumeLocalizedName ?? url.lastPathComponent,
                isEjectable: (v.volumeIsEjectable ?? false) || (v.volumeIsRemovable ?? false),
                isInternal: v.volumeIsInternal ?? false,
                isRoot: v.volumeIsRootFileSystem ?? false,
                isLocal: v.volumeIsLocal ?? true
            )
        }
        .sorted { a, b in
            if a.isRoot != b.isRoot { return a.isRoot }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        refreshCapacities()
    }

    private func refreshCapacities() {
        capacityTask?.cancel()
        let urls = volumes.map(\.url)
        capacityTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                var map: [String: CapacityUsage] = [:]
                for url in urls { map[url.path] = FileSystemFacts.capacity(at: url) }
                return map
            }.value
            guard let self, !Task.isCancelled else { return }
            self.capacities = result
        }
    }

    func eject(_ volume: Volume) throws {
        try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
    }

    /// The mounted volume containing `url`, if any.
    func volume(containing url: URL) -> Volume? {
        volumes
            .filter { PathBreadcrumbs.isDescendant(url, of: $0.url, orEqual: true) }
            .max { $0.url.pathComponents.count < $1.url.pathComponents.count }
    }
}

/// Watches one directory for added, removed or renamed entries using a kqueue-backed
/// dispatch source. Events are coalesced and delivered on the main actor.
final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private let onChange: @MainActor () -> Void

    init?(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .link, .attrib, .extend, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.schedule() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func schedule() {
        pending?.cancel()
        let callback = onChange
        let item = DispatchWorkItem { Task { @MainActor in callback() } }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    deinit {
        pending?.cancel()
        source?.cancel()
    }
}
