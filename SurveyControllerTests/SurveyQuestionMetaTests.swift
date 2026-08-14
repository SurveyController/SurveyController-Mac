// 对标 CI/unit_tests/providers/test_contracts.py

import XCTest
@testable import SurveyController

final class SurveyQuestionMetaTests: XCTestCase {

    // test_ensure_survey_question_meta_normalizes_media_and_missing_provider_fields
    func test_ensure_survey_question_meta_normalizes_media_and_missing_provider_fields() {
        let meta = ensureSurveyQuestionMeta(
            [
                "num": 0,
                "page": 0,
                "title": "  测试题  ",
                "type_code": "3",
                "options": 2,
                "logic_parse_status": "bad-status",
                "provider": "unknown",
                "provider_question_id": "",
                "provider_page_id": "",
                "unsupported": true,
                "unsupported_reason": "",
                "question_media": [
                    [
                        "kind": "image", "scope": "title", "index": 99,
                        "source_url": " https://example.com/title.png ", "label": " 题干图 ",
                    ] as [String: Any],
                    [
                        "kind": "image", "scope": "option", "index": "1",
                        "source_url": "https://example.com/option-b.png", "label": " 选项B ",
                    ],
                    [
                        "kind": "image", "scope": "row", "index": "-1",
                        "source_url": "https://example.com/bad-row.png", "label": "坏行",
                    ],
                    [
                        "kind": "video", "scope": "title", "index": NSNull(),
                        "source_url": "https://example.com/video.mp4", "label": "坏媒体",
                    ],
                ],
            ] as [String: Any],
            defaultProvider: .qq,
            index: 7
        )

        XCTAssertEqual(meta.num, 1)
        XCTAssertEqual(meta.page, 1)
        XCTAssertEqual(meta.provider, .qq)
        XCTAssertEqual(meta.providerQuestionId, "1")
        XCTAssertEqual(meta.providerPageId, "1")
        XCTAssertEqual(meta.logicParseStatus, logicParseStatusUnknown)
        XCTAssertEqual(meta.unsupportedReason, "当前平台暂不支持该题型")

        let media = meta.questionMedia
        XCTAssertEqual(media.count, 2)
        XCTAssertEqual(media[0]["source_url"] as? String, "https://example.com/title.png")
        XCTAssertTrue(media[0]["index"] is NSNull)
        XCTAssertEqual(media[0]["label"] as? String, "题干图")
        XCTAssertEqual(media[1]["index"] as? Int, 1)
        XCTAssertEqual(media[1]["label"] as? String, "选项B")
    }

    // test_description_provider_type_is_not_treated_as_unsupported
    func test_description_provider_type_is_not_treated_as_unsupported() {
        let meta = ensureSurveyQuestionMeta(
            [
                "num": 5,
                "title": "模特A：无眼镜",
                "type_code": "0",
                "provider_type": "description",
                "unsupported": true,
                "unsupported_reason": "暂不支持腾讯题型：description",
            ],
            defaultProvider: .qq
        )
        XCTAssertTrue(meta.isDescription)
        XCTAssertFalse(meta.unsupported)
    }

    // test_legacy_logic_status_is_inferred_from_saved_rules
    func test_legacy_logic_status_is_inferred_from_saved_rules() {
        let jumpMeta = ensureSurveyQuestionMeta([
            "num": 1, "title": "跳题", "has_jump": true,
            "jump_rules": [["option_index": 1, "jumpto": 5]],
        ])
        let plainMeta = ensureSurveyQuestionMeta(["num": 2, "title": "普通题"])
        let unknownMeta = ensureSurveyQuestionMeta(["num": 3, "title": "未知跳题", "has_jump": true])

        XCTAssertEqual(jumpMeta.logicParseStatus, logicParseStatusComplete)
        XCTAssertEqual(plainMeta.logicParseStatus, logicParseStatusNone)
        XCTAssertEqual(unknownMeta.logicParseStatus, logicParseStatusUnknown)
    }

    // test_serialized_question_meta_preserves_provider_identity_fields
    func test_serialized_question_meta_preserves_provider_identity_fields() {
        let meta = ensureSurveyQuestionMeta(
            [
                "num": 8,
                "title": "联系方式",
                "provider": "qq",
                "provider_question_id": "question-8",
                "provider_page_id": "page-2",
                "provider_type": "text",
                "required": true,
                "option_texts": ["姓名", "电话"],
            ],
            defaultProvider: .wjx
        )

        let dumped = serializeSurveyQuestionMetas([meta])[0]
        let cloned = ensureSurveyQuestionMeta(dumped, defaultProvider: .wjx)

        XCTAssertEqual(dumped["provider"] as? String, "qq")
        XCTAssertEqual(dumped["provider_question_id"] as? String, "question-8")
        XCTAssertEqual(dumped["provider_page_id"] as? String, "page-2")
        XCTAssertEqual(dumped["provider_type"] as? String, "text")
        XCTAssertEqual(dumped["required"] as? Bool, true)
        XCTAssertEqual(cloned.provider, .qq)
    }

    // 跳题规则补充 terminates_survey（对标 _normalize_jump_rules）
    func test_jump_rules_gain_terminates_survey_flag() {
        let meta = ensureSurveyQuestionMeta([
            "num": 2, "title": "结束题", "has_jump": true,
            "jump_rules": [
                ["option_index": 1, "option_text": "结束作答"],
                ["option_index": 2, "option_text": "跳到第5题", "terminates_survey": 1],
            ],
        ])
        let rules = meta.jumpRules
        XCTAssertEqual(rules[0]["terminates_survey"] as? Bool, true)
        XCTAssertEqual(rules[1]["terminates_survey"] as? Bool, true)
    }

    // 对标 sanitize_answer_rules 的核心行为
    func test_sanitize_answer_rules_drops_invalid_and_unsupported() {
        let questions = [
            SurveyQuestionMeta(num: 1, title: "单选", typeCode: "4", options: 2),
            SurveyQuestionMeta(num: 2, title: "说明", typeCode: "0"),
        ]
        let (rules, stats) = sanitizeAnswerRules(
            [
                // 合法：1 → 1
                ["condition_question_num": 1, "condition_mode": "selected", "condition_option_indices": [0],
                 "target_question_num": 1, "action_mode": "must_select", "target_option_indices": [1]],
                // 非法 mode
                ["condition_question_num": 1, "condition_mode": "bad", "condition_option_indices": [0],
                 "target_question_num": 1, "action_mode": "must_select", "target_option_indices": [1]],
                // 目标题型不支持
                ["condition_question_num": 1, "condition_mode": "selected", "condition_option_indices": [0],
                 "target_question_num": 2, "action_mode": "must_not_select", "target_option_indices": [1]],
            ],
            questionsInfo: questions
        )
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(stats["invalid"], 1)
        XCTAssertEqual(stats["unsupported"], 1)
    }

    // 对标 build_survey_definition 的归一化
    func test_build_survey_definition_normalizes_questions() {
        let definition = SurveyDefinition(
            provider: .credamo,
            title: "  解析标题  ",
            questions: [["num": 1, "title": "题", "type_code": "2"]]
        )
        XCTAssertEqual(definition.provider, .credamo)
        XCTAssertEqual(definition.title, "解析标题")
        XCTAssertEqual(definition.questions.count, 1)
        XCTAssertEqual(definition.questions[0].provider, .credamo)
        XCTAssertEqual(definition.questions[0].providerQuestionId, "1")
    }
}
