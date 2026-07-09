import XCTest
@testable import PDFUnpackKit

final class PDFAttachmentExtractorTests: XCTestCase {

    static let password = "test123"

    /// Locate fixtures/sample-protected.pdf by walking up from this source file
    /// to the repo root. The test bundle is NOT app-hosted, so the runner is
    /// unsandboxed and can read straight from the repo.
    static func fixtureURL(file: StaticString = #filePath) throws -> URL {
        let testFile = URL(fileURLWithPath: "\(file)")
        // .../pdf-unpack/Tests/PDFAttachmentExtractorTests.swift → repo root is two up.
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let fixture = repoRoot
            .appendingPathComponent("fixtures")
            .appendingPathComponent("sample-protected.pdf")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("Fixture missing at \(fixture.path)")
        }
        return fixture
    }

    // Expected contents, kept in sync with the fixture.
    static let expectedTxt = Data("Hello, PDF Unpack!\n".utf8)
    static let expectedCsv = Data("name,value\nalpha,1\nbeta,2\n".utf8)
    static let expectedPng = Data([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xde, 0x00, 0x00, 0x00,
        0x0c, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
        0x00, 0x03, 0x01, 0x01, 0x00, 0xc9, 0xfe, 0x92, 0xef, 0x00, 0x00, 0x00,
        0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
    ])

    // MARK: - Encryption / unlock

    func testFixtureIsEncrypted() throws {
        let extractor = try PDFAttachmentExtractor(url: Self.fixtureURL())
        XCTAssertTrue(extractor.isEncrypted)
        XCTAssertFalse(extractor.isUnlocked)
    }

    func testExtractBeforeUnlockThrows() throws {
        let extractor = try PDFAttachmentExtractor(url: Self.fixtureURL())
        XCTAssertThrowsError(try extractor.extractAttachments()) { error in
            XCTAssertEqual(error as? PDFError, .notUnlocked)
        }
    }

    func testWrongPasswordFails() throws {
        let extractor = try PDFAttachmentExtractor(url: Self.fixtureURL())
        XCTAssertFalse(extractor.unlock(password: "nope"))
        XCTAssertFalse(extractor.isUnlocked)
    }

    func testCorrectPasswordUnlocks() throws {
        let extractor = try PDFAttachmentExtractor(url: Self.fixtureURL())
        XCTAssertTrue(extractor.unlock(password: Self.password))
        XCTAssertTrue(extractor.isUnlocked)
    }

    // MARK: - Extraction

    private func unlockedExtractor() throws -> PDFAttachmentExtractor {
        let extractor = try PDFAttachmentExtractor(url: Self.fixtureURL())
        XCTAssertTrue(extractor.unlock(password: Self.password))
        return extractor
    }

    func testAttachmentCount() throws {
        let atts = try unlockedExtractor().extractAttachments()
        XCTAssertEqual(atts.count, 3)
    }

    func testAttachmentNames() throws {
        let names = Set(try unlockedExtractor().extractAttachments().map(\.name))
        XCTAssertEqual(names, ["hello.txt", "data.csv", "pixel.png"])
    }

    func testAttachmentSizesMatchByteCounts() throws {
        for att in try unlockedExtractor().extractAttachments() {
            XCTAssertEqual(att.size, att.data.count, "size mismatch for \(att.name)")
        }
    }

    func testBytesRoundTrip() throws {
        let byName = Dictionary(
            uniqueKeysWithValues: try unlockedExtractor().extractAttachments().map { ($0.name, $0.data) }
        )
        XCTAssertEqual(byName["hello.txt"], Self.expectedTxt)
        XCTAssertEqual(byName["data.csv"], Self.expectedCsv)
        XCTAssertEqual(byName["pixel.png"], Self.expectedPng)
    }

    func testModDateParsed() throws {
        // Every attachment in the fixture is stamped with D:20240115103000Z.
        for att in try unlockedExtractor().extractAttachments() {
            let date = try XCTUnwrap(att.modDate, "missing modDate for \(att.name)")
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            XCTAssertEqual(c.year, 2024)
            XCTAssertEqual(c.month, 1)
            XCTAssertEqual(c.day, 15)
            XCTAssertEqual(c.hour, 10)
            XCTAssertEqual(c.minute, 30)
            XCTAssertEqual(c.second, 0)
        }
    }
}
