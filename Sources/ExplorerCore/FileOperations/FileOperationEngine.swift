import Foundation

/// Performs file operations with conflict resolution, progress, cancellation and
/// partial-failure reporting.
///
/// Safety rules:
/// * Nothing is ever overwritten silently; conflicts go through `ConflictHandler`.
/// * Copies are written to a hidden temporary name in the destination folder and
///   renamed into place only after they complete, so a failed or interrupted copy never
///   leaves a half-written item under the final name.
/// * "Replace" moves the existing item to the Trash (when the volume supports it)
///   before the new item takes its name.
/// * Cancellation is checked between top-level items; the item in flight finishes.
public final class FileOperationEngine: @unchecked Sendable {
    private let trash: Trashing
    private var fm: FileManager { FileManager.default }

    public init(trash: Trashing = SystemTrash()) {
        self.trash = trash
    }

    // MARK: - Copy / move

    public func copy(
        _ sources: [URL], into destination: URL,
        conflicts: ConflictHandler, progress: ProgressHandler? = nil
    ) async -> FileOperationReport {
        await transfer(sources, into: destination, kind: .copy, conflicts: conflicts, progress: progress)
    }

    public func move(
        _ sources: [URL], into destination: URL,
        conflicts: ConflictHandler, progress: ProgressHandler? = nil
    ) async -> FileOperationReport {
        await transfer(sources, into: destination, kind: .move, conflicts: conflicts, progress: progress)
    }

    private func transfer(
        _ rawSources: [URL], into rawDestination: URL, kind: FileOperationKind,
        conflicts: ConflictHandler, progress: ProgressHandler?
    ) async -> FileOperationReport {
        var report = FileOperationReport(kind: kind)
        let destination = rawDestination.standardizedFileURL
        let sources = Self.deduplicated(rawSources)

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: destination.path, isDirectory: &isDir), isDir.boolValue else {
            report.failures = sources.map { .init(url: $0, error: .notFound(path: destination.path)) }
            return report
        }

        // Sizes for progress and the free-space check (skipped for same-volume moves,
        // which are renames).
        var sizes: [URL: Int64] = [:]
        var totalBytes: Int64 = 0
        for source in sources {
            if Task.isCancelled { report.cancelled = true; return report }
            let needsCopy = kind == .copy || !FileSystemFacts.isSameVolume(source, destination)
            if needsCopy, let size = try? FileSystemFacts.totalSize(of: source) {
                sizes[source] = size
                totalBytes += size
            }
        }
        if let available = FileSystemFacts.availableCapacity(at: destination), totalBytes > available {
            report.failures = sources.map {
                .init(url: $0, error: .insufficientSpace(required: totalBytes, available: available))
            }
            return report
        }

        var state = OperationProgress(
            kind: kind, completedItems: 0, totalItems: sources.count,
            completedBytes: 0, totalBytes: totalBytes, currentName: ""
        )
        progress?(state)

        var sticky: ConflictAction?
        var anyReplaced = false

        for (index, source) in sources.enumerated() {
            if Task.isCancelled { report.cancelled = true; break }
            state.currentName = source.lastPathComponent
            progress?(state)
            defer {
                state.completedItems += 1
                state.completedBytes += sizes[source] ?? 0
                progress?(state)
            }

            guard fm.fileExists(atPath: source.path) || Self.isSymlink(source) else {
                report.failures.append(.init(url: source, error: .notFound(path: source.path)))
                continue
            }
            if PathBreadcrumbs.isDescendant(destination, of: source, orEqual: true) {
                report.failures.append(.init(url: source, error: .destinationInsideSource(path: source.path)))
                continue
            }
            let sameParent = source.deletingLastPathComponent().standardizedFileURL == destination
            if kind == .move && sameParent {
                report.skipped.append(source)   // Moving into the folder it is already in.
                continue
            }

            let sourceIsDir = Self.isDirectory(source)
            var target = destination.appendingPathComponent(source.lastPathComponent)
            var replace = false

            if kind == .copy && sameParent {
                // Pasting into the same folder makes a copy, as Finder does.
                target = destination.appendingPathComponent(
                    UniqueNameGenerator.duplicateName(for: source.lastPathComponent, isDirectory: sourceIsDir && !Self.isPackageLike(source)) {
                        self.exists(destination.appendingPathComponent($0))
                    })
            } else if exists(target) {
                if PathBreadcrumbs.isDescendant(source, of: target) {
                    report.failures.append(.init(url: source, error: .replacingAncestor(path: target.path)))
                    continue
                }
                let action: ConflictAction
                if let sticky {
                    action = sticky
                } else {
                    let conflict = FileConflict(
                        operation: kind, source: source, existing: target,
                        sourceIsDirectory: sourceIsDir, existingIsDirectory: Self.isDirectory(target),
                        remainingItems: sources.count - index - 1
                    )
                    let resolution = await conflicts(conflict)
                    action = resolution.action
                    if resolution.applyToRemaining { sticky = action }
                }
                switch action {
                case .cancel:
                    report.cancelled = true
                case .skip:
                    report.skipped.append(source)
                    continue
                case .keepBoth:
                    target = destination.appendingPathComponent(
                        UniqueNameGenerator.keepBothName(for: source.lastPathComponent, isDirectory: sourceIsDir && !Self.isPackageLike(source)) {
                            self.exists(destination.appendingPathComponent($0))
                        })
                case .replace:
                    replace = true
                }
                if report.cancelled { break }
            }

            do {
                if kind == .copy {
                    try copyItem(source, to: target, replacing: replace, report: &report)
                } else {
                    try moveItem(source, to: target, replacing: replace, report: &report)
                }
                if replace { anyReplaced = true }
                report.completed.append(Transfer(source: source, destination: target))
            } catch {
                report.failures.append(.init(url: source, error: FileOperationError.classify(error, path: source.path)))
            }
        }

        if !report.completed.isEmpty && !anyReplaced {
            report.record = kind == .copy ? .created(report.destinations) : .moved(report.completed)
        }
        return report
    }

    private func copyItem(_ source: URL, to target: URL, replacing: Bool, report: inout FileOperationReport) throws {
        let temp = Self.temporaryURL(near: target)
        do {
            try fm.copyItem(at: source, to: temp)
            if replacing { try replaceExisting(target, report: &report) }
            try fm.moveItem(at: temp, to: target)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    private func moveItem(_ source: URL, to target: URL, replacing: Bool, report: inout FileOperationReport) throws {
        if FileSystemFacts.isSameVolume(source, target.deletingLastPathComponent()) {
            if !replacing {
                try fm.moveItem(at: source, to: target)
                return
            }
            // Park the source beside the target, retire the existing item, then rename.
            let temp = Self.temporaryURL(near: target)
            try fm.moveItem(at: source, to: temp)
            do {
                try replaceExisting(target, report: &report)
                try fm.moveItem(at: temp, to: target)
            } catch {
                try? fm.moveItem(at: temp, to: source)
                throw error
            }
            return
        }
        // Different volumes: copy completely, then remove the original.
        try copyItem(source, to: target, replacing: replacing, report: &report)
        do {
            try fm.removeItem(at: source)
        } catch {
            throw FileOperationError.sourceNotRemoved(path: source.path)
        }
    }

    /// Retires an item that is being replaced: Trash when possible, otherwise delete.
    private func replaceExisting(_ url: URL, report: inout FileOperationReport) throws {
        do {
            _ = try trash.trashItem(at: url)
        } catch {
            try fm.removeItem(at: url)
        }
        report.replacedItems.append(url)
    }

    // MARK: - Duplicate, new folder, rename

    public func duplicate(_ sources: [URL], progress: ProgressHandler? = nil) async -> FileOperationReport {
        var report = FileOperationReport(kind: .duplicate)
        var state = OperationProgress(kind: .duplicate, completedItems: 0, totalItems: sources.count, completedBytes: 0, totalBytes: 0, currentName: "")
        for source in Self.deduplicated(sources) {
            if Task.isCancelled { report.cancelled = true; break }
            state.currentName = source.lastPathComponent
            progress?(state)
            let folder = source.deletingLastPathComponent()
            let name = UniqueNameGenerator.duplicateName(
                for: source.lastPathComponent,
                isDirectory: Self.isDirectory(source) && !Self.isPackageLike(source)
            ) { self.exists(folder.appendingPathComponent($0)) }
            let target = folder.appendingPathComponent(name)
            do {
                try copyItem(source, to: target, replacing: false, report: &report)
                report.completed.append(Transfer(source: source, destination: target))
            } catch {
                report.failures.append(.init(url: source, error: FileOperationError.classify(error, path: source.path)))
            }
            state.completedItems += 1
            progress?(state)
        }
        if !report.completed.isEmpty { report.record = .created(report.destinations) }
        return report
    }

    /// Creates a folder. With `name == nil` uses "untitled folder", "untitled folder 2", …
    public func createFolder(in directory: URL, name: String? = nil) throws -> URL {
        let finalName: String
        if let name {
            if let issue = FilenameValidator.validate(name).first { throw FileOperationError.invalidName(issue) }
            finalName = name
        } else {
            finalName = UniqueNameGenerator.newFolderName { self.exists(directory.appendingPathComponent($0)) }
        }
        let url = directory.appendingPathComponent(finalName, isDirectory: true)
        if exists(url) { throw FileOperationError.alreadyExists(path: url.path) }
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            throw FileOperationError.classify(error, path: url.path)
        }
        return url.standardizedFileURL
    }

    /// Renames in place. Case-only changes go through a temporary name so they work on
    /// case-insensitive volumes.
    public func rename(_ url: URL, to newName: String) throws -> URL {
        if let issue = FilenameValidator.validate(newName).first { throw FileOperationError.invalidName(issue) }
        let source = url.standardizedFileURL
        let target = source.deletingLastPathComponent().appendingPathComponent(newName)
        if newName == source.lastPathComponent { return source }
        do {
            if newName.lowercased() == source.lastPathComponent.lowercased() {
                let temp = Self.temporaryURL(near: target)
                try fm.moveItem(at: source, to: temp)
                do { try fm.moveItem(at: temp, to: target) } catch {
                    try? fm.moveItem(at: temp, to: source)
                    throw error
                }
            } else {
                if exists(target) { throw FileOperationError.alreadyExists(path: target.path) }
                try fm.moveItem(at: source, to: target)
            }
        } catch {
            throw FileOperationError.classify(error, path: source.path)
        }
        return target.standardizedFileURL
    }

    // MARK: - Trash and delete

    public func moveToTrash(_ urls: [URL]) async -> FileOperationReport {
        var report = FileOperationReport(kind: .trash)
        var restorable = true
        for url in Self.deduplicated(urls) {
            if Task.isCancelled { report.cancelled = true; break }
            do {
                let result = try trash.trashItem(at: url)
                if result == nil { restorable = false }
                report.completed.append(Transfer(source: url, destination: result ?? url))
            } catch {
                report.failures.append(.init(url: url, error: FileOperationError.classify(error, path: url.path)))
            }
        }
        if restorable && !report.completed.isEmpty { report.record = .trashed(report.completed) }
        return report
    }

    /// Permanently removes items. Irreversible: the caller must have confirmed.
    public func deletePermanently(_ urls: [URL]) async -> FileOperationReport {
        var report = FileOperationReport(kind: .delete)
        for url in Self.deduplicated(urls) {
            if Task.isCancelled { report.cancelled = true; break }
            do {
                try fm.removeItem(at: url)
                report.completed.append(Transfer(source: url, destination: url))
            } catch {
                report.failures.append(.init(url: url, error: FileOperationError.classify(error, path: url.path)))
            }
        }
        return report
    }

    // MARK: - Batch rename

    /// Applies a validated plan in two phases (to temporary names, then to final names)
    /// so swaps such as a→b, b→a succeed.
    public func applyBatchRename(_ plan: [BatchRenameEntry]) -> FileOperationReport {
        var report = FileOperationReport(kind: .batchRename)
        let changes = plan.filter { $0.isChange }
        if let invalid = plan.first(where: { $0.issue != nil }) {
            report.failures = [.init(url: invalid.source, error: .other(path: invalid.source.path, message: invalid.issue!.message))]
            return report
        }
        var staged: [(entry: BatchRenameEntry, temp: URL)] = []
        for entry in changes {
            let temp = Self.temporaryURL(near: entry.destination)
            do {
                try fm.moveItem(at: entry.source, to: temp)
                staged.append((entry, temp))
            } catch {
                report.failures.append(.init(url: entry.source, error: FileOperationError.classify(error, path: entry.source.path)))
            }
        }
        for (entry, temp) in staged {
            do {
                if exists(entry.destination) { throw FileOperationError.alreadyExists(path: entry.destination.path) }
                try fm.moveItem(at: temp, to: entry.destination)
                report.completed.append(Transfer(source: entry.source, destination: entry.destination))
            } catch {
                // Put the item back under its original name.
                try? fm.moveItem(at: temp, to: entry.source)
                report.failures.append(.init(url: entry.source, error: FileOperationError.classify(error, path: entry.source.path)))
            }
        }
        if !report.completed.isEmpty { report.record = .renamed(report.completed) }
        return report
    }

    // MARK: - Undo

    /// Reverses a record when the filesystem still matches it. Never overwrites.
    public func undo(_ record: FileOperationRecord) async -> FileOperationReport {
        var report = FileOperationReport(kind: .undo)
        switch record {
        case .created(let urls):
            for url in urls {
                guard exists(url) else {
                    report.failures.append(.init(url: url, error: .cannotUndo(reason: "“\(url.lastPathComponent)” no longer exists.")))
                    continue
                }
                do {
                    let trashed = try trash.trashItem(at: url)
                    report.completed.append(Transfer(source: url, destination: trashed ?? url))
                } catch {
                    report.failures.append(.init(url: url, error: FileOperationError.classify(error, path: url.path)))
                }
            }
        case .renamed(let transfers), .moved(let transfers), .trashed(let transfers):
            // Reverse in the opposite order so chained renames unwind correctly.
            for transfer in transfers.reversed() {
                let current = transfer.destination
                let original = transfer.source
                guard exists(current) else {
                    report.failures.append(.init(url: current, error: .cannotUndo(reason: "“\(current.lastPathComponent)” is no longer where it was.")))
                    continue
                }
                guard !exists(original) || original.path.lowercased() == current.path.lowercased() else {
                    report.failures.append(.init(url: original, error: .cannotUndo(reason: "Another item named “\(original.lastPathComponent)” now exists.")))
                    continue
                }
                do {
                    if original.path.lowercased() == current.path.lowercased() {
                        _ = try rename(current, to: original.lastPathComponent)
                    } else {
                        try fm.moveItem(at: current, to: original)
                    }
                    report.completed.append(Transfer(source: current, destination: original))
                } catch {
                    report.failures.append(.init(url: current, error: FileOperationError.classify(error, path: current.path)))
                }
            }
        }
        return report
    }

    // MARK: - Helpers

    private func exists(_ url: URL) -> Bool {
        fm.fileExists(atPath: url.path) || Self.isSymlink(url)
    }

    static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    static func isDirectory(_ url: URL) -> Bool {
        guard let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return v.isDirectory == true && v.isSymbolicLink != true
    }

    static func isPackageLike(_ url: URL) -> Bool {
        #if os(macOS)
        if let v = try? url.resourceValues(forKeys: [.isPackageKey]), v.isPackage == true { return true }
        #endif
        return FileTypeClassifier.looksLikePackage(name: url.lastPathComponent)
    }

    static func temporaryURL(near target: URL) -> URL {
        let token = UUID().uuidString.prefix(8)
        return target.deletingLastPathComponent().appendingPathComponent(".lexp-\(token).partial")
    }

    /// Removes duplicates and items already covered by a selected ancestor.
    static func deduplicated(_ urls: [URL]) -> [URL] {
        let standardized = urls.map { $0.standardizedFileURL }
        var seen = Set<String>()
        var result: [URL] = []
        for url in standardized where !seen.contains(url.path) {
            seen.insert(url.path)
            let coveredByAncestor = standardized.contains { other in
                other.path != url.path && PathBreadcrumbs.isDescendant(url, of: other)
            }
            if !coveredByAncestor { result.append(url) }
        }
        return result
    }
}
