import XCTest
@testable import PDFUnpackKit

/// Covers the non-portfolio embedding locations: page /FileAttachment
/// annotations and PDF 2.0 associated files (/AF), plus de-duplication of a file
/// referenced from more than one place — by object identity (shared.txt) and by
/// content (dup.txt, distinct filespec objects with identical bytes).
/// Fixture: fixtures/sample-mixed.pdf.
final class MixedSourcesTests: XCTestCase {

    static func fixtureURL() throws -> URL {
        try Fixtures.url("sample-mixed.pdf")
    }

    // Kept in sync with MIXED_FILES in tools/make_fixtures.py.
    static let expected: [String: Data] = [
        "embedded.txt":  Data("document-level embedded file\n".utf8),        // /EmbeddedFiles
        "shared.txt":    Data("shared between EmbeddedFiles and AF\n".utf8),  // /EmbeddedFiles + /AF (same object)
        "invoice.xml":   Data("<invoice><total>42</total></invoice>\n".utf8), // catalog /AF
        "annotated.txt": Data("attached to a page annotation\n".utf8),       // page /FileAttachment
        "page-af.txt":   Data("page-level associated file\n".utf8),          // page /AF
        "dup.txt":       Data("identical content under two distinct filespec objects\n".utf8), // distinct objects, same bytes
    ]

    private func embeddedFiles() throws -> [RawEmbeddedFile] {
        let extractor = try EmbeddedFileExtractor(url: Self.fixtureURL())
        XCTAssertTrue(extractor.isUnlocked)   // fixture is not encrypted
        return try extractor.extractEmbeddedFiles()
    }

    func testAllSourcesExtractedAndDeduped() throws {
        let files = try embeddedFiles()
        XCTAssertEqual(files.count, 6, "expected 6 deduped files, got \(files.map(\.name))")
        XCTAssertEqual(Set(files.map(\.name)), Set(Self.expected.keys))
        // shared.txt: same filespec object referenced twice → object-identity dedup.
        XCTAssertEqual(files.filter { $0.name == "shared.txt" }.count, 1, "shared.txt not deduped")
        // dup.txt: two distinct filespec objects, identical bytes → content dedup.
        XCTAssertEqual(files.filter { $0.name == "dup.txt" }.count, 1, "dup.txt not content-deduped")
    }

    func testBytesRoundTrip() throws {
        var byName: [String: Data] = [:]
        for file in try embeddedFiles() where byName[file.name] == nil { byName[file.name] = file.data }
        for (name, expected) in Self.expected {
            XCTAssertEqual(byName[name], expected, "content mismatch for \(name)")
        }
    }
}
