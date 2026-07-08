import XCTest
@testable import PDFUnpackKit

final class PDFDateTests: XCTestCase {

    private func components(_ date: Date) -> DateComponents {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    func testFullUTC() throws {
        let c = components(try XCTUnwrap(PDFDate.parse("D:20240115103000Z")))
        XCTAssertEqual(c.year, 2024)
        XCTAssertEqual(c.month, 1)
        XCTAssertEqual(c.day, 15)
        XCTAssertEqual(c.hour, 10)
        XCTAssertEqual(c.minute, 30)
        XCTAssertEqual(c.second, 0)
    }

    func testPositiveOffsetNormalizesToUTC() throws {
        // 12:30 at +02'00' == 10:30 UTC.
        let c = components(try XCTUnwrap(PDFDate.parse("D:20240115123000+02'00'")))
        XCTAssertEqual(c.hour, 10)
        XCTAssertEqual(c.minute, 30)
    }

    func testNegativeOffsetNormalizesToUTC() throws {
        // 08:30 at -02'00' == 10:30 UTC.
        let c = components(try XCTUnwrap(PDFDate.parse("D:20240115083000-02'00'")))
        XCTAssertEqual(c.hour, 10)
        XCTAssertEqual(c.minute, 30)
    }

    func testYearOnly() throws {
        let c = components(try XCTUnwrap(PDFDate.parse("D:2024")))
        XCTAssertEqual(c.year, 2024)
        XCTAssertEqual(c.month, 1)
        XCTAssertEqual(c.day, 1)
        XCTAssertEqual(c.hour, 0)
    }

    func testWithoutDPrefix() throws {
        XCTAssertNotNil(PDFDate.parse("20240115103000Z"))
    }

    func testMalformedReturnsNil() {
        XCTAssertNil(PDFDate.parse(""))
        XCTAssertNil(PDFDate.parse("D:"))
        XCTAssertNil(PDFDate.parse("D:abcd"))
        XCTAssertNil(PDFDate.parse("garbage"))
    }
}
