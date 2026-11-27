import XCTest
@testable import SurveyController

final class OfflineRehearsalTests: XCTestCase {
    func testRehearsalIsSeededAndShowsRulesSkipsAndAI() async throws {
        var config = RuntimeConfig()
        config.questionsInfo = [
            SurveyQuestionMeta(num: 1, title: "来源", typeCode: "3", options: 2, optionTexts: ["甲", "乙"], forcedOptionIndex: 0),
            SurveyQuestionMeta(num: 2, title: "目标", typeCode: "3", options: 2, optionTexts: ["是", "否"]),
            SurveyQuestionMeta(num: 3, title: "说明", typeCode: "1", textInputs: 1),
            SurveyQuestionMeta(num: 4, title: "隐藏", typeCode: "3", options: 2, optionTexts: ["高", "低"],
                               hasDisplayCondition: true, displayConditions: [[
                                "condition_question_num": 1, "condition_mode": "selected", "condition_option_indices": [1],
                               ]]),
            SurveyQuestionMeta(num: 5, title: "随机", typeCode: "3", options: 2, optionTexts: ["春", "秋"]),
        ]
        config.questionEntries = [
            QuestionEntry(questionType: "single", probabilities: [0.5, 0.5], optionCount: 2, questionNum: 1),
            QuestionEntry(questionType: "single", probabilities: [0.5, 0.5], optionCount: 2, questionNum: 2),
            QuestionEntry(questionType: "text", texts: ["备用"], questionNum: 3, aiEnabled: true),
            QuestionEntry(questionType: "single", probabilities: [0.5, 0.5], optionCount: 2, questionNum: 4),
            QuestionEntry(questionType: "single", probabilities: [0.5, 0.5], optionCount: 2, questionNum: 5),
        ]
        config.answerRules = [[
            "id": "a", "condition_question_num": 1, "condition_mode": "selected", "condition_option_indices": [0],
            "target_question_num": 2, "action_mode": "must_select", "target_option_indices": [1],
        ]]
        let execution = ExecutionConfigBuilder.build(from: config)
        let first = try await OfflineRehearsal.generate(config: execution, seed: 42)
        let repeated = try await OfflineRehearsal.generate(config: execution, seed: 42)
        let changed = try await OfflineRehearsal.generate(config: execution, seed: 43)

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first.samples, changed.samples)
        XCTAssertEqual(first.samples.count, 20)
        XCTAssertEqual(first.samples[0].questions.map(\.answer).prefix(4), ["甲", "否", "〔AI 填空占位〕", "按问卷逻辑跳过"])
        XCTAssertEqual(first.samples[0].questions[1].details, ["命中第 1 题的必选规则"])
        XCTAssertEqual(first.distributions[1].counts, ["是": 0, "否": 20])
        XCTAssertEqual(first.distributions[3].answeredCount, 0)
    }

    @MainActor
    func testQuestionIssueSelectsTheMatchingEditorRow() {
        let model = AppModel()
        model.runtimeConfig = RuntimeConfig()
        model.runtimeConfig.questionsInfo = [
            SurveyQuestionMeta(num: 2, title: "来源", typeCode: "3", options: 2),
            SurveyQuestionMeta(num: 9, title: "目标", typeCode: "3", options: 2, hasJump: true, logicParseStatus: "unknown"),
        ]
        model.runtimeConfig.questionEntries = [
            QuestionEntry(questionType: "single", optionCount: 2, questionNum: 2),
            QuestionEntry(questionType: "single", optionCount: 2, questionNum: 9),
        ]
        model.parsePhase = .ready
        model.goToStep(.check)

        let issue = model.preflight.errors.first { $0.contains("逻辑规则") }
        XCTAssertNotNil(issue)
        XCTAssertEqual(issue.flatMap { model.preflight.questionTargets[$0] }, 9)
        model.editQuestion(9)
        XCTAssertEqual(model.wizardStep, .answers)
        XCTAssertEqual(model.selectedQuestionIndex, 1)
    }

    func testReverseFillUsesExistingRowsInOrder() async throws {
        var config = RuntimeConfig()
        config.questionsInfo = [SurveyQuestionMeta(num: 1, title: "反填", typeCode: "1", textInputs: 1)]
        config.questionEntries = [QuestionEntry(questionType: "text", texts: ["备用"], questionNum: 1)]
        let execution = ExecutionConfigBuilder.build(from: config)
        let answers = [1: AnswerAction(questionNum: 1, kind: "text", textValues: ["表格内容"])]
        let spec = ReverseFillSpec(totalRows: 1, samples: [ReverseFillSample(row: 9, answers: answers)], unmatched: [], invalidRows: [])
        let result = try await OfflineRehearsal.generate(config: execution, seed: 42, reverseFill: spec)

        XCTAssertEqual(result.samples.count, 1)
        XCTAssertEqual(result.samples[0].sourceRow, 9)
        XCTAssertEqual(result.samples[0].questions[0].answer, "表格内容")
    }
}
