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

    func testTransfersAdjustDerivedCost() {
        let account = Account(bookId: UUID(), name: "基金", type: .investment)
        account.positionCostMinor = 10_000
        let other = UUID()
        let inflow = Txn(bookId: UUID(), type: .transfer, amountMinor: 5_000, accountId: other, counterAccountId: account.id)
        let outflow = Txn(bookId: UUID(), type: .transfer, amountMinor: 2_000, accountId: account.id, counterAccountId: other)

        let position = InvestmentService.position(for: account, txns: [inflow, outflow])
        XCTAssertEqual(position?.costMinor, 13_000)
        XCTAssertEqual(position?.valueMinor, 3_000)
        XCTAssertEqual(position?.profitMinor, -10_000)
    }
}
