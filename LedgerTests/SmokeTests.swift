import XCTest
@testable import Ledger

/// 临时冒烟测试：验证测试 target 能在云端跑起来。
final class SmokeTests: XCTestCase {
    func testSmoke() {
        XCTAssertEqual(1 + 1, 2)
    }
}
