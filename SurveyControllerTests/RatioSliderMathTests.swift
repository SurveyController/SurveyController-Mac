// 对标安卓端 ui/RatioSlidersTest.kt —— 联动滑杆算法的行为规格

import XCTest
@testable import SurveyController

final class RatioSliderMathTests: XCTestCase {

    // redistribute_keeps_total_100
    func test_redistribute_keeps_total_100() {
        let result = RatioSliderMath.redistribute([40, 30, 30], changed: 0, newValueRaw: 70)
        XCTAssertEqual(result.reduce(0, +), 100)
        XCTAssertEqual(result[0], 70)
        // 剩余 30 按原比例（30:30）分给另外两项
        XCTAssertEqual(result[1] + result[2], 30)
    }

    // redistribute_handles_zero_others
    func test_redistribute_handles_zero_others() {
        // 其余项全 0 时按均分补足
        let result = RatioSliderMath.redistribute([100, 0, 0], changed: 0, newValueRaw: 50)
        XCTAssertEqual(result.reduce(0, +), 100)
        XCTAssertEqual(result[0], 50)
        XCTAssertEqual(result[1] + result[2], 50)
    }

    // normalize_to_100_from_uniform_weights
    func test_normalize_to_100_from_uniform_weights() {
        let result = RatioSliderMath.normalizeTo100([25, 25, 25, 25])
        XCTAssertEqual(result, [25, 25, 25, 25])
        XCTAssertEqual(result.reduce(0, +), 100)

        let arbitrary = RatioSliderMath.normalizeTo100([1, 2, 3])
        XCTAssertEqual(arbitrary.reduce(0, +), 100)
    }

    // single_option_is_100
    func test_single_option_is_100() {
        XCTAssertEqual(RatioSliderMath.redistribute([100], changed: 0, newValueRaw: 30), [100])
        XCTAssertEqual(RatioSliderMath.normalizeTo100([42]), [100])
    }

    // locked_item_stays_fixed
    func test_locked_item_stays_fixed() {
        let current = [30, 40, 30]
        let result = RatioSliderMath.redistribute(current, changed: 0, newValueRaw: 50, locked: [1])
        XCTAssertEqual(result[1], 40, "锁定项必须保持不变")
        XCTAssertEqual(result.reduce(0, +), 100)
    }

    // changed_capped_by_locked_budget
    func test_changed_capped_by_locked_budget() {
        // 锁定项占 40 → 改动项最高只能到 60
        let result = RatioSliderMath.redistribute([20, 40, 40], changed: 0, newValueRaw: 90, locked: [1])
        XCTAssertLessThanOrEqual(result[0], 60, "改动项不得超过 100 - 锁定额度")
        XCTAssertEqual(result[1], 40)
        XCTAssertEqual(result.reduce(0, +), 100)
    }

    // 补充：拖到 0 与拖满
    func test_extremes() {
        let zero = RatioSliderMath.redistribute([50, 50], changed: 0, newValueRaw: 0)
        XCTAssertEqual(zero, [0, 100])

        let full = RatioSliderMath.redistribute([50, 50], changed: 0, newValueRaw: 100)
        XCTAssertEqual(full, [100, 0])
    }

    // evenSplit
    func test_even_split() {
        XCTAssertEqual(RatioSliderMath.evenSplit(4), [25, 25, 25, 25])
        XCTAssertEqual(RatioSliderMath.evenSplit(3).reduce(0, +), 100)
        // 不能整除时首项补差保持总和
        XCTAssertEqual(RatioSliderMath.evenSplit(3), [33, 33, 34])
    }

    // roundToStep 5% 吸附
    func test_round_to_step() {
        XCTAssertEqual(RatioSliderMath.roundToStep(12.4), 10)
        XCTAssertEqual(RatioSliderMath.roundToStep(12.6), 15)
        XCTAssertEqual(RatioSliderMath.roundToStep(-3), 0)
        XCTAssertEqual(RatioSliderMath.roundToStep(104), 100)
    }
}
