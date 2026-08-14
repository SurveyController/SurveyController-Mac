// 对标 wjx/provider/answering_builders.py
// v0.1 简化说明（后续版本补齐）：信度倾向(tendency)、分布收敛(distribution)、
// 人设加权(persona)、严格比例(strict_ratio)、反填(reverse_fill)、AI 填空为恒等/禁用路径。

import Foundation

public enum WjxAnswerBuilder {

    /// 对标 build_answer_action。
    public static func buildAnswerAction(
        _ question: SurveyQuestionMeta,
        state: inout ExecutionState,
        threadName: String = "",
        rng: RandomSource = SystemRandomSource()
    ) throws -> AnswerAction? {
        guard let configEntry = state.config.questionConfigIndexMap[question.num] else {
            return nil
        }
        let config = state.config
        let (entryType, configIndex) = configEntry

        switch entryType {
        case "single":
            return try buildSingleAction(question, configIndex, state: &state, rng: rng)
        case "multiple":
            return try buildMultipleAction(question, configIndex, state: &state, rng: rng)
        case "dropdown":
            return try buildDropdownAction(question, configIndex, state: &state, rng: rng)
        case "text", "multi_text":
            return buildTextAction(question, configIndex, config: config, rng: rng)
        case "location":
            return nil
        case "matrix":
            return try buildMatrixAction(question, configIndex, config: config, rng: rng)
        case "scale":
            return try buildScoreLikeAction(question, configIndex, config: config, answerType: "scale", rng: rng)
        case "score":
            return try buildScoreLikeAction(question, configIndex, config: config, answerType: "score", rng: rng)
        case "slider":
            return buildSliderAction(question, configIndex, config: config)
        case "order":
            return buildOrderAction(question, rng: rng)
        default:
            return nil
        }
    }

    static func runtimeOptionTexts(_ question: SurveyQuestionMeta) -> [String] {
        question.optionTexts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 对标 _build_wjx_single_action。
    static func buildSingleAction(
        _ question: SurveyQuestionMeta, _ configIndex: Int,
        state: inout ExecutionState,
        rng: RandomSource
    ) throws -> AnswerAction? {
        let config = state.config
        let current = question.num
        let optionTexts = runtimeOptionTexts(question)
        let optionCount = max(1, optionTexts.count != 0 ? optionTexts.count : question.options)

        var forcedIndex = AnswerProbabilities.validForcedChoiceIndex(question.forcedOptionIndex, optionCount: optionCount)
        if forcedIndex == nil {
            forcedIndex = ConsistencyRules.singleLikeConstraint(
                config.answerRules, questionNum: current, answeredChoices: state.answeredChoices
            ).flatMap { AnswerProbabilities.validForcedChoiceIndex($0, optionCount: optionCount) }
        }

        let selectedIndex: Int
        if let forcedIndex {
            selectedIndex = forcedIndex
        } else {
            let probabilities = AnswerProbabilities.normalizeDroplistProbs(
                configIndex < config.singleProb.count ? config.singleProb[configIndex] : -1,
                optionCount: optionCount
            )
            selectedIndex = rng.weightedIndex(probabilities)
        }

        state.recordChoice(questionNum: current, indices: [selectedIndex])

        let selectedText = selectedIndex < optionTexts.count ? optionTexts[selectedIndex] : ""
        let fillEntries = configIndex < config.singleOptionFillTexts.count ? config.singleOptionFillTexts[configIndex] : nil
        var fillValue = AnswerProbabilities.resolveStaticOptionFillText(fillEntries, optionIndex: selectedIndex, question: question)
        fillValue = AnswerProbabilities.defaultMissingOptionFill(question, optionIndex: selectedIndex, fillValue: fillValue)

        let combined: String
        if !selectedText.isEmpty, let fillValue, !fillValue.isEmpty {
            combined = "\(selectedText) / \(fillValue)"
        } else if let fillValue, !fillValue.isEmpty {
            combined = fillValue
        } else {
            combined = selectedText
        }

        return AnswerAction(
            questionNum: current,
            kind: "choice",
            inputType: "radio",
            selectedIndices: [selectedIndex],
            optionFillTexts: (fillValue ?? "").isEmpty ? [] : [(selectedIndex, fillValue!)],
            selectedTexts: [combined.isEmpty ? defaultFillText : combined],
            recordType: "single"
        )
    }

    /// 对标 _build_wjx_dropdown_action。
    static func buildDropdownAction(
        _ question: SurveyQuestionMeta, _ configIndex: Int,
        state: inout ExecutionState,
        rng: RandomSource
    ) throws -> AnswerAction? {
        let config = state.config
        let current = question.num
        let optionTexts = runtimeOptionTexts(question)
        let optionCount = max(1, optionTexts.count != 0 ? optionTexts.count : question.options)

        var forcedIndex = AnswerProbabilities.validForcedChoiceIndex(question.forcedOptionIndex, optionCount: optionCount)
        if forcedIndex == nil {
            forcedIndex = ConsistencyRules.singleLikeConstraint(
                config.answerRules, questionNum: current, answeredChoices: state.answeredChoices
            ).flatMap { AnswerProbabilities.validForcedChoiceIndex($0, optionCount: optionCount) }
        }

        let selectedIndex: Int
        if let forcedIndex {
            selectedIndex = forcedIndex
        } else {
            let probabilities = AnswerProbabilities.normalizeDroplistProbs(
                configIndex < config.droplistProb.count ? config.droplistProb[configIndex] : -1,
                optionCount: optionCount
            )
            selectedIndex = rng.weightedIndex(probabilities)
        }

        state.recordChoice(questionNum: current, indices: [selectedIndex])

        let selectedText = selectedIndex < optionTexts.count ? optionTexts[selectedIndex] : ""
        let fillEntries = configIndex < config.droplistOptionFillTexts.count ? config.droplistOptionFillTexts[configIndex] : nil
        var fillValue = AnswerProbabilities.resolveStaticOptionFillText(fillEntries, optionIndex: selectedIndex, question: question)
        fillValue = AnswerProbabilities.defaultMissingOptionFill(question, optionIndex: selectedIndex, fillValue: fillValue)

        let combined: String
        if !selectedText.isEmpty, let fillValue, !fillValue.isEmpty {
            combined = "\(selectedText) / \(fillValue)"
        } else if let fillValue, !fillValue.isEmpty {
            combined = fillValue
        } else {
            combined = selectedText
        }

        return AnswerAction(
            questionNum: current,
            kind: "select",
            selectedIndices: [selectedIndex],
            optionFillTexts: (fillValue ?? "").isEmpty ? [] : [(selectedIndex, fillValue!)],
            selectedTexts: [combined.isEmpty ? defaultFillText : combined],
            recordType: "dropdown"
        )
    }

    /// 对标 _build_wjx_text_action。
    static func buildTextAction(
        _ question: SurveyQuestionMeta, _ configIndex: Int,
        config: ExecutionConfig,
        rng: RandomSource
    ) -> AnswerAction? {
        let current = question.num
        let blankCount = max(1, question.textInputs)
        let entryType = configIndex < config.textEntryTypes.count ? config.textEntryTypes[configIndex] : "text"

        var textValues = TextValues.resolveValues(
            answerCandidates: configIndex < config.texts.count ? config.texts[configIndex] : nil,
            probabilities: configIndex < config.textsProb.count ? config.textsProb[configIndex] : [1.0],
            blankCount: blankCount,
            entryType: entryType,
            blankModes: configIndex < config.multiTextBlankModes.count ? config.multiTextBlankModes[configIndex] : [],
            blankIntRanges: configIndex < config.multiTextBlankIntRanges.count ? config.multiTextBlankIntRanges[configIndex] : [],
            rng: rng
        )
        if textValues.isEmpty { textValues = [defaultFillText] }

        let finalValues = (0..<blankCount).map { index -> String in
            let value = index < textValues.count ? textValues[index] : (textValues.last ?? defaultFillText)
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? defaultFillText : trimmed
        }
        return AnswerAction(
            questionNum: current,
            kind: "text",
            textValues: finalValues,
            recordType: "text"
        )
    }

    /// 对标 _build_wjx_score_like_action（量表/评分）。
    static func buildScoreLikeAction(
        _ question: SurveyQuestionMeta, _ configIndex: Int,
        config: ExecutionConfig, answerType: String,
        rng: RandomSource
    ) throws -> AnswerAction? {
        let current = question.num
        let optionTexts = runtimeOptionTexts(question)
        let optionCount = max(2, optionTexts.count != 0 ? optionTexts.count : question.options)

        var forcedIndex = AnswerProbabilities.validForcedChoiceIndex(question.forcedOptionIndex, optionCount: optionCount)
        if forcedIndex == nil {
            forcedIndex = ConsistencyRules.singleLikeConstraint(
                config.answerRules, questionNum: current, answeredChoices: [:]
            ).flatMap { AnswerProbabilities.validForcedChoiceIndex($0, optionCount: optionCount) }
        }

        let selectedIndex: Int
        if let forcedIndex {
            selectedIndex = forcedIndex
        } else {
            let probabilities = AnswerProbabilities.normalizeDroplistProbs(
                configIndex < config.scaleProb.count ? config.scaleProb[configIndex] : -1,
                optionCount: optionCount
            )
            selectedIndex = rng.weightedIndex(probabilities)
        }

        let selectedText = selectedIndex < optionTexts.count ? optionTexts[selectedIndex] : ""
        return AnswerAction(
            questionNum: current,
            kind: "choice",
            inputType: "radio",
            selectedIndices: [selectedIndex],
            selectedTexts: [selectedText],
            recordType: answerType
        )
    }

    /// 对标 _build_wjx_multiple_action。
    static func buildMultipleAction(
        _ question: SurveyQuestionMeta, _ configIndex: Int,
        state: inout ExecutionState,
        rng: RandomSource
    ) throws -> AnswerAction? {
        let config = state.config
        let current = question.num
        let optionTexts = runtimeOptionTexts(question)
        let optionCount = max(1, optionTexts.count != 0 ? optionTexts.count : question.options)
        let rawMinRequired = max(1, min(AnswerProbabilities.coercePositiveInt(question.multiMinLimit, default: 1), optionCount))
        let rawMaxAllowed = max(1, min(AnswerProbabilities.coercePositiveInt(question.multiMaxLimit, default: optionCount), optionCount))
        let minRequired = min(rawMinRequired, rawMaxAllowed)
        let maxAllowed = rawMaxAllowed

        let constraint = ConsistencyRules.multipleConstraint(config.answerRules, questionNum: current, optionCount: optionCount)
        let requiredIndices = AnswerProbabilities.normalizeSelectedIndices(constraint.mustSelect, optionCount: optionCount)
        let blockedIndices = AnswerProbabilities.normalizeSelectedIndices(constraint.mustNotSelect, optionCount: optionCount)

        func finalize(_ selectedIndices: [Int]) -> AnswerAction? {
            let selected = AnswerProbabilities.normalizeSelectedIndices(selectedIndices, optionCount: optionCount)
            if selected.isEmpty { return nil }
            let fillEntries = configIndex < config.multipleOptionFillTexts.count
                ? config.multipleOptionFillTexts[configIndex] : nil
            var fillTexts: [(Int, String)] = []
            var selectedTexts: [String] = []
            for optionIdx in selected {
                var selectedText = optionIdx < optionTexts.count ? optionTexts[optionIdx] : ""
                var fillValue = AnswerProbabilities.resolveStaticOptionFillText(fillEntries, optionIndex: optionIdx, question: question)
                fillValue = AnswerProbabilities.defaultMissingOptionFill(question, optionIndex: optionIdx, fillValue: fillValue)
                if let fillValue, !fillValue.isEmpty {
                    fillTexts.append((optionIdx, fillValue))
                    selectedText = selectedText.isEmpty ? fillValue : "\(selectedText) / \(fillValue)"
                }
                selectedTexts.append(selectedText)
            }
            return AnswerAction(
                questionNum: current,
                kind: "choice",
                inputType: "checkbox",
                selectedIndices: selected,
                optionFillTexts: fillTexts,
                selectedTexts: selectedTexts,
                recordType: "multiple"
            )
        }

        let rawProbabilities = configIndex < config.multipleProb.count ? config.multipleProb[configIndex] : nil
        let isUnset: Bool
        if let number = rawProbabilities as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            isUnset = number.doubleValue == -1
        } else if let list = rawProbabilities as? [Any] {
            isUnset = list.count == 1 && JSONCoercion.asInt(list[0]) == -1
        } else {
            isUnset = rawProbabilities == nil
        }

        if isUnset {
            // 未配置：随机数量 + 随机组合（避开禁选与必选）
            let availablePool = (0..<optionCount).filter { !blockedIndices.contains($0) && !requiredIndices.contains($0) }
            var minTotal = max(minRequired, requiredIndices.count)
            let maxTotal = min(maxAllowed, requiredIndices.count + availablePool.count)
            if minTotal > maxTotal { minTotal = maxTotal }
            let extraMin = max(0, minTotal - requiredIndices.count)
            let extraMax = max(0, maxTotal - requiredIndices.count)
            let extraCount = extraMax >= extraMin ? rng.nextInt(lower: extraMin, upper: extraMax) : 0
            let sampled = extraCount > 0 ? rng.sample(availablePool, count: extraCount) : []
            let result = finalize(requiredIndices + sampled)
            if let result {
                state.recordChoice(questionNum: current, indices: Set(result.selectedIndices))
            }
            return result
        }

        // 已配置概率：逐项伯努利
        var sanitized: [Double] = []
        if let list = rawProbabilities as? [Any] {
            for rawProb in list {
                var value = JSONCoercion.asDouble(rawProb, default: 0)
                if value.isNaN || value.isInfinite { value = 0 }
                sanitized.append(min(100, max(0, value)))
            }
        }
        if sanitized.count < optionCount {
            sanitized.append(contentsOf: [Double](repeating: 0, count: optionCount - sanitized.count))
        } else if sanitized.count > optionCount {
            sanitized = Array(sanitized.prefix(optionCount))
        }

        let blockedSet = Set(blockedIndices)
        let requiredSet = Set(requiredIndices)
        for index in 0..<sanitized.count where blockedSet.contains(index) || requiredSet.contains(index) {
            sanitized[index] = 0
        }

        let positiveIndices = (0..<optionCount).filter { sanitized[$0] > 0 }
        if positiveIndices.isEmpty && requiredIndices.isEmpty { return nil }

        var selectionMask = [Int](repeating: 0, count: optionCount)
        var attempts = 0
        let maxAttempts = 32
        if !positiveIndices.isEmpty {
            while selectionMask.reduce(0, +) == 0 && attempts < maxAttempts {
                for index in 0..<optionCount {
                    selectionMask[index] = rng.chance(sanitized[index] / 100.0) ? 1 : 0
                }
                attempts += 1
            }
            if selectionMask.reduce(0, +) == 0 {
                selectionMask = [Int](repeating: 0, count: optionCount)
                if let chosen = rng.choice(positiveIndices) {
                    selectionMask[chosen] = 1
                }
            }
        }

        var selected = (0..<optionCount).filter { selectionMask[$0] == 1 && sanitized[$0] > 0 }
        selected = AnswerProbabilities.normalizeSelectedIndices(requiredIndices + selected, optionCount: optionCount)
        if selected.count < minRequired {
            var missing = positiveIndices.filter { !selected.contains($0) && !blockedSet.contains($0) }
            while selected.count < minRequired && !missing.isEmpty {
                selected.append(missing.removeFirst())
            }
        }
        selected = Array(selected.prefix(maxAllowed))

        let result = finalize(selected)
        if let result {
            state.recordChoice(questionNum: current, indices: Set(result.selectedIndices))
        }
        return result
    }

    /// 对标 _build_wjx_matrix_action。
    static func buildMatrixAction(
        _ question: SurveyQuestionMeta, _ configIndex: Int,
        config: ExecutionConfig,
        rng: RandomSource
    ) throws -> AnswerAction? {
        let current = question.num
        let rowCount = max(1, question.rows)
        let optionCount = max(2, question.optionTexts.count != 0 ? question.optionTexts.count : question.options)

        var selectedIndices: [Int] = []
        var nextIndex = configIndex
        for _ in 0..<rowCount {
            let rowRaw = nextIndex < config.matrixProb.count ? config.matrixProb[nextIndex] : -1
            let rowProbabilities = AnswerProbabilities.normalizeDroplistProbs(rowRaw, optionCount: optionCount)
            selectedIndices.append(rng.weightedIndex(rowProbabilities))
            nextIndex += 1
        }
        return AnswerAction(
            questionNum: current,
            kind: "matrix",
            matrixIndices: selectedIndices,
            recordType: "matrix"
        )
    }

    /// 对标 _build_wjx_slider_action。
    static func buildSliderAction(
        _ question: SurveyQuestionMeta, _ configIndex: Int,
        config: ExecutionConfig
    ) -> AnswerAction? {
        var targetValue = 50.0
        if configIndex < config.sliderTargets.count {
            targetValue = config.sliderTargets[configIndex]
        }
        // 对标：滑块值夹紧到题目声明的范围
        if let minValue = doubleOrNil(question.sliderMin), let maxValue = doubleOrNil(question.sliderMax) {
            targetValue = min(max(targetValue, minValue), maxValue)
        }
        return AnswerAction(
            questionNum: question.num,
            kind: "slider",
            sliderValue: targetValue,
            recordType: "slider"
        )
    }

    /// 对标 _build_wjx_order_action：全选项随机排序。
    static func buildOrderAction(
        _ question: SurveyQuestionMeta,
        rng: RandomSource
    ) -> AnswerAction? {
        let optionTexts = runtimeOptionTexts(question)
        let optionCount = max(1, optionTexts.count != 0 ? optionTexts.count : question.options)
        var orderedIndices = Array(0..<optionCount)
        for index in (1..<orderedIndices.count).reversed() {
            let j = rng.nextInt(lower: 0, upper: index)
            orderedIndices.swapAt(index, j)
        }
        return AnswerAction(
            questionNum: question.num,
            kind: "order",
            selectedIndices: orderedIndices,
            selectedTexts: orderedIndices.compactMap { $0 < optionTexts.count ? optionTexts[$0] : nil },
            recordType: "order"
        )
    }

    static func doubleOrNil(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.doubleValue
        }
        if let text = value as? String { return Double(text) }
        return nil
    }
}
