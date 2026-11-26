import XCTest
import Foundation
@testable import Ledger

final class PaymentMethodDetectorTests: XCTestCase {
    func testBankDebitCardWithTail() {
        let result = PaymentMethodDetector.detect(texts: [
            "付款成功",
            "中信银行储蓄卡1368",
            "¥35.00"
        ])
        XCTAssertEqual(result?.bankId, "citic")
        XCTAssertEqual(result?.accountType, .debit)
        XCTAssertEqual(result?.cardTail, "1368")
        XCTAssertEqual(result?.displayName, "中信银行 ··1368")
        XCTAssertEqual(result?.suggestedAccountName, "中信银行储蓄卡 1368")
    }

    func testCreditCardWithLabeledTail() {
        let result = PaymentMethodDetector.detect(texts: [
            "招商银行信用卡",
            "尾号 8888",
            "支付成功"
        ])
        XCTAssertEqual(result?.bankId, "cmb")
        XCTAssertEqual(result?.accountType, .credit)
        XCTAssertEqual(result?.cardTail, "8888")
    }

    func testAlipayPlatform() {
        let result = PaymentMethodDetector.detect(texts: ["支付宝余额宝", "付款成功 ¥20.00"])
        XCTAssertEqual(result?.bankId, "alipay")
        XCTAssertEqual(result?.accountType, .ewallet)
    }

    func testHuabeiIsBnpl() {
        let result = PaymentMethodDetector.detect(texts: ["花呗", "支付成功"])
        XCTAssertEqual(result?.bankId, "huabei")
        XCTAssertEqual(result?.accountType, .bnpl)
    }

    func testNoPaymentInfoReturnsNil() {
        XCTAssertNil(PaymentMethodDetector.detect(texts: ["收款方：星巴克", "¥35.00", "交易成功"]))
    }
}

final class CategorySeedTests: XCTestCase {
    func testExpenseCategoryNamesUniqueAndSplitUtilities() {
        let names = SeedData.expenseCategories.map { $0.name }
        XCTAssertEqual(names.count, Set(names).count, "支出分类不能重名")
        XCTAssertTrue(names.contains("水费"))
        XCTAssertTrue(names.contains("电费"))
        XCTAssertTrue(names.contains("燃气费"))
        XCTAssertFalse(names.contains("水电燃气"))
        XCTAssertFalse(names.contains("买菜"))
        XCTAssertFalse(names.contains("零食"))
        XCTAssertFalse(names.contains("外卖"))
        XCTAssertGreaterThanOrEqual(names.count, 26)
    }

    func testIncomeCategoryNamesUnique() {
        let names = SeedData.incomeCategories.map { $0.name }
        XCTAssertEqual(names.count, Set(names).count, "收入分类不能重名")
        XCTAssertTrue(names.contains("工资"))
        XCTAssertTrue(names.contains("利息收入"))
        XCTAssertLessThanOrEqual(names.count, 12)
    }
}
