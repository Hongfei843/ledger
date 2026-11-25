import XCTest
@testable import Ledger

final class CategoryMatcherTests: XCTestCase {
    private let bookId = UUID()

    private func categories() -> [Category] {
        ["餐饮", "交通", "购物", "居住", "通讯", "娱乐", "医疗", "教育", "人情", "旅行", "宠物", "订阅服务", "手续费", "税费", "其他"]
            .map { Category(bookId: bookId, name: $0, kind: .expense) }
    }

    func testExactNameWins() {
        let pool = categories()
        let matched = CategoryMatcher.match(name: "交通", kind: .expense, categories: pool)
        XCTAssertEqual(matched?.name, "交通")
    }

    func testKeywordMapping() {
        let pool = categories()
        XCTAssertEqual(CategoryMatcher.match(name: "咖啡奶茶", kind: .expense, categories: pool)?.name, "餐饮")
        XCTAssertEqual(CategoryMatcher.match(name: "App 订阅", kind: .expense, categories: pool)?.name, "订阅服务")
        XCTAssertEqual(CategoryMatcher.match(name: "电费", kind: .expense, categories: pool)?.name, "居住")
        XCTAssertEqual(CategoryMatcher.match(name: "打车", kind: .expense, categories: pool)?.name, "交通")
    }

    func testUnknownFallsBackToOther() {
        let pool = categories()
        let matched = CategoryMatcher.match(name: "某个不存在的分类", kind: .expense, categories: pool)
        XCTAssertEqual(matched?.name, "其他")
    }

    func testIncomeMapping() {
        let pool = [
            Category(bookId: bookId, name: "工资", kind: .income),
            Category(bookId: bookId, name: "奖金", kind: .income),
            Category(bookId: bookId, name: "其他", kind: .income)
        ]
        XCTAssertEqual(CategoryMatcher.match(name: "月薪", kind: .income, categories: pool)?.name, "工资")
        XCTAssertEqual(CategoryMatcher.match(name: "年终奖", kind: .income, categories: pool)?.name, "奖金")
    }

    func testDoesNotCrossKind() {
        let pool = [
            Category(bookId: bookId, name: "餐饮", kind: .expense),
            Category(bookId: bookId, name: "其他", kind: .income)
        ]
        // 支出名不能匹配到收入分类
        let matched = CategoryMatcher.match(name: "餐饮", kind: .income, categories: pool)
        XCTAssertEqual(matched?.name, "其他")
    }
}
