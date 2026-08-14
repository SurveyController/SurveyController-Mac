// 对标 Python random 模块的可注入用法（rng=random.Random(seed)）。
// 协议抽象便于测试注入确定性随机源。

import Foundation

/// 可注入随机源（全项目统一使用，不要直接调 SystemRandomNumberGenerator）。
public protocol RandomSource: Sendable {
    /// [0, 1) 均匀随机数，对标 random.random()。
    func nextDouble() -> Double
    /// [lower, upper] 闭区间整数，对标 random.randint(lower, upper)。
    func nextInt(lower: Int, upper: Int) -> Int
}

extension RandomSource {
    /// 对标 random.random() < p 的伯努利试验。
    public func chance(_ probability: Double) -> Bool {
        nextDouble() < probability
    }

    /// 对标 random.choices(items, weights=weights, k=1)[0]：轮盘赌加权选择。
    /// 权重全非正时返回 nil。
    public func weightedChoice<T>(_ items: [T], weights: [Double]) -> T? {
        guard items.count == weights.count, !items.isEmpty else { return nil }
        let positive = weights.map { max(0, $0) }
        let total = positive.reduce(0, +)
        guard total > 0 else { return nil }
        var roll = nextDouble() * total
        for (index, weight) in positive.enumerated() {
            roll -= weight
            if roll < 0 { return items[index] }
        }
        return items.last
    }

    /// 对标 core/questions/utils.py weighted_index：轮盘赌取下标，总量非正时均匀。
    public func weightedIndex(_ probabilities: [Double]) -> Int {
        guard !probabilities.isEmpty else { return 0 }
        let positive = probabilities.map { max(0, $0) }
        let total = positive.reduce(0, +)
        if total <= 0 { return nextInt(lower: 0, upper: probabilities.count - 1) }
        var roll = nextDouble() * total
        for (index, probability) in positive.enumerated() {
            roll -= probability
            if roll < 0 { return index }
        }
        return probabilities.count - 1
    }

    /// 对标 random.uniform(a, b)。
    public func uniform(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * nextDouble()
    }

    /// 对标 random.gauss(mu, sigma)（Box-Muller）。
    public func gauss(_ mu: Double, _ sigma: Double) -> Double {
        let u1 = max(nextDouble(), Double.leastNonzeroMagnitude)
        let u2 = nextDouble()
        let magnitude = (-2 * log(u1)).squareRoot()
        let z0 = magnitude * cos(2 * .pi * u2)
        return mu + sigma * z0
    }

    /// 对标 random.sample(population, k)：不放回抽样。
    public func sample<T>(_ population: [T], count k: Int) -> [T] {
        guard k > 0, !population.isEmpty else { return [] }
        let take = min(k, population.count)
        var pool = population
        var result: [T] = []
        result.reserveCapacity(take)
        for i in 0..<take {
            let j = nextInt(lower: i, upper: pool.count - 1)
            pool.swapAt(i, j)
            result.append(pool[i])
        }
        return result
    }

    /// 对标 random.choice(seq)。
    public func choice<T>(_ items: [T]) -> T? {
        guard !items.isEmpty else { return nil }
        return items[nextInt(lower: 0, upper: items.count - 1)]
    }
}

/// 系统随机源。
public struct SystemRandomSource: RandomSource {
    public init() {}

    public func nextDouble() -> Double {
        Double.random(in: 0..<1)
    }

    public func nextInt(lower: Int, upper: Int) -> Int {
        precondition(lower <= upper, "nextInt 要求 lower <= upper")
        return Int.random(in: lower...upper)
    }
}

/// 可复现随机源（引用类型：实例内维护 xorshift64* 序列，对标 random.Random 实例）。
public final class SeededRandomSource: RandomSource, @unchecked Sendable {
    private var state: UInt64
    private let lock = NSLock()

    public init(seed: UInt64) {
        // 种子为 0 时会退化，固定替换
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    public convenience init(seed: Int) {
        self.init(seed: UInt64(bitPattern: Int64(seed)))
    }

    private func nextRaw() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        var x = state
        x ^= x >> 12
        x ^= x << 25
        x ^= x >> 27
        state = x
        return x &* 0x2545F4914F6CDD1D
    }

    public func nextDouble() -> Double {
        Double(nextRaw() >> 11) * (1.0 / 9007199254740992.0)
    }

    public func nextInt(lower: Int, upper: Int) -> Int {
        precondition(lower <= upper, "nextInt 要求 lower <= upper")
        let span = UInt64(upper - lower + 1)
        return lower + Int(nextRaw() % span)
    }
}
