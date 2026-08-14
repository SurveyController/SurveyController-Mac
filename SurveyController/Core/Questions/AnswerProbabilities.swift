// 对标 software/core/questions/utils.py（概率部分）+ providers/answering/selection.py
//        + providers/answering/option_fill.py + wjx/provider/questions/multiple_rules.py

import Foundation

public let optionFillAiToken = "__AI_FILL__"

public enum AnswerProbabilities {

    /// 对标 normalize_probabilities：按总和归一（总和≤0 时抛错）。
    public static func normalize(_ values: [Double]) throws -> [Double] {
        guard !values.isEmpty else {
            throw NSError(domain: "AnswerProbabilities", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "概率列表不能为空"])
        }
        let total = values.reduce(0, +)
        guard total > 0 else {
            throw NSError(domain: "AnswerProbabilities", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "概率列表的和必须大于0"])
        }
        return values.map { $0 / total }
    }

    /// 对标 normalize_droplist_probs：-1/None → 均匀；列表补齐/截断后归一。
    public static func normalizeDroplistProbs(_ probConfig: Any?, optionCount: Int) -> [Double] {
        if optionCount <= 0 { return [] }
        let isUnset: Bool
        if probConfig == nil || probConfig is NSNull {
            isUnset = true
        } else if let number = probConfig as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            isUnset = number.doubleValue == -1
        } else if let text = probConfig as? String {
            isUnset = text == "-1"
        } else {
            isUnset = false
        }
        if isUnset {
            let uniform = [Double](repeating: 1.0, count: optionCount)
            return (try? normalize(uniform)) ?? [1.0 / Double(optionCount)]
        }

        var base: [Double]
        if let list = probConfig as? [Any] {
            base = list.map { item -> Double in
                if item is NSNull { return 0 }
                if let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                    return max(0, number.doubleValue)
                }
                if let text = item as? String { return max(0, Double(text) ?? 0) }
                return 0
            }
        } else if let number = probConfig as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            base = [number.doubleValue]
        } else {
            base = []
        }
        if base.count < optionCount {
            base.append(contentsOf: [Double](repeating: 0, count: optionCount - base.count))
        } else if base.count > optionCount {
            base = Array(base.prefix(optionCount))
        }
        let total = base.reduce(0, +)
        if total > 0 { return base.map { $0 / total } }
        return [Double](repeating: 1.0 / Double(optionCount), count: optionCount)
    }

    /// 对标 coerce_positive_int。
    public static func coercePositiveInt(_ value: Any?, default defaultValue: Int) -> Int {
        max(0, JSONCoercion.asInt(value, default: defaultValue))
    }

    /// 对标 valid_forced_choice_index。
    public static func validForcedChoiceIndex(_ rawValue: Any?, optionCount: Int) -> Int? {
        guard let candidate = intOrNull(rawValue) else { return nil }
        return (0..<optionCount).contains(candidate) ? candidate : nil
    }

    static func intOrNull(_ value: Any?) -> Int? {
        guard let value, !(value is NSNull) else { return nil }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.intValue
        }
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// 对标 _normalize_selected_indices：去重、去越界、保持原顺序。
    public static func normalizeSelectedIndices(_ indices: [Int], optionCount: Int) -> [Int] {
        var normalized: [Int] = []
        var seen: Set<Int> = []
        for index in indices {
            if seen.contains(index) { continue }
            if index < 0 || index >= optionCount { continue }
            seen.insert(index)
            normalized.append(index)
        }
        return normalized
    }

    /// 对标 option_requires_fill。
    public static func optionRequiresFill(_ question: SurveyQuestionMeta, optionIndex: Int) -> Bool {
        question.fillableOptions.contains { $0 == optionIndex }
    }

    /// 对标 default_missing_option_fill。
    public static func defaultMissingOptionFill(
        _ question: SurveyQuestionMeta, optionIndex: Int, fillValue: String?
    ) -> String? {
        let trimmed = (fillValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if optionRequiresFill(question, optionIndex: optionIndex) { return defaultFillText }
        return nil
    }

    /// 对标 get_fill_text_from_config。
    public static func getFillTextFromConfig(_ fillEntries: [Any?]?, optionIndex: Int) -> String? {
        guard let fillEntries, optionIndex >= 0, optionIndex < fillEntries.count else { return nil }
        let value = fillEntries[optionIndex]
        if value == nil || value is NSNull { return nil }
        let text = JSONCoercion.asTrimmedString(value)
        return text.isEmpty ? nil : text
    }

    /// 对标 resolve_static_option_fill_text：AI token 回落默认文本。
    public static func resolveStaticOptionFillText(
        _ fillEntries: [Any?]?, optionIndex: Int, question: SurveyQuestionMeta
    ) -> String? {
        guard let rawValue = getFillTextFromConfig(fillEntries, optionIndex: optionIndex) else {
            return defaultMissingOptionFill(question, optionIndex: optionIndex, fillValue: nil)
        }
        if rawValue.isEmpty {
            return defaultMissingOptionFill(question, optionIndex: optionIndex, fillValue: nil)
        }
        if rawValue == optionFillAiToken {
            return defaultFillText
        }
        return TextValues.resolveDynamicTextToken(rawValue)
    }
}
