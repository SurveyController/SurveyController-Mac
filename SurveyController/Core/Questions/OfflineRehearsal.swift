import Foundation

enum OfflineRehearsal {
    static let sampleLimit = 20
    static let defaultSeed = 42

    struct QuestionResult: Identifiable, Equatable, Sendable {
        let id: Int
        let title: String
        let answer: String
        let details: [String]
        let selections: [String]
        let answered: Bool
    }

    struct Sample: Identifiable, Equatable, Sendable {
        let id: Int
        let sourceRow: Int?
        let questions: [QuestionResult]
    }

    struct Distribution: Identifiable, Equatable, Sendable {
        let id: Int
        let title: String
        let answeredCount: Int
        let counts: [String: Int]
    }

    struct Report: Equatable, Sendable {
        let seed: Int
        let samples: [Sample]
        let distributions: [Distribution]
    }

    struct Issue: LocalizedError {
        let questionNumber: Int?
        let message: String
        var errorDescription: String? { message }
    }

    static func generate(config: ExecutionConfig, seed: Int, reverseFill: ReverseFillSpec? = nil) async throws -> Report {
        let questions = HttpLogicPlanner.orderedQuestions(config.questionsOrdered).filter { $0.num > 0 && !$0.isDescription }
        guard !questions.isEmpty else { throw Issue(questionNumber: nil, message: "请先解析问卷并配置答案") }
        guard Set(questions.map(\.num)).count == questions.count else {
            throw Issue(questionNumber: nil, message: "题号重复，请重新解析问卷")
        }
        if let unsupported = questions.first(where: \.unsupported) {
            throw Issue(questionNumber: unsupported.num, message: "第 \(unsupported.num) 题暂不支持试跑")
        }
        if let issue = HttpLogicPlanner.fallbackIssue(questions) {
            throw Issue(questionNumber: issue.questionNumber, message: issue.message)
        }
        let samplesToReplay = reverseFill.map { Array($0.samples.prefix(sampleLimit)) }
        let count = samplesToReplay?.count ?? sampleLimit
        guard count > 0 else { throw Issue(questionNumber: nil, message: "请先导入可用的反填数据") }

        let random = SeededRandomSource(seed: seed)
        var configuration = config
        configuration.aiSettings = AISettings()
        configuration.targetNum = count
        let psychometricPlan = reverseFill == nil ? PsychometricPlan.build(configuration, rng: random, shouldStop: { Task.isCancelled }) : [:]
        let selection = AnswerSelectionRuntime(plan: psychometricPlan)
        var samples: [Sample] = []
        for index in 0..<count {
            try Task.checkCancellation()
            let replay = samplesToReplay?[index]
            var state = ExecutionState(config: configuration)
            state.rehearsalRules = [:]
            state.answerSelection = await selection.reserve(rng: random)
            state.reverseFillAnswers = replay?.answers ?? [:]
            let plan = try HttpLogicPlanner.buildPlan(questions) { question in
                try Task.checkCancellation()
                do {
                    guard let action = try WjxAnswerBuilder.buildAnswerAction(question, state: &state, rng: random) else {
                        throw Issue(questionNumber: question.num, message: "第 \(question.num) 题无法生成答案，请检查题型和配置")
                    }
                    return action
                } catch let issue as Issue {
                    throw issue
                } catch {
                    throw Issue(questionNumber: question.num, message: "第 \(question.num) 题无法试跑。\(error.localizedDescription)")
                }
            }
            await selection.record(plan.actions)
            let answers = Dictionary(uniqueKeysWithValues: plan.actions.map { ($0.questionNum, $0) })
            let skipped = Set(plan.skippedQuestionNums)
            let results = questions.map { question in
                questionResult(question, answer: answers[question.num], rules: state.rehearsalRules?[question.num] ?? [],
                               replayed: replay?.answers[question.num] != nil, skipped: skipped.contains(question.num))
            }
            samples.append(Sample(id: index + 1, sourceRow: replay?.row, questions: results))
        }
        let distributions = questions.enumerated().map { index, question in
            let results = samples.map { $0.questions[index] }
            let type = config.questionConfigIndexMap[question.num]?.entryType
            let counts = results.flatMap(\.selections).reduce(into: initialCounts(question, type: type)) {
                $0[$1, default: 0] += 1
            }
            return Distribution(id: question.num, title: question.title,
                                answeredCount: results.count(where: \.answered), counts: counts)
        }
        return Report(seed: seed, samples: samples, distributions: distributions)
    }

    private static func initialCounts(_ question: SurveyQuestionMeta, type: String?) -> [String: Int] {
        let labels = WjxAnswerBuilder.runtimeOptionTexts(question)
        let optionCount = labels.isEmpty ? question.options : labels.count
        var counts: [String: Int] = [:]
        if type == "matrix" {
            for row in 0..<max(1, question.rows) {
                for option in 0..<max(2, optionCount) {
                    counts[matrixLabel(question, row: row, option: option)] = 0
                }
            }
        } else if let type, ["single", "multiple", "dropdown", "score", "scale"].contains(type) {
            for index in 0..<max(1, optionCount) {
                counts[optionLabel(question, index: index)] = 0
            }
        }
        return counts
    }

    private static func optionLabel(_ question: SurveyQuestionMeta, index: Int) -> String {
        let labels = WjxAnswerBuilder.runtimeOptionTexts(question)
        guard labels.indices.contains(index), !labels[index].isEmpty else { return "选项 \(index + 1)" }
        let label = labels[index]
        return labels.firstIndex(of: label) == labels.lastIndex(of: label) ? label : "\(label)（选项 \(index + 1)）"
    }

    private static func matrixLabel(_ question: SurveyQuestionMeta, row: Int, option: Int) -> String {
        let title = question.rowTexts.indices.contains(row) ? question.rowTexts[row] : ""
        let rowLabel = title.isEmpty ? "第 \(row + 1) 行" : "第 \(row + 1) 行 · \(title)"
        return "\(rowLabel) · \(optionLabel(question, index: option))"
    }

    private static func questionResult(
        _ question: SurveyQuestionMeta, answer: AnswerAction?, rules: [String], replayed: Bool, skipped: Bool
    ) -> QuestionResult {
        guard let answer else {
            return QuestionResult(id: question.num, title: question.title,
                                  answer: skipped ? "按问卷逻辑跳过" : "问卷提前结束", details: [], selections: [], answered: false)
        }
        var selections: [String] = []
        var values: [String] = []
        if !answer.matrixIndices.isEmpty {
            selections = answer.matrixIndices.enumerated().map { matrixLabel(question, row: $0.offset, option: $0.element) }
            values = selections
        } else if !answer.selectedIndices.isEmpty {
            let choices = answer.selectedIndices.map { optionLabel(question, index: $0) }
            selections = answer.kind == "order" ? [] : choices
            values = answer.selectedIndices.map { index in
                let title = optionLabel(question, index: index)
                guard let fill = answer.optionFillTexts.first(where: { $0.0 == index })?.1 else { return title }
                return "\(title) · \(fill)"
            }
        } else if !answer.textValues.isEmpty {
            values = answer.textValues
        } else if let slider = answer.sliderValue {
            values = [slider.formatted(.number.precision(.fractionLength(0...4)))]
        } else if let scalar = answer.scalarValue {
            values = [String(scalar)]
        } else {
            values = answer.selectedTexts
        }
        let details = replayed ? rules + ["来自反填表格"] : rules
        let text = values.joined(separator: answer.kind == "order" ? " → " : "；")
            .replacingOccurrences(of: optionFillAiToken, with: "〔AI 填空占位〕")
        return QuestionResult(id: question.num, title: question.title, answer: text.isEmpty ? "空答案" : text,
                              details: details, selections: selections, answered: true)
    }
}
