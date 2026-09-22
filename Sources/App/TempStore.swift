import Foundation
import PDFUnpackKit

/// Writes embedded-file bytes to a per-session temp directory on demand and caches
/// the resulting URLs. Quick Look and drag-out both need a real file on disk;
/// this defers that write until first use so large portfolios don't hit disk
/// eagerly. The session directory is removed on app termination.
final class TempStore {
    static let shared = TempStore()

    private let sessionDir: URL
    private var cache: [UUID: URL] = [:]
    private var usedNames: Set<String> = []
    private let lock = NSLock()

    private init() {
        sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFUnpack-\(UUID().uuidString)", isDirectory: true)
    }

    /// Materialize `file` to disk (once) and return its file URL.
    func materialize(_ file: EmbeddedFile) throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        if let url = cache[file.id] { return url }

        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        // Reserve the deduped name against a copy and only commit it if the
        // write succeeds, so a failed write doesn't burn a name for the session.
        var reserved = usedNames
        let filename = Filename.deduplicated(Filename.sanitized(file.name), taken: &reserved)
        let url = sessionDir.appendingPathComponent(filename)
        try file.data.write(to: url)
        usedNames = reserved
        cache[file.id] = url
        return url
    }

    /// Synchronized with `materialize` so cleanup can't race a concurrent
    /// drag/Quick Look write mid-materialization.
    func cleanup() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: sessionDir)
        cache.removeAll()
        usedNames.removeAll()
    }
}
