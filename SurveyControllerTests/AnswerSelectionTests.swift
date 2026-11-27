import XCTest
@testable import SurveyController

final class AnswerSelectionTests: XCTestCase {
    func test_candidates_can_mix_legacy_scalar_and_nested_text() {
        let values: [Any?] = [["", " 甲 ", "乙"], "旧文本", nil]
        let rng = SeededRandomSource(seed: 2)
        let resolved = (0..<20).compactMap { _ in
            AnswerProbabilities.getFillTextFromConfig(values, optionIndex: 0, rng: rng)
        }
        XCTAssertEqual(Set(resolved), ["甲", "乙"])
        XCTAssertEqual(AnswerProbabilities.getFillTextFromConfig(values, optionIndex: 1, rng: rng), "旧文本")
        XCTAssertNil(AnswerProbabilities.getFillTextFromConfig(values, optionIndex: 2, rng: rng))
    }

    func test_joint_plan_keeps_option_quotas_for_each_question() throws {
        var draft = RuntimeConfig()
        draft.target = 10
        draft.questionsInfo = [
            SurveyQuestionMeta(num: 1, typeCode: "5", options: 2, optionTexts: ["低", "高"]),
            SurveyQuestionMeta(num: 2, typeCode: "5", options: 2, optionTexts: ["低", "高"]),
        ]
        draft.questionEntries = [
            QuestionEntry(questionType: "scale", probabilities: [20.0, 80.0], distributionMode: "custom", questionNum: 1, dimension: "A"),
            QuestionEntry(questionType: "scale", probabilities: [60.0, 40.0], distributionMode: "custom", questionNum: 2, dimension: "A"),
        ]
        let plan = PsychometricPlan.build(ExecutionConfigBuilder.build(from: draft), rng: SeededRandomSource(seed: 8))
        let first = try XCTUnwrap(plan[QuestionOptionKey(question: 1, row: nil)])
        let second = try XCTUnwrap(plan[QuestionOptionKey(question: 2, row: nil)])
        XCTAssertEqual(first.filter { $0 == 0 }.count, 2)
        XCTAssertEqual(second.filter { $0 == 0 }.count, 6)
        XCTAssertEqual(first.count, 10)
        XCTAssertEqual(second.count, 10)
    }

    func test_distribution_correction_favors_underrepresented_options_and_keeps_zero_weight() {
        let adjusted = AnswerSelection.adjusted([0.5, 0.5, 0], observed: [0: 18, 1: 2], reliability: false)
        XCTAssertLessThan(adjusted[0], adjusted[1])
        XCTAssertEqual(adjusted[2], 0)
        XCTAssertEqual(adjusted.reduce(0, +), 1, accuracy: 0.000001)
    }

    func test_ai_accepts_v5_json_array_and_legacy_delimiter() throws {
        XCTAssertEqual(try AIAnswerResolver.parseAnswers(#"["甲","乙"]"#, count: 2), ["甲", "乙"])
        XCTAssertEqual(try AIAnswerResolver.parseAnswers("甲 || 乙", count: 2), ["甲", "乙"])
        XCTAssertThrowsError(try AIAnswerResolver.parseAnswers(#"["甲"]"#, count: 2))
    }

    func test_ai_config_export_omits_secrets_and_imports_legacy_mode() throws {
        var config = RuntimeConfig()
        config.aiApiKey = "fake-test-value"
        XCTAssertNil(ConfigCodec.serializeRuntimeConfig(config)["ai_api_key"])
        XCTAssertEqual(ConfigCodec.serializeRuntimeConfig(config, includeSecrets: true)["ai_api_key"] as? String, "fake-test-value")
        let imported = try ConfigCodec.deserializeRuntimeConfig(["schema_version": 2, "ai_mode": "free", "ai_config_mode": "override"])
        XCTAssertFalse(imported.aiConfigPresent)
        XCTAssertEqual(imported.aiConfigMode, "inherit")
    }

    func test_imports_v5_optional_fields_and_preserves_known_fields() throws {
        let config = try ConfigCodec.deserializeRuntimeConfig([
            "schema_version": 2,
            "fail_threshold": 7,
            "question_entries": [["question_num": 1, "question_type": "single", "multi_random_count": false, "question_id": "client-id"]],
            "questions_info": [["num": 1, "title": "Q1", "extra_media": []]],
        ])
        XCTAssertEqual(config.questionEntries.first?.questionId, "client-id")
        XCTAssertEqual(config.questionsInfo.first?.title, "Q1")
    }
}
