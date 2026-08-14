// 对标 CI/unit_tests/providers/test_http_logic.py + wjx 答案构建行为

import XCTest
@testable import SurveyController

final class WjxAnswerBuilderTests: XCTestCase {

    func makeConfig(
        questions: [SurveyQuestionMeta],
        entries: [QuestionEntry],
        answerRules: [[String: Any]] = []
    ) -> ExecutionConfig {
        var config = RuntimeConfig()
        config.url = "https://www.wjx.cn/vm/demo.aspx"
        config.surveyProvider = .wjx
        config.questionsInfo = questions
        config.questionEntries = entries
        config.answerRules = answerRules
        return ExecutionConfigBuilder.build(from: config)
    }

    // 对标 weighted_index：概率为 0 的选项永不选中
    func test_single_action_respects_zero_probability() throws {
        let questions = [SurveyQuestionMeta(num: 1, title: "单选", typeCode: "3", options: 3, optionTexts: ["A", "B", "C"])]
        let entries = [QuestionEntry(questionType: "single", probabilities: [0.0, 0.0, 100.0], optionCount: 3, questionNum: 1)]
        let config = makeConfig(questions: questions, entries: entries)
        var state = ExecutionState(config: config)
        let rng = SeededRandomSource(seed: 7)

        for _ in 0..<20 {
            let action = try WjxAnswerBuilder.buildAnswerAction(questions[0], state: &state, rng: rng)
            XCTAssertEqual(action?.selectedIndices, [2])
        }
    }

    // 对标 valid_forced_choice_index：强制选项优先生效
    func test_single_action_honors_forced_option() throws {
        let questions = [SurveyQuestionMeta(
            num: 1, title: "请务必选择第2项", typeCode: "3", options: 3,
            optionTexts: ["A", "B", "C"], forcedOptionIndex: 1
        )]
        let entries = [QuestionEntry(questionType: "single", probabilities: [100.0, 0.0, 0.0], optionCount: 3, questionNum: 1)]
        let config = makeConfig(questions: questions, entries: entries)
        var state = ExecutionState(config: config)

        let action = try WjxAnswerBuilder.buildAnswerAction(questions[0], state: &state, rng: SeededRandomSource(seed: 1))
        XCTAssertEqual(action?.selectedIndices, [1])
        XCTAssertEqual(action?.kind, "choice")
        XCTAssertEqual(action?.recordType, "single")
    }

    // 对标 _build_wjx_multiple_action 未配置概率路径：随机数量且符合数量限制
    func test_multiple_action_unset_probabilities_respects_limits() throws {
        let questions = [SurveyQuestionMeta(
            num: 2, title: "多选", typeCode: "4", options: 4,
            optionTexts: ["A", "B", "C", "D"],
            multiMinLimit: 2, multiMaxLimit: 3
        )]
        let entries = [QuestionEntry(questionType: "multiple", probabilities: -1, optionCount: 4, questionNum: 2)]
        let config = makeConfig(questions: questions, entries: entries)
        let rng = SeededRandomSource(seed: 42)

        for _ in 0..<30 {
            var state = ExecutionState(config: config)
            let action = try WjxAnswerBuilder.buildAnswerAction(questions[0], state: &state, rng: rng)
            let count = action?.selectedIndices.count ?? 0
            XCTAssertTrue((2...3).contains(count), "选中数量 \(count) 不在 [2,3]")
        }
    }

    // 对标 get_multiple_rule_constraint：必选优先于概率
    func test_multiple_action_applies_must_select_rule() throws {
        let questions = [SurveyQuestionMeta(num: 1, title: "条件题", typeCode: "3", options: 2, optionTexts: ["A", "B"])]
        let questions2 = [SurveyQuestionMeta(num: 2, title: "多选题", typeCode: "4", options: 3, optionTexts: ["X", "Y", "Z"])]
        let rules: [[String: Any]] = [[
            "id": "rule-1-2", "condition_question_num": 1, "condition_mode": "selected",
            "condition_option_indices": [0], "target_question_num": 2,
            "action_mode": "must_select", "target_option_indices": [2],
        ]]
        let entries = [
            QuestionEntry(questionType: "single", probabilities: -1, optionCount: 2, questionNum: 1),
            QuestionEntry(questionType: "multiple", probabilities: -1, optionCount: 3, questionNum: 2),
        ]
        let config = makeConfig(questions: questions + questions2, entries: entries, answerRules: rules)
        var state = ExecutionState(config: config)
        let rng = SeededRandomSource(seed: 9)

        // 第1题选 A（下标 0）→ 第2题必选 Z（下标 2）
        _ = try WjxAnswerBuilder.buildAnswerAction(questions[0], state: &state, rng: rng)
        let action = try WjxAnswerBuilder.buildAnswerAction(questions2[0], state: &state, rng: rng)
        XCTAssertTrue(action?.selectedIndices.contains(2) ?? false, "必选规则未生效：\(action?.selectedIndices ?? [])")
    }

    // 对标 _build_wjx_text_action：多空拆分与随机模式
    func test_text_action_multi_blank_with_modes() throws {
        let questions = [SurveyQuestionMeta(num: 3, title: "信息", typeCode: "1", options: 0, textInputs: 2)]
        let entries = [QuestionEntry(
            questionType: "text",
            probabilities: [1.0],
            texts: ["张三||13800138000"],
            optionCount: 0,
            questionNum: 3,
            multiTextBlankModes: ["name", "mobile"]
        )]
        let config = makeConfig(questions: questions, entries: entries)
        var state = ExecutionState(config: config)
        let action = try WjxAnswerBuilder.buildAnswerAction(questions[0], state: &state, rng: SeededRandomSource(seed: 3))
        XCTAssertEqual(action?.kind, "text")
        XCTAssertEqual(action?.textValues.count, 2)
        // name 模式生成中文姓名（1-3 个字符），mobile 模式生成 11 位手机号
        let name = action?.textValues[0] ?? ""
        XCTAssertTrue((1...3).contains(name.count))
        let mobile = action?.textValues[1] ?? ""
        XCTAssertEqual(mobile.count, 11)
        XCTAssertTrue(mobile.hasPrefix("1"))
    }

    // 对标 _build_wjx_matrix_action：逐行按概率选择
    func test_matrix_action_builds_row_indices() throws {
        let questions = [SurveyQuestionMeta(
            num: 4, title: "矩阵", typeCode: "6", options: 2, rows: 3,
            rowTexts: ["R1", "R2", "R3"], optionTexts: ["差", "好"]
        )]
        let entries = [QuestionEntry(
            questionType: "matrix", probabilities: [[100.0, 0.0], [0.0, 100.0], [50.0, 50.0]],
            rows: 3, optionCount: 2, questionNum: 4
        )]
        let config = makeConfig(questions: questions, entries: entries)
        var state = ExecutionState(config: config)
        let action = try WjxAnswerBuilder.buildAnswerAction(questions[0], state: &state, rng: SeededRandomSource(seed: 5))
        XCTAssertEqual(action?.kind, "matrix")
        XCTAssertEqual(action?.matrixIndices[0], 0)
        XCTAssertEqual(action?.matrixIndices[1], 1)
        XCTAssertTrue([0, 1].contains(action?.matrixIndices[2] ?? -1))
    }

    // 对标 _build_wjx_slider_action：目标值夹紧到声明范围
    func test_slider_action_clamps_to_declared_range() throws {
        let questions = [SurveyQuestionMeta(
            num: 5, title: "滑块", typeCode: "8", options: 1,
            sliderMin: 1.0, sliderMax: 5.0, sliderStep: 0.5
        )]
        let entries = [QuestionEntry(questionType: "slider", probabilities: [66.0], optionCount: 1, questionNum: 5)]
        let config = makeConfig(questions: questions, entries: entries)
        var state = ExecutionState(config: config)
        let action = try WjxAnswerBuilder.buildAnswerAction(questions[0], state: &state)
        XCTAssertEqual(action?.sliderValue, 5.0)
    }

    // 对标 _build_wjx_order_action：全选项乱序排列
    func test_order_action_permutes_all_options() throws {
        let questions = [SurveyQuestionMeta(num: 6, title: "排序", typeCode: "11", options: 4, optionTexts: ["A", "B", "C", "D"])]
        let entries = [QuestionEntry(questionType: "order", probabilities: -1, optionCount: 4, questionNum: 6)]
        let config = makeConfig(questions: questions, entries: entries)
        var state = ExecutionState(config: config)
        let action = try WjxAnswerBuilder.buildAnswerAction(questions[0], state: &state, rng: SeededRandomSource(seed: 11))
        XCTAssertEqual(Set(action?.selectedIndices ?? []), [0, 1, 2, 3])
        XCTAssertEqual(action?.kind, "order")
    }

    // fillable_options 无配置时回落默认填空文本
    func test_single_action_defaults_fill_for_fillable_option() throws {
        let questions = [SurveyQuestionMeta(
            num: 7, title: "其他", typeCode: "3", options: 2,
            optionTexts: ["A", "其他"], fillableOptions: [1]
        )]
        let entries = [QuestionEntry(
            questionType: "single", probabilities: [0.0, 100.0], optionCount: 2, questionNum: 7,
            optionFillTexts: [nil, nil]
        )]
        let config = makeConfig(questions: questions, entries: entries)
        var state = ExecutionState(config: config)
        let action = try WjxAnswerBuilder.buildAnswerAction(questions[0], state: &state, rng: SeededRandomSource(seed: 2))
        XCTAssertEqual(action?.optionFillTexts.first?.0, 1)
        XCTAssertEqual(action?.optionFillTexts.first?.1, "无")
    }
}

// MARK: - HttpLogicPlanner 测试（对标 test_http_logic.py 核心行为）

final class HttpLogicPlannerTests: XCTestCase {

    // 无逻辑问卷：全部作答
    func test_plan_answers_all_questions_without_logic() throws {
        let questions = [
            SurveyQuestionMeta(num: 1, title: "Q1", typeCode: "3", options: 2),
            SurveyQuestionMeta(num: 2, title: "Q2", typeCode: "3", options: 2),
        ]
        let plan = try HttpLogicPlanner.buildPlan(questions) { question in
            AnswerAction(questionNum: question.num, kind: "choice", selectedIndices: [0])
        }
        XCTAssertEqual(plan.actions.count, 2)
        XCTAssertTrue(plan.skippedQuestionNums.isEmpty)
        XCTAssertFalse(plan.terminatedEarly)
    }

    // 显示条件：来源题未命中 → 跳过
    func test_plan_skips_question_with_unmet_display_condition() throws {
        let questions = [
            SurveyQuestionMeta(num: 1, title: "Q1", typeCode: "4", options: 2, optionTexts: ["A", "B"]),
            SurveyQuestionMeta(
                num: 2, title: "Q2", typeCode: "3", options: 2,
                hasDisplayCondition: true,
                displayConditions: [[
                    "condition_question_num": 1, "condition_mode": "selected",
                    "condition_option_indices": [1], "raw_relation": "1,2",
                ]]
            ),
            SurveyQuestionMeta(num: 3, title: "Q3", typeCode: "3", options: 2),
        ]
        let plan = try HttpLogicPlanner.buildPlan(questions) { question in
            AnswerAction(questionNum: question.num, kind: "choice", selectedIndices: [0])
        }
        XCTAssertEqual(plan.actions.map { $0.questionNum }, [1, 3])
        XCTAssertEqual(plan.skippedQuestionNums, [2])
    }

    // 跳题：选中跳转目标 → 中间题跳过
    func test_plan_honors_jump_rules() throws {
        let questions = [
            SurveyQuestionMeta(
                num: 1, title: "Q1", typeCode: "3", options: 2, optionTexts: ["A", "B"],
                hasJump: true,
                jumpRules: [["option_index": 0, "jumpto": 3, "option_text": "A", "terminates_survey": false]]
            ),
            SurveyQuestionMeta(num: 2, title: "Q2", typeCode: "3", options: 2),
            SurveyQuestionMeta(num: 3, title: "Q3", typeCode: "3", options: 2),
        ]
        let plan = try HttpLogicPlanner.buildPlan(questions) { question in
            AnswerAction(questionNum: question.num, kind: "choice", selectedIndices: [0])
        }
        XCTAssertEqual(plan.actions.map { $0.questionNum }, [1, 3])
        XCTAssertEqual(plan.skippedQuestionNums, [2])
        XCTAssertFalse(plan.terminatedEarly)
    }

    // 跳题到结束（terminates_survey）→ 提前结束
    func test_plan_terminates_early_on_terminate_jump() throws {
        let questions = [
            SurveyQuestionMeta(
                num: 1, title: "Q1", typeCode: "3", options: 2, optionTexts: ["结束作答", "B"],
                hasJump: true,
                jumpRules: [["option_index": 0, "jumpto": 1, "option_text": "结束作答", "terminates_survey": true]]
            ),
            SurveyQuestionMeta(num: 2, title: "Q2", typeCode: "3", options: 2),
        ]
        let plan = try HttpLogicPlanner.buildPlan(questions) { question in
            AnswerAction(questionNum: question.num, kind: "choice", selectedIndices: [0])
        }
        XCTAssertEqual(plan.actions.map { $0.questionNum }, [1])
        XCTAssertTrue(plan.terminatedEarly)
    }

    // 对标 get_http_logic_fallback_reason：回跳拒绝
    func test_fallback_reason_rejects_backward_jump() {
        let questions = [
            SurveyQuestionMeta(
                num: 3, title: "Q3", typeCode: "3", options: 2, optionTexts: ["A", "B"],
                hasJump: true,
                jumpRules: [["option_index": 0, "jumpto": 1, "option_text": "A", "terminates_survey": false]]
            ),
        ]
        XCTAssertEqual(HttpLogicPlanner.fallbackReason(questions), "第3题跳题目标回跳到已过题目")
    }

    // 对标 get_http_logic_fallback_reason：显隐依赖未来题拒绝
    func test_fallback_reason_rejects_future_dependency() {
        let questions = [
            SurveyQuestionMeta(
                num: 1, title: "Q1", typeCode: "3", options: 2,
                hasDisplayCondition: true,
                displayConditions: [[
                    "condition_question_num": 2, "condition_mode": "selected",
                    "condition_option_indices": [0],
                ]]
            ),
        ]
        XCTAssertEqual(HttpLogicPlanner.fallbackReason(questions), "第1题显隐条件依赖未来题目")
    }
}

// MARK: - ExecutionConfigBuilder 测试

final class ExecutionConfigBuilderTests: XCTestCase {

    func test_build_maps_entries_by_question_num() {
        var config = RuntimeConfig()
        config.questionsInfo = [
            SurveyQuestionMeta(num: 1, title: "单选", typeCode: "3", options: 2),
            SurveyQuestionMeta(num: 2, title: "多选", typeCode: "4", options: 3),
            SurveyQuestionMeta(num: 3, title: "填空", typeCode: "1", options: 0, textInputs: 2),
        ]
        config.questionEntries = [
            QuestionEntry(questionType: "single", probabilities: [60.0, 40.0], optionCount: 2, questionNum: 1),
            QuestionEntry(questionType: "multiple", probabilities: [50.0, 50.0, 50.0], optionCount: 3, questionNum: 2),
            QuestionEntry(
                questionType: "text", probabilities: [1.0], texts: ["A||B"],
                optionCount: 0, questionNum: 3, multiTextBlankModes: ["none", "none"]
            ),
        ]

        let execution = ExecutionConfigBuilder.build(from: config)
        XCTAssertEqual(execution.questionConfigIndexMap[1]?.entryType, "single")
        XCTAssertEqual(execution.questionConfigIndexMap[2]?.entryType, "multiple")
        XCTAssertEqual(execution.questionConfigIndexMap[3]?.entryType, "text")
        XCTAssertEqual(execution.singleProb.count, 1)
        XCTAssertEqual(execution.multipleProb.count, 1)
        XCTAssertEqual(execution.questionsOrdered.map { $0.num }, [1, 2, 3])
    }
}
