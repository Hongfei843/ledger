import XCTest
import Foundation
@testable import Ledger

final class LoanCalculatorTests: XCTestCase {
    private let calendar = AppCalendar.gregorian
    private var firstDue: Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 15
        return calendar.date(from: comps) ?? Date()
    }

    /// 等额本息：本金合计必须精确等于合同本金
    func testEqualInstallmentPrincipalSumsExactly() {
        let schedule = LoanCalculator.schedule(
            principalMinor: 100_000_000, // 100 万
            annualRateBp: 420,           // 4.2%
            termMonths: 360,
            method: .equalInstallment,
            firstDueDate: firstDue
        )

        XCTAssertEqual(schedule.count, 360)
        let principalSum = schedule.reduce(Int64(0)) { $0 + $1.principalMinor }
        XCTAssertEqual(principalSum, 100_000_000, "本金合计必须精确等于合同本金")

        // 月供约 4890 元，允许 ±2% 误差
        let monthly = schedule[0].totalMinor
        XCTAssertGreaterThan(monthly, 480_000)
        XCTAssertLessThan(monthly, 500_000)

        // 首期利息应为 剩余本金 × 4.2%/12 ≈ 3500 元
        XCTAssertEqual(Double(schedule[0].interestMinor), 350_000, accuracy: 100)
    }

    func testEqualPrincipal() {
        let schedule = LoanCalculator.schedule(
            principalMinor: 12_000_00,
            annualRateBp: 600,
            termMonths: 12,
            method: .equalPrincipal,
            firstDueDate: firstDue
        )
        XCTAssertEqual(schedule.count, 12)
        XCTAssertEqual(schedule.reduce(Int64(0)) { $0 + $1.principalMinor }, 12_000_00)
        // 等额本金：利息逐月递减
        XCTAssertGreaterThan(schedule[0].interestMinor, schedule[11].interestMinor)
    }

    /// 先息后本：前 n-1 期只还利息，最后一期还本
    func testInterestOnly() {
        let schedule = LoanCalculator.schedule(
            principalMinor: 10_000_00,
            annualRateBp: 1200, // 12%
            termMonths: 12,
            method: .interestOnly,
            firstDueDate: firstDue
        )
        XCTAssertEqual(schedule.count, 12)
        for item in schedule.dropLast() {
            XCTAssertEqual(item.principalMinor, 0)
            XCTAssertEqual(item.interestMinor, 10_000)
        }
        XCTAssertEqual(schedule[11].principalMinor, 10_000_00)
    }

    /// IRR：借 12000 分 12 期每期 1080，实际年化约 15.4%
    /// 校验思路：总还款 12960，月利率约 1.2%，1.012^12 - 1 ≈ 15.4%
    func testEffectiveAnnualRate() {
        guard let annual = LoanCalculator.effectiveAnnualRate(
            principalMinor: 12_000_00,
            termMonths: 12,
            paymentMinor: 1_080_00
        ) else {
            return XCTFail("IRR 未收敛")
        }
        XCTAssertGreaterThan(annual, 0.14)
        XCTAssertLessThan(annual, 0.17)
    }

    /// 零利率不应崩溃
    func testZeroRate() {
        let schedule = LoanCalculator.schedule(
            principalMinor: 1_200_00,
            annualRateBp: 0,
            termMonths: 12,
            method: .equalInstallment,
            firstDueDate: firstDue
        )
        XCTAssertEqual(schedule.count, 12)
        XCTAssertEqual(schedule.reduce(Int64(0)) { $0 + $1.principalMinor }, 1_200_00)
        XCTAssertEqual(schedule[0].interestMinor, 0)
    }

    /// 提前还款：缩短期限后总利息必须下降
    func testPrepaymentSavesInterest() {
        let original = LoanCalculator.schedule(
            principalMinor: 100_000_000,
            annualRateBp: 420,
            termMonths: 360,
            method: .equalInstallment,
            firstDueDate: firstDue
        )
        let remaining = Array(original.dropFirst(60))
        let outstandingBefore = remaining.reduce(Int64(0)) { $0 + $1.principalMinor }
        // 真实提前还款：先还掉 10 万本金
        let prepay: Int64 = 10_000_000
        let outstanding = outstandingBefore - prepay

        let updated = LoanCalculator.reschedule(
            outstandingMinor: outstanding,
            annualRateBp: 420,
            remainingMonths: 300,
            originalMonthlyPaymentMinor: original[0].totalMinor,
            method: .equalInstallment,
            firstDueDate: firstDue,
            strategy: .shortenTerm
        )

        XCTAssertFalse(updated.isEmpty)
        XCTAssertLessThan(updated.count, 300, "缩期后剩余期数应减少")
        XCTAssertGreaterThan(LoanCalculator.savedInterest(original: remaining, updated: updated), 0)
        XCTAssertEqual(updated.reduce(Int64(0)) { $0 + $1.principalMinor }, outstanding)
    }
}
