import Foundation

struct QuestionOptionKey: Hashable, Sendable {
    let question: Int
    let row: Int?
}

struct AnswerSelectionSample: Sendable {
    let index: Int
    let planned: [QuestionOptionKey: Int]
    let observations: [QuestionOptionKey: [Int: Int]]
    let persona: AnswerPersona
}

struct AnswerPersona: Sendable {
    let keywords: [String]

    static func generate(_ random: RandomSource) -> Self {
        let gender = random.chance(0.5) ? ["男", "男性", "先生", "男生"] : ["女", "女性", "女士", "女生"]
        let age = random.weightedIndex([35, 35, 20, 10])
        let ranges = [18...25, 26...35, 36...45, 46...60]
        let range = ranges[age]
        let education = [
            ["高中", "初中", "中专", "职高", "小学", "中学"],
            ["大专", "专科", "高职"],
            ["本科", "大学", "学士"],
            ["研究生", "硕士", "博士"],
        ][random.weightedIndex([[15, 20, 50, 15], [10, 20, 45, 25], [10, 20, 45, 25], [25, 25, 35, 15]][age])]
        let work = random.weightedIndex([[55, 35, 10, 0], [0, 75, 25, 0], [0, 75, 25, 0], [0, 50, 25, 25]][age])
        let occupations = [
            ["学生", "在校", "在读", "校园"],
            ["上班", "在职", "企业", "公司", "职员", "白领", "员工", "工作"],
            ["自由职业", "自由", "个体", "创业", "自营", "个体户"],
            ["退休", "离退休"],
        ]
        let incomeWeights: [Double] = switch work {
        case 0: [85, 15, 0]
        case 3: [30, 50, 20]
        default: [[40, 45, 15], [20, 50, 30], [15, 45, 40], [15, 45, 40]][age]
        }
        let income = [
            ["3000以下", "3000元以下", "5000以下", "5000元以下", "低收入", "无收入", "2000以下"],
            ["5000-10000", "5000~10000", "5001-10000", "10000-20000", "10000~20000", "万元", "中等收入", "1万", "一万"],
            ["20000以上", "20000元以上", "2万以上", "3万以上", "50000以上", "高收入", "5万"],
        ][random.weightedIndex(incomeWeights)]
        let single = random.chance([0.9, 0.45, 0.15, 0.1][age])
        let marital = single ? ["未婚", "单身", "恋爱"] : ["已婚", "已婚已育", "已婚未育", "结婚"]
        let children = random.chance(single ? 0.03 : [0.10, 0.50, 0.90, 0.90][age])
            ? ["有孩子", "有子女", "已育", "有小孩"]
            : ["无子女", "无孩子", "未育", "没有孩子", "没有小孩"]
        let ageWords = [
            ["大学", "青年", "18岁", "20岁"], ["青年", "中青年", "30岁"],
            ["中年", "40岁"], ["中年", "中老年", "50岁"],
        ][age]
        var keywords = gender
        keywords.append(contentsOf: range.map(String.init))
        keywords.append("\(range.lowerBound)-\(range.upperBound)")
        keywords.append("\(range.lowerBound)~\(range.upperBound)")
        for group in [ageWords, education, occupations[work], income, marital, children] {
            keywords.append(contentsOf: group)
        }
        return Self(keywords: keywords)
    }

    func boost(_ weights: [Double], labels: [String]) -> [Double] {
        weights.enumerated().map { index, value in
            guard labels.indices.contains(index), keywords.contains(where: labels[index].contains) else { return value }
            return value * 3
        }
    }
}

actor AnswerSelectionRuntime {
    private let planned: [QuestionOptionKey: [Int]]
    private var observations: [QuestionOptionKey: [Int: Int]] = [:]
    private var available: [Int] = []
    private var next = 0

    init(plan: [QuestionOptionKey: [Int]]) { planned = plan }

    func reserve(rng: RandomSource) -> AnswerSelectionSample {
        let index: Int
        if let reused = available.popLast() {
            index = reused
        } else {
            index = next
            next += 1
        }
        return AnswerSelectionSample(
            index: index,
            planned: planned.compactMapValues { $0.indices.contains(index) ? $0[index] : nil },
            observations: observations,
            persona: AnswerPersona.generate(rng)
        )
    }

    func release(_ index: Int) { available.append(index) }

    func record(_ actions: [AnswerAction]) {
        for action in actions {
            if action.kind == "matrix" {
                for (row, choice) in action.matrixIndices.enumerated() {
                    observations[QuestionOptionKey(question: action.questionNum, row: row), default: [:]][choice, default: 0] += 1
                }
            } else if ["choice", "select", "scale", "score"].contains(action.kind) {
                for choice in action.selectedIndices {
                    observations[QuestionOptionKey(question: action.questionNum, row: nil), default: [:]][choice, default: 0] += 1
                }
            }
        }
    }
}

enum AnswerSelection {
    static func adjusted(_ weights: [Double], observed: [Int: Int], reliability: Bool) -> [Double] {
        let target = normalize(weights)
        let total = observed.values.reduce(0, +)
        guard total > 0 else { return target }
        let (warmup, gain, minimum, maximum, gapLimit) = reliability
            ? (14.0, 1.75, 0.80, 1.28, 0.28)
            : (12.0, 4.2, 0.45, 2.2, 0.42)
        let factor = min(1, Double(total) / warmup)
        let adjusted = target.enumerated().map { index, value in
            let gap = max(-gapLimit, min(gapLimit, value - Double(observed[index, default: 0]) / Double(total)))
            return value * max(minimum, min(maximum, exp(gain * factor * gap)))
        }
        return normalize(adjusted)
    }

    static func normalize(_ values: [Double]) -> [Double] {
        let weights = values.map { $0.isFinite ? max(0, $0) : 0 }
        let total = weights.reduce(0, +)
        guard !weights.isEmpty else { return [] }
        return total > 0 ? weights.map { $0 / total } : weights.map { _ in 1 / Double(weights.count) }
    }

    static func quotas(_ target: [Double], count: Int) -> [Int] {
        let values = normalize(target)
        let precise = values.map { $0 * Double(count) }
        var integers = precise.map { Int($0.rounded(.down)) }
        let ordered = values.indices.sorted { left, right in
            let l = precise[left] - Double(integers[left])
            let r = precise[right] - Double(integers[right])
            if l != r { return l > r }
            if values[left] != values[right] { return values[left] > values[right] }
            return left < right
        }
        for index in ordered.prefix(max(0, count - integers.reduce(0, +))) { integers[index] += 1 }
        return integers
    }

    static func choose(
        _ weights: [Double], labels: [String], question: Int, row: Int? = nil,
        state: ExecutionState, rng: RandomSource
    ) -> Int {
        let key = QuestionOptionKey(question: question, row: row)
        if let choice = state.answerSelection?.planned[key], weights.indices.contains(choice) { return choice }
        let strict = state.config.strictRatioQuestions.contains(question)
        let reliability = state.config.questionDimensions[question] != nil
        let personaWeights = strict ? weights : state.answerSelection?.persona.boost(weights, labels: labels) ?? weights
        let probabilities = strict || reliability
            ? adjusted(personaWeights, observed: state.answerSelection?.observations[key] ?? [:], reliability: reliability)
            : personaWeights
        return rng.weightedIndex(probabilities)
    }

    static func strictMultiple(
        _ weights: [Double],
        question: Int,
        requiredCount: Int,
        lower: Int,
        upper: Int,
        state: ExecutionState,
        rng: RandomSource
    ) -> [Int] {
        var pool = weights.indices.filter { weights[$0] > 0 }
        let expectation = weights.reduce(0, +) / 100
        let whole = Int(expectation.rounded(.down))
        let count = min(max(0, upper - requiredCount), max(max(0, lower - requiredCount), whole + (rng.chance(expectation - Double(whole)) ? 1 : 0)))
        let key = QuestionOptionKey(question: question, row: nil)
        let adjustedWeights = adjusted(weights, observed: state.answerSelection?.observations[key] ?? [:], reliability: false)
        var selected: [Int] = []
        for _ in 0..<min(pool.count, count) {
            selected.append(pool.remove(at: rng.weightedIndex(pool.map { adjustedWeights[$0] })))
        }
        return selected
    }
}
