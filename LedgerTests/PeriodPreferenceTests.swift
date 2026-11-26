import XCTest
import Foundation
@testable import Ledger

final class PeriodPreferenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ledger.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveAndLoadMonth() {
        let range = PeriodRange(kind: .month, anchor: Date())
        PeriodPreference.save(range: range, defaults: defaults)

        let loaded = PeriodPreference.load(defaults: defaults)
        XCTAssertEqual(loaded?.kind, PeriodKind.month)
        XCTAssertEqual(loaded?.customStart, nil)
    }

    func testCustomRangeRoundTrip() {
        let start = Date().addingTimeInterval(-86400 * 10)
        let end = Date()
        let range = PeriodRange(kind: .custom, anchor: Date(), customStart: start, customEnd: end)
        PeriodPreference.save(range: range, defaults: defaults)

        let loaded = PeriodPreference.load(defaults: defaults)
        XCTAssertEqual(loaded?.kind, PeriodKind.custom)
        XCTAssertEqual(loaded?.customStart, start)
        XCTAssertEqual(loaded?.customEnd, end)
    }

    func testInvalidKindReturnsNil() {
        let preference = PeriodPreference(range: PeriodRange(kind: .week))
        var broken = preference
        broken.kindRaw = "not-a-kind"
        let data = try! JSONEncoder().encode(broken)
        defaults.set(data, forKey: PeriodPreference.storageKey)

        XCTAssertNil(PeriodPreference.load(defaults: defaults))
    }

    func testEmptyDefaultsReturnsNil() {
        XCTAssertNil(PeriodPreference.load(defaults: defaults))
    }
}
