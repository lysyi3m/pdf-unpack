import Foundation
import PDFUnpackKit
import Synchronization

/// Writes embedded-file bytes to a per-session temp directory on demand and caches
/// the resulting URLs. Quick Look and drag-out both need a real file on disk;
/// this defers that write until first use so large portfolios don't hit disk
/// eagerly. The session directory is removed on app termination.
///
/// Called from the main actor and from drag-out's file export, which runs off it,
/// so all mutable state sits behind one `Mutex`.
final class TempStore: Sendable {
    static let shared = TempStore()

    private struct State {
        var cache: [UUID: URL] = [:]
        var usedNames: Set<String> = []
    }

    private let sessionDir: URL
    private let state = Mutex(State())

    private init() {
        sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFUnpack-\(UUID().uuidString)", isDirectory: true)
    }

    /// Materialize `file` to disk (once) and return its file URL.
    func materialize(_ file: EmbeddedFile) throws -> URL {
        try state.withLock { state in
            if let url = state.cache[file.id] { return url }

            try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            // Reserve the deduped name against a copy and only commit it if the
            // write succeeds, so a failed write doesn't burn a name for the session.
            var reserved = state.usedNames
            let filename = Filename.deduplicated(Filename.sanitized(file.name), taken: &reserved)
            let url = sessionDir.appendingPathComponent(filename)
            try file.data.write(to: url)
            state.usedNames = reserved
            state.cache[file.id] = url
            return url
        }
    }

    /// Holds the same lock as `materialize`, so cleanup can't race a concurrent
    /// drag/Quick Look write mid-materialization.
    func cleanup() {
        state.withLock { state in
            try? FileManager.default.removeItem(at: sessionDir)
            state.cache.removeAll()
            state.usedNames.removeAll()
        }
    }
}
