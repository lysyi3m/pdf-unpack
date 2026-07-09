import XCTest
@testable import PDFUnpackKit

/// Covers the non-portfolio embedding locations: page /FileAttachment
/// annotations and PDF 2.0 associated files (/AF), plus de-duplication of a file
/// referenced from more than one place — by object identity (shared.txt) and by
/// content (dup.txt, distinct filespec objects with identical bytes).
/// Fixture: fixtures/sample-mixed.pdf.
final class MixedSourcesTests: XCTestCase {

    static func fixtureURL(file: StaticString = #filePath) throws -> URL {
        let testFile = URL(fileURLWithPath: "\(file)")
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let fixture = repoRoot
            .appendingPathComponent("fixtures")
            .appendingPathComponent("sample-mixed.pdf")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("Fixture missing at \(fixture.path)")
        }
        return fixture
    }

    // Kept in sync with the fixture contents.
    static let expected: [String: Data] = [
        "embedded.txt":  Data("document-level embedded file\n".utf8),        // /EmbeddedFiles
        "shared.txt":    Data("shared between EmbeddedFiles and AF\n".utf8),  // /EmbeddedFiles + /AF (same object)
        "invoice.xml":   Data("<invoice><total>42</total></invoice>\n".utf8), // catalog /AF
        "annotated.txt": Data("attached to a page annotation\n".utf8),       // page /FileAttachment
        "page-af.txt":   Data("page-level associated file\n".utf8),          // page /AF
        "dup.txt":       Data("identical content under two distinct filespec objects\n".utf8), // distinct objects, same bytes
    ]

    private func attachments() throws -> [RawAttachment] {
        let extractor = try PDFAttachmentExtractor(url: Self.fixtureURL())
        XCTAssertTrue(extractor.isUnlocked)   // fixture is not encrypted
        return try extractor.extractAttachments()
    }

    func testAllSourcesExtractedAndDeduped() throws {
        let atts = try attachments()
        XCTAssertEqual(atts.count, 6, "expected 6 deduped files, got \(atts.map(\.name))")
        XCTAssertEqual(Set(atts.map(\.name)), Set(Self.expected.keys))
        // shared.txt: same filespec object referenced twice → object-identity dedup.
        XCTAssertEqual(atts.filter { $0.name == "shared.txt" }.count, 1, "shared.txt not deduped")
        // dup.txt: two distinct filespec objects, identical bytes → content dedup.
        XCTAssertEqual(atts.filter { $0.name == "dup.txt" }.count, 1, "dup.txt not content-deduped")
    }

    func testBytesRoundTrip() throws {
        var byName: [String: Data] = [:]
        for att in try attachments() where byName[att.name] == nil { byName[att.name] = att.data }
        for (name, expected) in Self.expected {
            XCTAssertEqual(byName[name], expected, "content mismatch for \(name)")
        }
    }
}
