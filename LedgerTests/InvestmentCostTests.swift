import XCTest
@testable import Ledger

final class InvestmentCostTests: XCTestCase {
    func testContributionIncreasesCost() {
        XCTAssertEqual(InvestmentService.costAfterContribution(current: nil, amount: 10_000), 10_000)
        XCTAssertEqual(InvestmentService.costAfterContribution(current: 5_000, amount: 3_000), 8_000)
    }

    func testWithdrawalReducesCostWithoutGoingNegative() {
        XCTAssertEqual(InvestmentService.costAfterWithdrawal(current: nil, amount: 1_000), 0)
        XCTAssertEqual(InvestmentService.costAfterWithdrawal(current: 8_000, amount: 3_000), 5_000)
        XCTAssertEqual(InvestmentService.costAfterWithdrawal(current: 2_000, amount: 5_000), 0)
    }
}
