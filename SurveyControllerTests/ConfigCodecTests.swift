// 对标 CI/unit_tests/app/test_config_codec.py

import XCTest
@testable import SurveyController

final class ConfigCodecTests: XCTestCase {

    // test_default_user_agent_is_pc_web
    func test_default_user_agent_is_pc_web() {
        XCTAssertEqual(defaultUserAgent, userAgentPresets["pc_web"]?.ua)
        XCTAssertTrue(defaultUserAgent.contains("Windows NT"))
    }

    // test_runtime_config_roundtrip_keeps_reverse_fill_fields
    func test_runtime_config_roundtrip_keeps_reverse_fill_fields() throws {
        var config = RuntimeConfig()
        config.reverseFillEnabled = true
        config.reverseFillSourcePath = "/Users/demo/Downloads/demo.xlsx"
        config.reverseFillFormat = reverseFillFormatWjxSequence
        config.reverseFillStartRow = 3
        config.reverseFillThreads = 4

        let payload = ConfigCodec.serializeRuntimeConfig(config)
        let restored = try ConfigCodec.deserializeRuntimeConfig(payload)

        XCTAssertNil(payload["config_schema_version"])
        XCTAssertTrue(restored.reverseFillEnabled)
        XCTAssertEqual(restored.reverseFillSourcePath, "/Users/demo/Downloads/demo.xlsx")
        XCTAssertEqual(restored.reverseFillFormat, reverseFillFormatWjxSequence)
        XCTAssertEqual(restored.reverseFillStartRow, 3)
        XCTAssertEqual(restored.reverseFillThreads, 4)
    }

    // test_runtime_config_roundtrip_keeps_answer_datetime_window
    func test_runtime_config_roundtrip_keeps_answer_datetime_window() throws {
        var config = RuntimeConfig()
        config.answerDatetimeWindow = ("2026-02-10 09:00:00", "2026-02-10 10:00:00")

        let payload = ConfigCodec.serializeRuntimeConfig(config)
        let restored = try ConfigCodec.deserializeRuntimeConfig(payload)

        let window = payload["answer_datetime_window"] as? [String]
        XCTAssertEqual(window, ["2026-02-10 09:00:00", "2026-02-10 10:00:00"])
        XCTAssertEqual(restored.answerDatetimeWindow.0, "2026-02-10 09:00:00")
        XCTAssertEqual(restored.answerDatetimeWindow.1, "2026-02-10 10:00:00")
    }

    // test_runtime_config_roundtrip_keeps_questions_info_provider_metadata
    func test_runtime_config_roundtrip_keeps_questions_info_provider_metadata() throws {
        var config = RuntimeConfig()
        config.surveyProvider = .qq
        config.questionsInfo = [
            SurveyQuestionMeta(
                num: 3,
                title: "联系方式",
                typeCode: "1",
                optionTexts: ["姓名", "电话"],
                logicParseStatus: logicParseStatusUnknown,
                questionMedia: [[
                    "kind": "image", "scope": "title", "index": NSNull(),
                    "source_url": "https://example.com/q3.png", "label": "题干图",
                ]],
                provider: .qq,
                providerQuestionId: "question-3",
                providerPageId: "page-2",
                providerType: "text",
                required: true
            ),
        ]

        let payload = ConfigCodec.serializeRuntimeConfig(config)
        let restored = try ConfigCodec.deserializeRuntimeConfig(payload)

        let dumpedInfo = (payload["questions_info"] as? [[String: Any]])?[0]
        XCTAssertEqual(dumpedInfo?["provider_question_id"] as? String, "question-3")
        XCTAssertEqual(dumpedInfo?["provider_page_id"] as? String, "page-2")
        XCTAssertEqual(dumpedInfo?["provider_type"] as? String, "text")
        XCTAssertEqual(dumpedInfo?["required"] as? Bool, true)
        XCTAssertEqual(dumpedInfo?["logic_parse_status"] as? String, "unknown")

        XCTAssertEqual(restored.questionsInfo.count, 1)
        let restoredInfo = restored.questionsInfo[0]
        XCTAssertEqual(restoredInfo.provider, .qq)
        XCTAssertEqual(restoredInfo.providerQuestionId, "question-3")
        XCTAssertEqual(restoredInfo.providerPageId, "page-2")
        XCTAssertEqual(restoredInfo.providerType, "text")
        XCTAssertTrue(restoredInfo.required)
        XCTAssertEqual(restoredInfo.logicParseStatus, logicParseStatusUnknown)
        XCTAssertEqual(restoredInfo.questionMedia[0]["label"] as? String, "题干图")
    }

    // test_build_runtime_config_snapshot_returns_detached_copies
    func test_build_runtime_config_snapshot_returns_detached_copies() {
        var config = RuntimeConfig()
        config.answerRules = [["question_num": 1, "equals": [0]]]
        config.dimensionGroups = ["情绪维度"]
        config.questionEntries = [
            QuestionEntry(questionType: "single", probabilities: [60.0, 40.0], texts: ["A", "B"], optionCount: 2, questionNum: 1)
        ]
        config.questionsInfo = [
            SurveyQuestionMeta(num: 1, title: "单选题", typeCode: "3", optionTexts: ["A", "B"], providerQuestionId: "q1")
        ]

        var snapshot = ConfigCodec.buildRuntimeConfigSnapshot(config)
        snapshot.questionEntries[0].texts?[0] = "已修改"
        snapshot.questionsInfo[0].optionTexts[0] = "已修改"
        if var equals = snapshot.answerRules[0]["equals"] as? [Int] {
            equals[0] = 9
            snapshot.answerRules[0]["equals"] = equals
        }
        snapshot.dimensionGroups[0] = "新维度"

        XCTAssertEqual(config.questionEntries[0].texts?[0], "A")
        XCTAssertEqual(config.questionsInfo[0].optionTexts[0], "A")
        XCTAssertEqual((config.answerRules[0]["equals"] as? [Int])?[0], 0)
        XCTAssertEqual(config.dimensionGroups[0], "情绪维度")
    }

    // test_unknown_fields_raise_corruption_error
    func test_unknown_fields_raise_corruption_error() {
        XCTAssertThrowsError(try ConfigCodec.normalizeRuntimeConfigPayload([
            "url": "https://example.test", "unknown_field": 1,
        ])) { error in
            XCTAssertTrue("\(error)".contains("该配置文件损坏"))
        }
        XCTAssertThrowsError(try ConfigCodec.normalizeRuntimeConfigPayload([
            "url": "https://example.test",
            "question_entries": [["question_type": "single", "unexpected": 1]],
        ]))
        XCTAssertThrowsError(try ConfigCodec.normalizeRuntimeConfigPayload([
            "url": "https://example.test",
            "questions_info": [["num": 1, "title": "Q1", "unexpected": 1]],
        ]))
    }

    // test_question_entry_normalizes_text_modes_ranges_provider_and_dimensions
    func test_question_entry_normalizes_text_modes_ranges_provider_and_dimensions() throws {
        let entry = try ConfigCodec.deserializeQuestionEntry([
            "question_type": "text",
            "probabilities": [] as [Any],
            "texts": ["答案"],
            "rows": "2",
            "option_count": "0",
            "distribution_mode": "custom",
            "custom_weights": [0, "3"],
            "survey_provider": "unknown",
            "provider_question_id": " q1 ",
            "provider_page_id": " p1 ",
            "ai_enabled": true,
            "multi_text_blank_modes": ["name", "bad", "integer"],
            "multi_text_blank_ai_flags": [1, 0],
            "multi_text_blank_int_ranges": [[1, 3] as [Any], "", ["bad"] as [Any]],
            "text_random_mode": "integer",
            "text_random_int_range": ["5", "9"],
            "is_location": true,
            "location_parts": ["北京", "北京", "东城区"],
            "dimension": " 未分组 ",
            "psycho_bias": "bad",
        ])

        let probabilities = entry.probabilities as? [Any]
        XCTAssertEqual(probabilities?.count, 2)
        XCTAssertEqual((probabilities?[0] as? NSNumber)?.intValue, 0)
        XCTAssertEqual((probabilities?[1] as? String), "3")
        XCTAssertEqual(entry.surveyProvider, .wjx)
        XCTAssertEqual(entry.providerQuestionId, "q1")
        XCTAssertEqual(entry.providerPageId, "p1")
        XCTAssertEqual(entry.multiTextBlankModes, ["name", "none", "integer"])
        XCTAssertEqual(entry.multiTextBlankAiFlags, [true, false])
        XCTAssertEqual(entry.textRandomIntRange, [5, 9])
        XCTAssertTrue(entry.isLocation)
        XCTAssertEqual(entry.locationParts, ["北京", "北京", "东城区"])
        XCTAssertNil(entry.dimension)
        XCTAssertEqual(entry.psychoBias, "custom")

        let payload = ConfigCodec.serializeQuestionEntry(entry)
        XCTAssertTrue(payload["dimension"] is NSNull)
        XCTAssertEqual(payload["text_random_int_range"] as? [Int], [5, 9])
        XCTAssertEqual(payload["location_parts"] as? [String], ["北京", "北京", "东城区"])
    }

    // test_normalize_runtime_config_payload_covers_boundaries_and_invalid_values
    func test_normalize_runtime_config_payload_covers_boundaries_and_invalid_values() throws {
        let cfg = try ConfigCodec.normalizeRuntimeConfigPayload([
            "url": "https://wjx.cn/vm/demo.aspx",
            "target": "bad",
            "threads": "4",
            "submit_interval": ["1", "3"],
            "answer_duration": ["bad"],
            "answer_datetime_window": ["2026-02-10 09:00:00", "bad"],
            "random_ip_enabled": "yes",
            "proxy_source": "bad",
            "custom_proxy_api": "https://proxy.example",
            "random_ua_enabled": "false",
            "random_ua_ratios": ["wechat": 20, "mobile": 20, "pc": 20],
            "reverse_fill_format": "bad",
            "reverse_fill_start_row": "-2",
            "reverse_fill_threads": "0",
            "dimension_groups": ["服务", "服务", "未分组"],
            "ai_mode": "bad",
            "questions_info": "bad",
            "question_entries": [["question_type": "single", "rows": "bad"]],
        ])

        XCTAssertEqual(cfg.target, 1)
        XCTAssertEqual(cfg.threads, 4)
        XCTAssertEqual(cfg.submitInterval.0, 1)
        XCTAssertEqual(cfg.submitInterval.1, 3)
        XCTAssertEqual(cfg.answerDuration.0, 60)
        XCTAssertEqual(cfg.answerDuration.1, 120)
        XCTAssertEqual(cfg.answerDatetimeWindow.0, "2026-02-10 09:00:00")
        XCTAssertEqual(cfg.answerDatetimeWindow.1, "")
        XCTAssertTrue(cfg.randomIpEnabled)
        XCTAssertEqual(cfg.proxySource, "default")
        XCTAssertFalse(cfg.randomUaEnabled)
        XCTAssertEqual(cfg.randomUaRatios, ["wechat": 33, "mobile": 33, "pc": 34])
        XCTAssertEqual(cfg.reverseFillFormat, reverseFillFormatAuto)
        XCTAssertEqual(cfg.reverseFillStartRow, 1)
        XCTAssertEqual(cfg.reverseFillThreads, 1)
        XCTAssertEqual(cfg.dimensionGroups, ["服务"])
        XCTAssertEqual(cfg.aiMode, "free")
        XCTAssertEqual(cfg.questionsInfo.count, 0)
        XCTAssertEqual(cfg.questionEntries.count, 1)
        XCTAssertEqual(cfg.questionEntries[0].rows, 1)
    }

    // test_random_ip_enabled_survives_official_proxy_sources
    func test_random_ip_enabled_survives_official_proxy_sources() throws {
        for source in ["default", "benefit", "custom"] {
            let cfg = try ConfigCodec.normalizeRuntimeConfigPayload([
                "random_ip_enabled": true,
                "proxy_source": source,
            ])
            XCTAssertTrue(cfg.randomIpEnabled)
            XCTAssertEqual(cfg.proxySource, source)
        }
    }

    // test_runtime_config_payload_defaults_proxy_source_to_default
    func test_runtime_config_payload_defaults_proxy_source_to_default() throws {
        XCTAssertEqual(try ConfigCodec.normalizeRuntimeConfigPayload([:]).proxySource, "default")
        XCTAssertEqual(
            try ConfigCodec.normalizeRuntimeConfigPayload(["proxy_source": "bad"]).proxySource,
            "default"
        )
    }

    // test_answer_duration_legacy_single_value_expands_to_10_percent_range
    func test_answer_duration_legacy_single_value_expands_to_10_percent_range() throws {
        func duration(_ payload: [String: Any]) throws -> (Int, Int) {
            try ConfigCodec.normalizeRuntimeConfigPayload(payload).answerDuration
        }
        var result = try duration(["answer_duration": 90])
        XCTAssertEqual(result.0, 81); XCTAssertEqual(result.1, 99)
        result = try duration(["answer_duration": ["90"]])
        XCTAssertEqual(result.0, 81); XCTAssertEqual(result.1, 99)
        result = try duration(["answer_duration": [180, 180]])
        XCTAssertEqual(result.0, 162); XCTAssertEqual(result.1, 198)
        result = try duration([:])
        XCTAssertEqual(result.0, 60); XCTAssertEqual(result.1, 120)
        result = try duration(["answer_duration": 9999])
        XCTAssertEqual(result.0, 1620); XCTAssertEqual(result.1, 1800)
        result = try duration(["answer_duration": [1200, 9999]])
        XCTAssertEqual(result.0, 1200); XCTAssertEqual(result.1, 1800)
    }

    // test_random_ua_ratio_normalization_ignores_unknown_keys_and_rejects_invalid_values
    func test_random_ua_ratio_normalization_ignores_unknown_keys_and_rejects_invalid_values() throws {
        var cfg = try ConfigCodec.normalizeRuntimeConfigPayload([
            "random_ua_ratios": ["wechat": 100, "unknown": 0],
        ])
        XCTAssertEqual(cfg.randomUaRatios, ["wechat": 100, "mobile": 0, "pc": 0])

        cfg = try ConfigCodec.normalizeRuntimeConfigPayload([
            "random_ua_ratios": ["wechat": 50, "unknown": 50],
        ])
        XCTAssertEqual(cfg.randomUaRatios, ["wechat": 33, "mobile": 33, "pc": 34])

        cfg = try ConfigCodec.normalizeRuntimeConfigPayload([
            "random_ua_ratios": ["wechat": 200, "mobile": -100, "pc": 0],
        ])
        XCTAssertEqual(cfg.randomUaRatios, ["wechat": 33, "mobile": 33, "pc": 34])
    }

    // test_random_ua_legacy_keys_raise
    func test_random_ua_legacy_keys_raise() {
        XCTAssertThrowsError(try ConfigCodec.normalizeRuntimeConfigPayload([
            "random_ua_keys": ["pc_web"],
            "random_ua_ratios": ["wechat": 0, "mobile": 0, "pc": 100],
        ])) { error in
            XCTAssertTrue("\(error)".contains("该配置文件损坏"))
        }
    }

    // test_select_user_agent_from_ratios_handles_empty_unknown_and_valid_devices
    func test_select_user_agent_from_ratios_handles_empty_unknown_and_valid_devices() {
        XCTAssertNil(ConfigCodec.selectUserAgent(fromRatios: ["wechat": 0, "mobile": 0, "pc": 0]))
        let profile = ConfigCodec.selectUserAgent(fromRatios: ["wechat": 0, "mobile": 0, "pc": 1])
        XCTAssertNotNil(profile)
        XCTAssertFalse(profile?.ua.isEmpty ?? true)
        XCTAssertFalse(profile?.label.isEmpty ?? true)
        XCTAssertEqual(profile?.category, "pc")
        XCTAssertNil(ConfigCodec.selectUserAgent(fromRatios: ["unknown": 1]))
    }

    // test_select_user_agent_from_ratios_distribution_tracks_weights
    func test_select_user_agent_from_ratios_distribution_tracks_weights() {
        let rng = SeededRandomSource(seed: 20260616)
        var counts: [String: Int] = [:]

        for _ in 0..<10000 {
            let profile = ConfigCodec.selectUserAgent(
                fromRatios: ["wechat": 55, "mobile": 34, "pc": 11],
                rng: rng
            )
            XCTAssertNotNil(profile)
            counts[profile!.category, default: 0] += 1
        }

        XCTAssertEqual(counts.values.reduce(0, +), 10000)
        XCTAssertLessThan(abs(Double(counts["wechat"] ?? 0) / 10000 - 0.55), 0.02)
        XCTAssertLessThan(abs(Double(counts["mobile"] ?? 0) / 10000 - 0.34), 0.02)
        XCTAssertLessThan(abs(Double(counts["pc"] ?? 0) / 10000 - 0.11), 0.02)
    }

    // 对标 normalize_target_alpha 的夹紧行为
    func test_normalize_target_alpha_clamps_to_valid_range() {
        XCTAssertEqual(normalizeTargetAlpha(0.99), 0.95)
        XCTAssertEqual(normalizeTargetAlpha(0.1), 0.60)
        XCTAssertEqual(normalizeTargetAlpha(nil), 0.85)
        XCTAssertEqual(normalizeTargetAlpha("0.9"), 0.9)
    }
}
