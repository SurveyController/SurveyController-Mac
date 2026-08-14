// 对标桌面端 ui/widgets/ratio_slider.py + 安卓端 ui/components/RatioSliders.kt 的联动算法
// 拖动任一项：其余未锁定项按原比例分摊，总和恒 100%；锁定项不变；5% 步进吸附。

import Foundation

public enum RatioSliderMath {

    /// 拖动第 changed 项到 newValueRaw 后重分配（对标安卓 redistribute）。
    /// - 改动项上限 = 100 - 锁定额度
    /// - 未锁定且非自身的项按原比例分摊剩余；全为 0 时均分
    /// - 整数舍入误差补到第一个可调整项
    public static func redistribute(
        _ current: [Int], changed: Int, newValueRaw: Int, locked: Set<Int> = []
    ) -> [Int] {
        let n = current.count
        guard n > 0 else { return current }
        guard n > 1 else { return [100] }

        let lockedSum = (0..<n).filter { locked.contains($0) && $0 != changed }
            .reduce(0) { $0 + current[$1] }
        let maxForChanged = max(0, 100 - lockedSum)
        let newValue = min(max(0, newValueRaw), maxForChanged)

        var values = current
        values[changed] = newValue

        let freeIdx = (0..<n).filter { $0 != changed && !locked.contains($0) }
        guard !freeIdx.isEmpty else {
            // 没有可调整项：差额补回改动项
            values[changed] = maxForChanged
            return values
        }

        let remaining = max(0, 100 - lockedSum - newValue)
        let freeSum = freeIdx.reduce(0) { $0 + current[$1] }
        if freeSum > 0 {
            for k in freeIdx {
                values[k] = Int(Double(remaining) * Double(current[k]) / Double(freeSum))
            }
        } else {
            let each = remaining / freeIdx.count
            for (j, k) in freeIdx.enumerated() {
                values[k] = j == freeIdx.count - 1
                    ? remaining - each * (freeIdx.count - 1)
                    : each
            }
        }

        let total = values.reduce(0, +)
        if total != 100 {
            let first = freeIdx[0]
            values[first] = max(0, values[first] + (100 - total))
        }
        return values
    }

    /// 任意权重展示归一化为总和 100（对标安卓 normalizeTo100）。
    public static func normalizeTo100(_ values: [Int]) -> [Int] {
        let n = values.count
        guard n > 0 else { return values }
        let total = values.reduce(0, +)
        var result: [Int]
        if total == 100 {
            return values
        } else if total > 0 {
            result = values.map { Int(Double($0) * 100.0 / Double(total)) }
        } else {
            let each = 100 / n
            result = (0..<n).map { $0 < n - 1 ? each : 100 - each * (n - 1) }
        }
        let diff = 100 - result.reduce(0, +)
        if diff != 0 {
            result[0] = max(0, result[0] + diff)
        }
        return result
    }

    /// 均分（首项补差）。
    public static func evenSplit(_ n: Int) -> [Int] {
        guard n > 0 else { return [] }
        let each = 100 / n
        return (0..<n).map { $0 < n - 1 ? each : 100 - each * (n - 1) }
    }

    /// 吸附到最近的 step% 刻度（默认 5%）。
    public static func roundToStep(_ value: Double, step: Int = 5) -> Int {
        let snapped = (value / Double(step)).rounded() * Double(step)
        return min(100, max(0, Int(snapped)))
    }
}
