import XCTest
@testable import PDFUnpackKit

/// Unlock, extraction, byte round-trip and date parsing. Fixture: fixtures/sample-protected.pdf.
final class EmbeddedFileExtractorTests: XCTestCase {

    static let password = Fixtures.protectedPassword

    static func fixtureURL() throws -> URL {
        try Fixtures.url("sample-protected.pdf")
    }

    // Expected contents. Kept in sync with PROTECTED_FILES in tools/make_fixtures.py.
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
        let extractor = try EmbeddedFileExtractor(url: Self.fixtureURL())
        XCTAssertTrue(extractor.isEncrypted)
        XCTAssertFalse(extractor.isUnlocked)
    }

    func testExtractBeforeUnlockThrows() throws {
        let extractor = try EmbeddedFileExtractor(url: Self.fixtureURL())
        XCTAssertThrowsError(try extractor.extractEmbeddedFiles()) { error in
            XCTAssertEqual(error as? PDFError, .notUnlocked)
        }
    }

    func testWrongPasswordFails() throws {
        let extractor = try EmbeddedFileExtractor(url: Self.fixtureURL())
        XCTAssertFalse(extractor.unlock(password: "nope"))
        XCTAssertFalse(extractor.isUnlocked)
    }

    func testCorrectPasswordUnlocks() throws {
        let extractor = try EmbeddedFileExtractor(url: Self.fixtureURL())
        XCTAssertTrue(extractor.unlock(password: Self.password))
        XCTAssertTrue(extractor.isUnlocked)
    }

    // MARK: - Extraction

    private func unlockedExtractor() throws -> EmbeddedFileExtractor {
        let extractor = try EmbeddedFileExtractor(url: Self.fixtureURL())
        XCTAssertTrue(extractor.unlock(password: Self.password))
        return extractor
    }

    func testEmbeddedFileCount() throws {
        let files = try unlockedExtractor().extractEmbeddedFiles()
        XCTAssertEqual(files.count, 3)
    }

    func testEmbeddedFileNames() throws {
        let names = Set(try unlockedExtractor().extractEmbeddedFiles().map(\.name))
        XCTAssertEqual(names, ["hello.txt", "data.csv", "pixel.png"])
    }

    func testEmbeddedFileSizesMatchByteCounts() throws {
        for file in try unlockedExtractor().extractEmbeddedFiles() {
            XCTAssertEqual(file.size, file.data.count, "size mismatch for \(file.name)")
        }
    }

    func testBytesRoundTrip() throws {
        let byName = Dictionary(
            uniqueKeysWithValues: try unlockedExtractor().extractEmbeddedFiles().map { ($0.name, $0.data) }
        )
        XCTAssertEqual(byName["hello.txt"], Self.expectedTxt)
        XCTAssertEqual(byName["data.csv"], Self.expectedCsv)
        XCTAssertEqual(byName["pixel.png"], Self.expectedPng)
    }

    func testModDateParsed() throws {
        // Every embedded file in the fixture is stamped with D:20240115103000Z.
        for file in try unlockedExtractor().extractEmbeddedFiles() {
            let date = try XCTUnwrap(file.modDate, "missing modDate for \(file.name)")
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
