import Foundation

enum PsychometricPlan {
    private struct Item {
        let key: QuestionOptionKey
        let probabilities: [Double]
        let ordinal: [Int]

        var mean: Double {
            probabilities.enumerated().reduce(0) { $0 + Double($1.offset) * $1.element } / Double(max(1, probabilities.count - 1))
        }
    }

    static func build(
        _ config: ExecutionConfig,
        rng: RandomSource = SystemRandomSource(),
        shouldStop: () -> Bool = { false }
    ) -> [QuestionOptionKey: [Int]] {
        let count = max(1, config.targetNum)
        var plan: [QuestionOptionKey: [Int]] = [:]
        var groups: [String: [Item]] = [:]
        for question in config.questionsOrdered {
            if shouldStop() { return [:] }
            guard let entry = config.questionConfigIndexMap[question.num], question.forcedOptionIndex == nil else { continue }
            let dimension = config.questionDimensions[question.num]
            let strict = config.strictRatioQuestions.contains(question.num)
            guard strict || dimension != nil else { continue }
            let optionCount = question.optionTexts.isEmpty ? question.options : question.optionTexts.count
            guard optionCount >= 2 else { continue }
            let rows: [Int?] = entry.entryType == "matrix" ? (0..<max(1, question.rows)).map(Optional.some) : [nil]
            for row in rows {
                let source: [Any]
                switch entry.entryType {
                case "single": source = config.singleProb
                case "dropdown": source = config.droplistProb
                case "score", "scale": source = config.scaleProb
                case "matrix": source = config.matrixProb
                default: continue
                }
                let index = entry.configIndex + (row ?? 0)
                let weights = AnswerProbabilities.normalizeDroplistProbs(source.indices.contains(index) ? source[index] : -1, optionCount: optionCount)
                let ordinal = orderedChoices(question.optionTexts, count: optionCount)
                let key = QuestionOptionKey(question: question.num, row: row)
                let item = Item(key: key, probabilities: ordinal.map { weights[$0] }, ordinal: ordinal)
                if let dimension {
                    groups[dimension, default: []].append(item)
                } else {
                    let values = zip(ordinal, AnswerSelection.quotas(item.probabilities, count: count))
                        .flatMap { repeatElement($0.0, count: $0.1) }
                    plan[key] = rng.sample(values, count: values.count)
                }
            }
        }
        for dimension in groups.keys.sorted() {
            if shouldStop() { return [:] }
            guard let items = groups[dimension], !items.isEmpty else { continue }
            let selected = optimize(items, count: count, target: config.targetAlpha, rng: rng, shouldStop: shouldStop)
            plan.merge(selected, uniquingKeysWith: { first, _ in first })
        }
        return plan
    }

    private static func orderedChoices(_ labels: [String], count: Int) -> [Int] {
        let numeric = labels.map { label in
            let cleaned = label.replacingOccurrences(of: #"[分点级星]$"#, with: "", options: .regularExpression)
            return Int(cleaned.trimmingCharacters(in: .whitespacesAndNewlines))
        }.compactMap { $0 }
        if numeric.count == count, Set(numeric).count == count {
            return numeric.indices.sorted { numeric[$0] < numeric[$1] }
        }
        let groups = [
            ["非常不同意", "不同意", "一般", "同意", "非常同意"],
            ["非常不满意", "不满意", "一般", "满意", "非常满意"],
            ["非常不符合", "不符合", "一般", "符合", "非常符合"],
            ["从不", "很少", "有时", "经常", "总是"],
        ]
        for group in groups {
            let ranks = labels.compactMap(group.firstIndex(of:))
            if ranks.count == count, Set(ranks).count == count {
                return ranks.indices.sorted { ranks[$0] < ranks[$1] }
            }
        }
        return Array(0..<count)
    }

    private static func optimize(
        _ items: [Item], count: Int, target: Double, rng: RandomSource, shouldStop: () -> Bool
    ) -> [QuestionOptionKey: [Int]] {
        let theta = (0..<count).map { _ in rng.gauss(0, 1) }
        let noise = items.map { _ in (0..<count).map { _ in rng.gauss(0, 1) } }
        let jitter = items.map { _ in (0..<count).map { _ in rng.gauss(0, 0.03) } }
        let left = items.reduce(0) { $0 + ($1.mean < 0.4 ? 0.5 - $1.mean : 0) }
        let right = items.reduce(0) { $0 + ($1.mean > 0.6 ? $1.mean - 0.5 : 0) }
        let anchor = max(left, right) >= 0.2 && max(left, right) > min(left, right) * 1.15
            ? (left > right ? -1 : 1) : 0
        let reversed = items.map { (anchor < 0 && $0.mean > 0.6) || (anchor > 0 && $0.mean < 0.4) }
        let quotas = items.map { AnswerSelection.quotas($0.probabilities, count: count) }
        let numItems = Double(items.count)
        let rho = target / (numItems - target * (numItems - 1))
        let sigma = sqrt(max(0, 1 / rho - 1))
        var best: [QuestionOptionKey: [Int]] = [:]
        var fit = Double.infinity
        var bestSigma = sigma
        var sigmas = [1.5, 1.2, 1.0, 0.8, 0.6, 0.4, 0.2].map { $0 * sigma } + [0.1, 0.05]
        for pass in 0..<2 {
            for candidate in sigmas {
                if shouldStop() { return [:] }
                var totals = [Double](repeating: 0, count: count)
                var itemVariance = 0.0
                var result: [QuestionOptionKey: [Int]] = [:]
                for (index, item) in items.enumerated() {
                    let sign = reversed[index] ? -1.0 : 1.0
                    let scores = theta.indices.map { sign * theta[$0] + candidate * noise[index][$0] + jitter[index][$0] }
                    let ranked = scores.indices.sorted { scores[$0] == scores[$1] ? $0 < $1 : scores[$0] < scores[$1] }
                    let choices = quotas[index].enumerated().flatMap { repeatElement($0.offset, count: $0.element) }
                    var assigned = [Int](repeating: 0, count: count)
                    var ordinalScores = [Double](repeating: 0, count: count)
                    for (sample, choice) in zip(ranked, choices) {
                        assigned[sample] = item.ordinal[choice]
                        ordinalScores[sample] = Double(reversed[index] ? item.ordinal.count - choice : choice + 1)
                        totals[sample] += ordinalScores[sample]
                    }
                    itemVariance += variance(ordinalScores)
                    result[item.key] = assigned
                }
                let totalVariance = variance(totals)
                let alpha = numItems > 1 && totalVariance > 0 ? numItems / (numItems - 1) * (1 - itemVariance / totalVariance) : 0
                let distance = abs(alpha - target)
                if distance < fit {
                    fit = distance
                    best = result
                    bestSigma = candidate
                }
            }
            if pass == 0 { sigmas = [0.87, 0.94, 1.06, 1.13].map { bestSigma * $0 } }
        }
        return best
    }

    private static func variance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
    }
}
