import Foundation
import XCTest
@testable import ExplorerCore

/// A throwaway directory tree for integration tests. Never touches user files.
final class TempDirectory {
    let url: URL

    init(function: String = #function) throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalExplorerTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.standardizedFileURL
    }

    deinit {
        // Restore permissions changed by tests so cleanup succeeds.
        if let e = FileManager.default.enumerator(atPath: url.path) {
            while let p = e.nextObject() as? String {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.appendingPathComponent(p).path)
            }
        }
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func file(_ relative: String, _ contents: String = "x", modified: Date? = nil) throws -> URL {
        let target = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: target)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: target.path)
        }
        return target
    }

    @discardableResult
    func folder(_ relative: String) throws -> URL {
        let target = url.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(relative).path)
    }

    func read(_ relative: String) -> String? {
        (try? Data(contentsOf: url.appendingPathComponent(relative))).map { String(decoding: $0, as: UTF8.self) }
    }

    func names(_ relative: String = "") -> [String] {
        let dir = relative.isEmpty ? url : url.appendingPathComponent(relative)
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }
}

func item(_ name: String, dir: Bool = false, size: Int64? = nil, modified: TimeInterval? = nil, hidden: Bool? = nil) -> FileItem {
    FileItem(
        url: URL(fileURLWithPath: "/tmp/x").appendingPathComponent(name),
        isDirectory: dir,
        isHidden: hidden,
        size: size,
        modificationDate: modified.map { Date(timeIntervalSince1970: $0) }
    )
}

/// Records conflict prompts and answers with scripted resolutions.
final class ScriptedConflicts: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [ConflictResolution]
    private(set) var seen: [FileConflict] = []

    init(_ answers: [ConflictResolution]) { self.answers = answers }

    var handler: ConflictHandler {
        { conflict in self.answer(conflict) }
    }

    private func answer(_ conflict: FileConflict) -> ConflictResolution {
        lock.lock(); defer { lock.unlock() }
        seen.append(conflict)
        return answers.isEmpty ? ConflictResolution(.skip) : answers.removeFirst()
    }
}

var isRunningAsRoot: Bool { getuid() == 0 }
