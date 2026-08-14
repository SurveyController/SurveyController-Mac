// 对标 software/core/modes/duration_control.py（采样部分）
// 作答时长采样：等长区间 ±20% 抖动，否则高斯分布，最后夹紧。

import Foundation

public enum AnswerDurationSampler {
    /// 对标 has_configured_answer_duration。
    public static func hasConfiguredAnswerDuration(_ range: (Int, Int)) -> Bool {
        max(0, range.0, range.1) > 0
    }

    /// 对标 sample_answer_duration_seconds。
    public static func sampleSeconds(
        _ answerDurationRangeSeconds: (Int, Int) = (0, 0),
        surveyProvider: String? = nil,
        defaultUnconfiguredSeconds: Int = 0,
        rng: RandomSource = SystemRandomSource()
    ) -> Double {
        var rawMin = answerDurationRangeSeconds.0
        var rawMax = answerDurationRangeSeconds.1
        if !hasConfiguredAnswerDuration(answerDurationRangeSeconds) {
            if defaultUnconfiguredSeconds <= 0 { return 0.0 }
            rawMin = defaultUnconfiguredSeconds
            rawMax = defaultUnconfiguredSeconds
        }

        var minDelay = max(0, rawMin)
        let maxDelay = max(minDelay, rawMax)

        if minDelay == maxDelay {
            let base = maxDelay
            let jitter = max(5, Int(Double(base) * 0.2))
            minDelay = max(0, base - jitter)
            // 对标：max_delay = base + jitter（重开区间后再算 center/std）
            let reopenedMax = base + jitter
            let center = Double(minDelay + reopenedMax) / 2.0
            let stdDev = reopenedMax > minDelay ? Double(reopenedMax - minDelay) / 6.0 : 0.0
            let waitSeconds = stdDev > 0 ? rng.gauss(center, stdDev) : Double(minDelay)
            return max(Double(minDelay), min(Double(reopenedMax), waitSeconds))
        }

        let center = Double(minDelay + maxDelay) / 2.0
        let stdDev = maxDelay > minDelay ? Double(maxDelay - minDelay) / 6.0 : 0.0
        let waitSeconds = stdDev > 0 ? rng.gauss(center, stdDev) : Double(minDelay)
        return max(Double(minDelay), min(Double(maxDelay), waitSeconds))
    }
}
