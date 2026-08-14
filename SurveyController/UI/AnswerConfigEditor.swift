// 对标官方题目配置向导（ui/question_editor/wizard_dialog.py）的 Mac 简化版：
// 左题目列表 + 右编辑器；单选/量表=权重滑杆，多选=命中概率滑杆，矩阵=按行权重，填空=候选文本与随机模式。

import SwiftUI

struct AnswerConfigEditor: View {
    @Bindable var model: AppModel

    var body: some View {
        HSplitView {
            questionList
                .frame(minWidth: 240, idealWidth: 280)
            editorPane
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 题目列表

    private var questionList: some View {
        List(selection: $model.selectedQuestionIndex) {
            ForEach(Array(model.runtimeConfig.questionsInfo.enumerated()), id: \.offset) { index, question in
                HStack(spacing: 8) {
                    Text("\(question.displayNum ?? question.num)")
                        .monospacedDigit()
                        .frame(width: 26, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Text(entryLabel(question))
                        .font(.caption)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    Text(question.title)
                        .lineLimit(1)
                    Spacer()
                    if question.required {
                        Image(systemName: "asterisk")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .tag(index)
            }
        }
        .listStyle(.sidebar)
    }

    private func entryLabel(_ question: SurveyQuestionMeta) -> String {
        let type = DefaultQuestionEntries.entryType(for: question)
        return ["single": "单选", "multiple": "多选", "scale": "量表", "score": "评分",
                "matrix": "矩阵", "dropdown": "下拉", "slider": "滑块", "order": "排序",
                "text": "填空", "multi_text": "多空", "location": "地区", "unsupported": "不支持"][type] ?? type
    }

    // MARK: - 编辑器

    @ViewBuilder
    private var editorPane: some View {
        let questions = model.runtimeConfig.questionsInfo
        if model.selectedQuestionIndex >= questions.count {
            ContentUnavailableView("选择左侧题目", systemImage: "sidebar.leading",
                                   description: Text("在左侧选择一道题来调整作答分布"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let question = questions[model.selectedQuestionIndex]
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("第\(question.displayNum ?? question.num)题 · \(question.title)")
                        .font(.title3.bold())
                    editor(for: question)
                }
                .padding(20)
                .frame(maxWidth: 720, alignment: .leading)
            }
            .id(question.num)
        }
    }

    @ViewBuilder
    private func editor(for question: SurveyQuestionMeta) -> some View {
        let type = DefaultQuestionEntries.entryType(for: question)
        switch type {
        case "single", "dropdown", "scale", "score":
            weightEditor(question, kindLabel: "选项权重（相对比例，运行时归一化）")
        case "multiple":
            probabilityEditor(question)
        case "matrix":
            matrixEditor(question)
        case "slider":
            sliderEditor(question)
        case "text", "multi_text":
            textEditor(question)
        case "order":
            Label("排序题将自动随机排序全部选项", systemImage: "shuffle")
                .foregroundStyle(.secondary)
        case "location":
            Label("地区题暂不支持自动作答", systemImage: "location.slash")
                .foregroundStyle(.secondary)
        default:
            Label("该题型不支持编辑", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 单选/量表/下拉：权重

    private func weightEditor(_ question: SurveyQuestionMeta, kindLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kindLabel).font(.subheadline).foregroundStyle(.secondary)
            ForEach(Array(optionList(question).enumerated()), id: \.offset) { index, option in
                HStack(spacing: 12) {
                    Text(option)
                        .lineLimit(1)
                        .frame(width: 220, alignment: .leading)
                    Slider(value: weightBinding(question, index: index), in: 0...100, step: 1)
                    Text("\(Int(currentWeight(question, index: index)))")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }
            if question.forcedOptionIndex != nil {
                Label("题目要求固定选择「\(question.forcedOptionText)」，权重不生效", systemImage: "pin")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - 多选：每项命中概率

    private func probabilityEditor(_ question: SurveyQuestionMeta) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("各选项独立命中概率（%），同时受题目数量限制约束")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(Array(optionList(question).enumerated()), id: \.offset) { index, option in
                HStack(spacing: 12) {
                    Text(option)
                        .lineLimit(1)
                        .frame(width: 220, alignment: .leading)
                    Slider(value: probabilityBinding(question, index: index), in: 0...100, step: 1)
                    Text("\(Int(currentProbability(question, index: index)))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }
            if let minLimit = intOrNil(question.multiMinLimit), let maxLimit = intOrNil(question.multiMaxLimit) {
                Text("题目限制：最少选 \(minLimit) 项，最多选 \(maxLimit) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 矩阵：按行权重

    private func matrixEditor(_ question: SurveyQuestionMeta) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("按行设置各列权重（切换行编辑，运行时逐行独立抽取）")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("编辑行", selection: Binding(
                get: { min(matrixRow, max(0, question.rows - 1)) },
                set: { matrixRow = $0 }
            )) {
                ForEach(0..<max(1, question.rows), id: \.self) { row in
                    Text(row < question.rowTexts.count && !question.rowTexts[row].isEmpty
                         ? question.rowTexts[row]
                         : "第 \(row + 1) 行").tag(row)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 260)

            let row = min(matrixRow, max(0, question.rows - 1))
            ForEach(Array(optionList(question).enumerated()), id: \.offset) { index, option in
                HStack(spacing: 12) {
                    Text(option)
                        .lineLimit(1)
                        .frame(width: 220, alignment: .leading)
                    Slider(value: matrixWeightBinding(question, row: row, index: index), in: 0...100, step: 1)
                    Text("\(Int(currentMatrixWeight(question, row: row, index: index)))")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @State private var matrixRow = 0

    // MARK: - 滑块

    private func sliderEditor(_ question: SurveyQuestionMeta) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let minValue = doubleOrZero(question.sliderMin, fallback: 0)
            let maxValue = doubleOrZero(question.sliderMax, fallback: 100)
            HStack(spacing: 12) {
                Text("目标值（范围 \(formatValue(minValue)) ~ \(formatValue(maxValue))）")
                    .frame(width: 220, alignment: .leading)
                Slider(value: sliderTargetBinding(question, min: minValue, max: maxValue),
                       in: minValue...maxValue)
                Text(formatValue(currentSliderTarget(question)))
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 填空

    private func textEditor(_ question: SurveyQuestionMeta) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if question.textInputs > 1 {
                Text("多空填空：用 \(multiTextDelimiter) 分隔各空答案（当前 \(question.textInputs) 空）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(0..<min(question.textInputs, question.textInputLabels.count), id: \.self) { blank in
                    let label = blank < question.textInputLabels.count ? question.textInputLabels[blank] : "第\(blank + 1)空"
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("候选答案（多行 = 多个候选，随机抽取）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: textCandidatesBinding(question))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 90)
                .border(Color(nsColor: .separatorColor))

            Picker("随机模式", selection: textModeBinding(question)) {
                Text("固定文本").tag(textRandomNone)
                Text("随机姓名").tag(textRandomName)
                Text("随机手机号").tag(textRandomMobile)
                Text("随机整数").tag(textRandomInteger)
            }
            .pickerStyle(.radioGroup)
            .frame(width: 260)

            HStack(spacing: 8) {
                TextField("随机整数下限", value: $model.textIntMin, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Text("~")
                TextField("随机整数上限", value: $model.textIntMax, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Button("应用整数范围") {
                    applyTextIntRange(question)
                }
            }
        }
    }

    // MARK: - Entry 读写辅助

    private func entryIndex(questionNum: Int) -> Int? {
        model.runtimeConfig.questionEntries.firstIndex { $0.questionNum == questionNum }
    }

    private func optionList(_ question: SurveyQuestionMeta) -> [String] {
        if !question.optionTexts.isEmpty { return question.optionTexts }
        return (0..<max(1, question.options)).map { "选项 \($0 + 1)" }
    }

    private func currentWeights(_ entry: QuestionEntry) -> [Double] {
        guard let list = entry.probabilities as? [Any] else { return [] }
        return list.compactMap { number($0) }
    }

    private func number(_ value: Any) -> Double? {
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private func currentWeight(_ question: SurveyQuestionMeta, index: Int) -> Double {
        guard let entryIndex = entryIndex(questionNum: question.num) else { return 0 }
        let weights = currentWeights(model.runtimeConfig.questionEntries[entryIndex])
        return index < weights.count ? weights[index] : 0
    }

    private func weightBinding(_ question: SurveyQuestionMeta, index: Int) -> Binding<Double> {
        Binding(
            get: { currentWeight(question, index: index) },
            set: { newValue in setFlatProb(question, index: index, value: newValue) }
        )
    }

    private func setFlatProb(_ question: SurveyQuestionMeta, index: Int, value: Double) {
        guard let entryIndex = entryIndex(questionNum: question.num) else { return }
        var weights = currentWeights(model.runtimeConfig.questionEntries[entryIndex])
        let optionCount = optionList(question).count
        if weights.count < optionCount {
            weights.append(contentsOf: [Double](repeating: 0, count: optionCount - weights.count))
        }
        weights[index] = value
        model.runtimeConfig.questionEntries[entryIndex].probabilities = weights
        if model.runtimeConfig.questionEntries[entryIndex].distributionMode == "custom" {
            model.runtimeConfig.questionEntries[entryIndex].customWeights = weights
        }
    }

    private func currentProbability(_ question: SurveyQuestionMeta, index: Int) -> Double {
        currentWeight(question, index: index)
    }

    private func probabilityBinding(_ question: SurveyQuestionMeta, index: Int) -> Binding<Double> {
        weightBinding(question, index: index)
    }

    private func currentMatrixWeight(_ question: SurveyQuestionMeta, row: Int, index: Int) -> Double {
        guard let entryIndex = entryIndex(questionNum: question.num) else { return 0 }
        let entry = model.runtimeConfig.questionEntries[entryIndex]
        guard let nested = entry.probabilities as? [Any],
              row < nested.count,
              let rowList = nested[row] as? [Any] else { return 0 }
        let weights = rowList.compactMap { number($0) }
        return index < weights.count ? weights[index] : 0
    }

    private func matrixWeightBinding(_ question: SurveyQuestionMeta, row: Int, index: Int) -> Binding<Double> {
        Binding(
            get: { currentMatrixWeight(question, row: row, index: index) },
            set: { newValue in
                guard let entryIndex = entryIndex(questionNum: question.num) else { return }
                let optionCount = optionList(question).count
                var nested: [[Double]] = []
                if let raw = model.runtimeConfig.questionEntries[entryIndex].probabilities as? [Any] {
                    nested = raw.map { ($0 as? [Any])?.compactMap { number($0) } ?? [] }
                }
                while nested.count < question.rows {
                    nested.append([Double](repeating: 0, count: optionCount))
                }
                while nested[row].count < optionCount {
                    nested[row].append(0)
                }
                nested[row][index] = newValue
                model.runtimeConfig.questionEntries[entryIndex].probabilities = nested
            }
        )
    }

    private func currentSliderTarget(_ question: SurveyQuestionMeta) -> Double {
        guard let entryIndex = entryIndex(questionNum: question.num),
              let list = model.runtimeConfig.questionEntries[entryIndex].probabilities as? [Any],
              let first = list.compactMap({ number($0) }).first else { return 50 }
        return first
    }

    private func sliderTargetBinding(_ question: SurveyQuestionMeta, min minValue: Double, max maxValue: Double) -> Binding<Double> {
        Binding(
            get: { currentSliderTarget(question) },
            set: { newValue in
                guard let entryIndex = entryIndex(questionNum: question.num) else { return }
                model.runtimeConfig.questionEntries[entryIndex].probabilities = [newValue]
            }
        )
    }

    private func textCandidatesBinding(_ question: SurveyQuestionMeta) -> Binding<String> {
        Binding(
            get: {
                guard let entryIndex = entryIndex(questionNum: question.num),
                      let texts = model.runtimeConfig.questionEntries[entryIndex].texts else { return "" }
                return texts.joined(separator: "\n")
            },
            set: { newValue in
                guard let entryIndex = entryIndex(questionNum: question.num) else { return }
                let lines = newValue.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                model.runtimeConfig.questionEntries[entryIndex].texts = lines.isEmpty ? [defaultFillText] : lines
            }
        )
    }

    private func textModeBinding(_ question: SurveyQuestionMeta) -> Binding<String> {
        Binding(
            get: {
                guard let entryIndex = entryIndex(questionNum: question.num) else { return textRandomNone }
                let entry = model.runtimeConfig.questionEntries[entryIndex]
                if let first = entry.multiTextBlankModes.first, !first.isEmpty, first != textRandomNone {
                    return first
                }
                return entry.textRandomMode.isEmpty ? textRandomNone : entry.textRandomMode
            },
            set: { newValue in
                guard let entryIndex = entryIndex(questionNum: question.num) else { return }
                let blanks = model.runtimeConfig.questionEntries[entryIndex].multiTextBlankModes
                if blanks.count > 1 {
                    model.runtimeConfig.questionEntries[entryIndex].multiTextBlankModes =
                        [String](repeating: newValue, count: blanks.count)
                } else {
                    model.runtimeConfig.questionEntries[entryIndex].textRandomMode = newValue
                }
            }
        )
    }

    private func applyTextIntRange(_ question: SurveyQuestionMeta) {
        guard let entryIndex = entryIndex(questionNum: question.num) else { return }
        let min = model.textIntMin ?? 0
        let max = max(min, model.textIntMax ?? 0)
        let range = [min, max]
        let entry = model.runtimeConfig.questionEntries[entryIndex]
        if entry.multiTextBlankModes.count > 1 {
            model.runtimeConfig.questionEntries[entryIndex].multiTextBlankIntRanges =
                [[Int]](repeating: range, count: entry.multiTextBlankModes.count)
        } else {
            model.runtimeConfig.questionEntries[entryIndex].textRandomIntRange = range
        }
        model.showToast("已应用整数范围 \(min)~\(max)")
    }

    private func intOrNil(_ value: Any?) -> Int? {
        guard let value, !(value is NSNull) else { return nil }
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private func doubleOrZero(_ value: Any?, fallback: Double) -> Double {
        guard let value, !(value is NSNull) else { return fallback }
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
        if let s = value as? String { return Double(s) ?? fallback }
        return fallback
    }

    private func formatValue(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}
