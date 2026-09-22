import Foundation

/// Locates the committed PDFs in `fixtures/`. The test bundle is not app-hosted, so the runner
/// is unsandboxed and reads straight from the repo.
///
/// A missing fixture fails the test instead of skipping it: every fixture is committed, so a
/// missing one means a broken checkout, and a skip would let CI pass without running anything.
/// `make fixtures` regenerates them; see `fixtures/README.md`.
enum Fixtures {
    static let protectedPassword = "test123"

    static func url(_ name: String) throws -> URL {
        // .../pdf-unpack/Tests/Fixtures.swift → the repo root is two levels up.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repoRoot.appendingPathComponent("fixtures").appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw Missing(path: fixture.path)
        }
        return fixture
    }

    struct Missing: Error, CustomStringConvertible {
        let path: String
        var description: String { "No fixture at \(path). Run `make fixtures`." }
    }
}
