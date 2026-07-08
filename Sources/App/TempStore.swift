import Foundation
import PDFUnpackKit

/// Writes attachment bytes to a per-session temp directory on demand and caches
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

    /// Materialize `att` to disk (once) and return its file URL.
    func materialize(_ att: Attachment) throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        if let url = cache[att.id] { return url }

        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let filename = Filename.deduplicated(Filename.sanitized(att.name), taken: &usedNames)
        let url = sessionDir.appendingPathComponent(filename)
        try att.data.write(to: url)
        cache[att.id] = url
        return url
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: sessionDir)
    }
}
