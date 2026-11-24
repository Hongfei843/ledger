import XCTest
@testable import Ledger

final class MoneyTests: XCTestCase {
    func testFormat() {
        XCTAssertEqual(Money.format(123456), "¥1,234.56")
        XCTAssertEqual(Money.format(0), "¥0.00")
        XCTAssertEqual(Money.format(-500), "-¥5.00")
        XCTAssertEqual(Money.format(5), "¥0.05")
        XCTAssertEqual(Money.format(100000000), "¥1,000,000.00")
    }

    func testFormatPlain() {
        XCTAssertEqual(Money.formatPlain(123456), "1,234.56")
        XCTAssertEqual(Money.formatPlain(-500), "-5.00")
    }

    func testParse() {
        XCTAssertEqual(Money.parse("¥1,234.56"), 123456)
        XCTAssertEqual(Money.parse("1234"), 123400)
        XCTAssertEqual(Money.parse("0.05"), 5)
        XCTAssertEqual(Money.parse("-5.00"), -500)
        XCTAssertNil(Money.parse("abc"))
        XCTAssertNil(Money.parse(""))
    }

    func testRoundTrip() {
        let values: [Int64] = [0, 1, 99, 100, 123456, 999999999]
        for value in values {
            XCTAssertEqual(Money.parse(Money.format(value)), value, "round trip failed for \(value)")
        }
    }

    func testRounding() {
        XCTAssertEqual(Money.minor(Decimal(string: "1.005")!), 101)
        XCTAssertEqual(Money.minor(Decimal(string: "1.004")!), 100)
    }
}
