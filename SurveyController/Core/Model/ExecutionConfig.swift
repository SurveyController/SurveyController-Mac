// 对标 software/core/task/task_context.py（ExecutionConfig）+ questions/normalization.py（概率编译）
// 运行时展开配置：把 question_entries 编译成按题型分组的扁平概率数组 + 题号索引映射。

import Foundation

/// 题号 → (配置类型, 该类型数组中的下标)。
public typealias QuestionConfigEntry = (entryType: String, configIndex: Int)

/// 运行时展开配置（对标 ExecutionConfig，v0.1 子集）。
public struct ExecutionConfig: @unchecked Sendable {
    public var url: String = ""
    public var surveyProvider: SurveyProvider = .wjx
    public var targetNum: Int = 1
    public var numThreads: Int = 1
    public var stopOnFailEnabled: Bool = true
    public var failThreshold: Int = 5
    public var submitIntervalRangeSeconds: (Int, Int) = (0, 0)
    public var answerDurationRangeSeconds: (Int, Int) = (60, 120)
    public var randomProxyIpEnabled: Bool = false
    public var proxySource: String = "default"
    public var customProxyApi: String = ""
    public var proxyAreaCode: String?
    public var randomUserAgentEnabled: Bool = false
    public var userAgentRatios: [String: Int] = ["wechat": 33, "mobile": 33, "pc": 34]
    public var answerRules: [[String: Any]] = []

    // 概率与文本数组（按配置下标索引）
    public var singleProb: [Any] = []              // 元素：[Double] 或 -1
    public var droplistProb: [Any] = []
    public var multipleProb: [Any] = []            // 元素：[Double]（每项 0-100 概率）
    public var matrixProb: [Any] = []              // 元素：[[Double]]（每行）
    public var scaleProb: [Any] = []
    public var sliderTargets: [Double] = []
    public var texts: [[String]] = []
    public var textsProb: [[Double]] = []
    public var textEntryTypes: [String] = []
    public var textAiFlags: [Bool] = []
    public var multiTextBlankModes: [[String]] = []
    public var multiTextBlankIntRanges: [[[Int]]] = []
    public var singleOptionFillTexts: [[Any?]?] = []
    public var droplistOptionFillTexts: [[Any?]?] = []
    public var multipleOptionFillTexts: [[Any?]?] = []

    // 映射
    public var questionConfigIndexMap: [Int: QuestionConfigEntry] = [:]
    public var questionsMetadata: [Int: SurveyQuestionMeta] = [:]
    public var questionsOrdered: [SurveyQuestionMeta] = []
}

/// 对标 android 端 ConfigCompiler（compile(draft) → ExecutionConfig）。
public enum ExecutionConfigBuilder {

    /// 从 RuntimeConfig 构建运行时配置。
    public static func build(from config: RuntimeConfig) -> ExecutionConfig {
        var execution = ExecutionConfig()
        execution.url = config.url
        execution.surveyProvider = config.surveyProvider
        execution.targetNum = max(1, config.target)
        execution.numThreads = max(1, config.threads)
        execution.stopOnFailEnabled = config.failStopEnabled
        execution.submitIntervalRangeSeconds = config.submitInterval
        execution.answerDurationRangeSeconds = config.answerDuration
        execution.randomProxyIpEnabled = config.randomIpEnabled
        execution.proxySource = config.proxySource
        execution.customProxyApi = config.customProxyApi
        execution.proxyAreaCode = config.proxyAreaCode
        execution.randomUserAgentEnabled = config.randomUaEnabled
        execution.userAgentRatios = config.randomUaRatios
        execution.answerRules = config.answerRules

        // 题目元数据按（页, 题号）排序
        execution.questionsOrdered = config.questionsInfo
            .filter { $0.num > 0 }
            .sorted { lhs, rhs in
                (lhs.page, lhs.num) < (rhs.page, rhs.num)
            }
        for question in execution.questionsOrdered {
            execution.questionsMetadata[question.num] = question
        }

        for entry in config.questionEntries {
            guard let questionNum = entry.questionNum, questionNum > 0 else { continue }
            let entryType = normalizedEntryType(entry)
            let configIndex: Int

            switch entryType {
            case "single":
                configIndex = execution.singleProb.count
                execution.singleProb.append(asProbList(entry.probabilities))
                execution.singleOptionFillTexts.append(entry.optionFillTexts ?? nil)
            case "dropdown":
                configIndex = execution.droplistProb.count
                execution.droplistProb.append(asProbList(entry.probabilities))
                execution.droplistOptionFillTexts.append(entry.optionFillTexts ?? nil)
            case "multiple":
                configIndex = execution.multipleProb.count
                execution.multipleProb.append(asProbList(entry.probabilities))
                execution.multipleOptionFillTexts.append(entry.optionFillTexts ?? nil)
            case "matrix":
                // 矩阵：每行一个概率数组，configIndex 指向首行
                configIndex = execution.matrixProb.count
                let rows = max(1, entry.rows)
                let rawProbabilities = asNestedProbList(entry.probabilities)
                if rawProbabilities.count >= rows {
                    for row in rawProbabilities.prefix(rows) {
                        execution.matrixProb.append(row)
                    }
                } else {
                    for _ in 0..<rows {
                        execution.matrixProb.append(rawProbabilities.first ?? [])
                    }
                }
            case "scale", "score":
                configIndex = execution.scaleProb.count
                execution.scaleProb.append(asProbList(entry.probabilities))
            case "slider":
                configIndex = execution.sliderTargets.count
                let target = asDoubleFirst(entry.probabilities) ?? 50.0
                execution.sliderTargets.append(target)
            case "text", "multi_text":
                configIndex = execution.texts.count
                execution.texts.append(entry.texts ?? [])
                execution.textsProb.append(asDoubleList(entry.probabilities))
                execution.textEntryTypes.append(entryType)
                execution.textAiFlags.append(entry.aiEnabled)
                execution.multiTextBlankModes.append(entry.multiTextBlankModes)
                execution.multiTextBlankIntRanges.append(entry.multiTextBlankIntRanges)
            case "location", "order":
                configIndex = 0
            default:
                configIndex = 0
            }
            execution.questionConfigIndexMap[questionNum] = (entryType, configIndex)
        }
        return execution
    }

    static func normalizedEntryType(_ entry: QuestionEntry) -> String {
        // text / multi_text 由配置创建时写入 question_type（对标桌面端向导产物），此处不做推断
        entry.questionType
    }

    static func asProbList(_ value: Any?) -> Any {
        if let list = value as? [Any] {
            return list.compactMap { item -> Double? in
                if let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                    return number.doubleValue
                }
                if let text = item as? String { return Double(text) }
                return nil
            }
        }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return [number.doubleValue]
        }
        return -1
    }

    static func asNestedProbList(_ value: Any?) -> [[Double]] {
        guard let list = value as? [Any] else { return [] }
        return list.map { row in
            (row as? [Any])?.compactMap { item -> Double? in
                if let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                    return number.doubleValue
                }
                if let text = item as? String { return Double(text) }
                return nil
            } ?? []
        }
    }

    static func asDoubleList(_ value: Any?) -> [Double] {
        guard let list = value as? [Any] else { return [] }
        return list.compactMap { item -> Double? in
            if let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                return number.doubleValue
            }
            if let text = item as? String { return Double(text) }
            return nil
        }
    }

    static func asDoubleFirst(_ value: Any?) -> Double? {
        asDoubleList(value).first
    }
}
