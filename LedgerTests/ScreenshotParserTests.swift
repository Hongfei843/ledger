import XCTest
import UIKit
@testable import Ledger

final class ScreenshotParserTests: XCTestCase {
    private func line(_ text: String, _ height: CGFloat = 0.02) -> OCRLine {
        OCRLine(text: text, height: height)
    }

    /// 取字号最大的金额，而不是第一个出现的
    func testPicksLargestAmount() {
        let lines = [
            line("付款成功", 0.03),
            line("余额 ¥1,234.56", 0.02),
            line("¥38.00", 0.06)
        ]
        XCTAssertEqual(ScreenshotParser.parse(lines: lines).amountMinor, 3800)
    }

    /// 余额、可用额度这类行要排除
    func testNoiseExcluded() {
        let lines = [
            line("可用额度 ¥50,000.00", 0.07),
            line("支付成功 ¥12.50", 0.03)
        ]
        XCTAssertEqual(ScreenshotParser.parse(lines: lines).amountMinor, 1250)
    }

    func testPayeeInline() {
        let lines = [line("收款方：星巴克"), line("¥25.00", 0.06)]
        XCTAssertEqual(ScreenshotParser.parse(lines: lines).payee, "星巴克")
    }

    func testPayeeNextLine() {
        let lines = [line("收款方"), line("瑞幸咖啡"), line("¥9.90", 0.06)]
        XCTAssertEqual(ScreenshotParser.parse(lines: lines).payee, "瑞幸咖啡")
    }

    func testAmountFormats() {
        XCTAssertEqual(ScreenshotParser.firstAmount(in: "¥0.05"), 5)
        XCTAssertEqual(ScreenshotParser.firstAmount(in: "¥1,234.5"), 123450)
        XCTAssertEqual(ScreenshotParser.firstAmount(in: "合计 38 元"), 3800)
        XCTAssertNil(ScreenshotParser.firstAmount(in: "没有数字"))
    }

    func testConfidenceHigherWithPayeeAndSuccess() {
        let rich = [
            line("付款成功", 0.03),
            line("¥38.00", 0.06),
            line("收款方：星巴克")
        ]
        let poor = [line("¥38.00", 0.06)]
        XCTAssertGreaterThan(
            ScreenshotParser.parse(lines: rich).confidence,
            ScreenshotParser.parse(lines: poor).confidence
        )
    }
}
