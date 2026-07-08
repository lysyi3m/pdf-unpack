import XCTest
@testable import PDFUnpackKit

final class FilenameTests: XCTestCase {

    func testStripsDirectoryComponents() {
        XCTAssertEqual(Filename.sanitized("../../etc/passwd"), "passwd")
        XCTAssertEqual(Filename.sanitized("a/b/c.txt"), "c.txt")
    }

    func testStripsLeadingDots() {
        XCTAssertEqual(Filename.sanitized(".hidden"), "hidden")
        XCTAssertEqual(Filename.sanitized("..secret.txt"), "secret.txt")
    }

    func testEmptyBecomesUntitled() {
        XCTAssertEqual(Filename.sanitized(""), "Untitled")
        XCTAssertEqual(Filename.sanitized("   "), "Untitled")
        XCTAssertEqual(Filename.sanitized("///"), "Untitled")
    }

    func testKeepsUnicodeAndSpaces() {
        XCTAssertEqual(Filename.sanitized("Отчёт 2024.pdf"), "Отчёт 2024.pdf")
        XCTAssertEqual(Filename.sanitized("emoji 🎉.png"), "emoji 🎉.png")
    }

    func testDeduplicationSuffixesBeforeExtension() {
        var taken = Set<String>()
        XCTAssertEqual(Filename.deduplicated("report.pdf", taken: &taken), "report.pdf")
        XCTAssertEqual(Filename.deduplicated("report.pdf", taken: &taken), "report 2.pdf")
        XCTAssertEqual(Filename.deduplicated("report.pdf", taken: &taken), "report 3.pdf")
    }

    func testDeduplicationWithoutExtension() {
        var taken = Set<String>()
        XCTAssertEqual(Filename.deduplicated("README", taken: &taken), "README")
        XCTAssertEqual(Filename.deduplicated("README", taken: &taken), "README 2")
    }
}
