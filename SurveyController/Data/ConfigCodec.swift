// 对标 software/core/config/codec.py
// 配置文件（schema v6）的序列化 / 反序列化 / 归一化，与桌面版配置文件互通。

import Foundation

public let currentConfigSchemaVersion = 6
public let configCorruptedMessage = "该配置文件损坏，请输入问卷链接/二维码重新配置"

/// 对标 UserAgentProfile dataclass。
public struct UserAgentProfile: @unchecked Sendable, Equatable {
    public let category: String
    public let presetKey: String
    public let ua: String
    public let label: String

    public init(category: String, presetKey: String, ua: String, label: String) {
        self.category = category
        self.presetKey = presetKey
        self.ua = ua
        self.label = label
    }
}

/// 配置编解码错误（对标 ValueError + 中文提示）。
public struct ConfigCodecError: Error, LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum ConfigCodec {
    static let defaultRandomUaRatios = ["wechat": 33, "mobile": 33, "pc": 34]
    static let userAgentDeviceToPresetKeys: [String: [String]] = [
        "wechat": ["wechat_android"],
        "mobile": ["mobile_android"],
        "pc": ["pc_web"],
    ]

    static let questionEntryFields: Set<String> = [
        "question_type", "probabilities", "texts", "rows", "option_count", "distribution_mode",
        "custom_weights", "question_num", "question_title", "survey_provider", "provider_question_id",
        "provider_page_id", "ai_enabled", "multi_text_blank_modes", "multi_text_blank_ai_flags",
        "multi_text_blank_int_ranges", "text_random_mode", "text_random_int_range", "option_fill_texts",
        "fillable_option_indices", "attached_option_selects", "is_location", "location_parts",
        "dimension", "psycho_bias",
    ]

    static let runtimeConfigFields: Set<String> = [
        "url", "survey_title", "survey_provider", "target", "threads", "submit_interval",
        "answer_duration", "answer_datetime_window", "random_ip_enabled", "proxy_source",
        "custom_proxy_api", "proxy_area_code", "random_ua_enabled", "random_ua_ratios",
        "fail_stop_enabled", "pause_on_aliyun_captcha", "reliability_mode_enabled",
        "psycho_target_alpha", "ai_mode", "ai_provider", "ai_api_key", "ai_base_url",
        "ai_api_protocol", "ai_model", "ai_system_prompt", "reverse_fill_enabled",
        "reverse_fill_source_path", "reverse_fill_format", "reverse_fill_start_row",
        "reverse_fill_threads", "answer_rules", "dimension_groups", "question_entries",
        "questions_info",
    ]

    // MARK: - UserAgent

    /// 对标 _normalize_user_agent_ratios：非法（负数/超100/总和≠100）整体回落默认。
    public static func normalizeUserAgentRatios(_ rawRatios: Any?) -> [String: Int] {
        guard let dict = rawRatios as? [String: Any] else { return defaultRandomUaRatios }
        var ratios: [String: Int] = [:]
        for deviceType in ["wechat", "mobile", "pc"] {
            let value = JSONCoercion.asInt(dict[deviceType], default: 0)
            if value < 0 || value > 100 { return defaultRandomUaRatios }
            ratios[deviceType] = value
        }
        if ratios.values.reduce(0, +) != 100 { return defaultRandomUaRatios }
        return ratios
    }

    /// 对标 _select_user_agent_from_ratios。
    public static func selectUserAgent(
        fromRatios ratios: [String: Int]?,
        rng: RandomSource = SystemRandomSource()
    ) -> UserAgentProfile? {
        let devices = userAgentDeviceToPresetKeys.keys.sorted().filter { deviceType in
            guard let keys = userAgentDeviceToPresetKeys[deviceType], !keys.isEmpty else { return false }
            let weight = max(0, JSONCoercion.asInt((ratios ?? [:])[deviceType], default: 0))
            return weight > 0
        }
        guard !devices.isEmpty else { return nil }
        let weights = devices.map { Double(max(0, JSONCoercion.asInt((ratios ?? [:])[$0], default: 0))) }
        guard let deviceType = rng.weightedChoice(devices, weights: weights) else { return nil }
        guard let uaKeys = userAgentDeviceToPresetKeys[deviceType], !uaKeys.isEmpty else { return nil }
        guard let key = rng.choice(uaKeys), let preset = userAgentPresets[key] else { return nil }
        let ua = preset.ua.trimmingCharacters(in: .whitespaces)
        guard !ua.isEmpty else { return nil }
        return UserAgentProfile(
            category: deviceType,
            presetKey: key,
            ua: ua,
            label: preset.label
        )
    }

    // MARK: - QuestionEntry

    /// 对标 serialize_question_entry。
    public static func serializeQuestionEntry(_ entry: QuestionEntry) -> [String: Any] {
        var probabilities = entry.probabilities
        if entry.distributionMode == "custom",
           probConfigIsUnset(probabilities),
           customWeightsHasPositive(entry.customWeights) {
            probabilities = entry.customWeights
        }
        return [
            "question_type": entry.questionType,
            "probabilities": probabilities ?? NSNull(),
            "texts": entry.texts ?? NSNull(),
            "rows": entry.rows,
            "option_count": entry.optionCount,
            "distribution_mode": entry.distributionMode,
            "custom_weights": entry.customWeights ?? NSNull(),
            "question_num": entry.questionNum ?? NSNull(),
            "question_title": entry.questionTitle ?? NSNull(),
            "survey_provider": entry.surveyProvider.rawValue,
            "provider_question_id": entry.providerQuestionId ?? "",
            "provider_page_id": entry.providerPageId ?? "",
            "ai_enabled": entry.aiEnabled,
            "multi_text_blank_modes": normalizeMultiTextBlankModes(entry.multiTextBlankModes),
            "multi_text_blank_ai_flags": entry.multiTextBlankAiFlags,
            "multi_text_blank_int_ranges": entry.multiTextBlankIntRanges,
            "text_random_mode": entry.textRandomMode.isEmpty ? textRandomNone : entry.textRandomMode,
            "text_random_int_range": entry.textRandomIntRange,
            "option_fill_texts": optionFillTextsToPayload(entry.optionFillTexts),
            "fillable_option_indices": entry.fillableOptionIndices ?? NSNull(),
            "attached_option_selects": entry.attachedOptionSelects,
            "is_location": entry.isLocation,
            "location_parts": entry.locationParts,
            "dimension": entry.dimension ?? NSNull(),
            "psycho_bias": entry.psychoBias.isEmpty ? "custom" : entry.psychoBias,
        ]
    }

    /// 对标 deserialize_question_entry（未知字段抛损坏错误）。
    public static func deserializeQuestionEntry(_ data: [String: Any]) throws -> QuestionEntry {
        let unknownKeys = Set(data.keys).subtracting(questionEntryFields)
        if !unknownKeys.isEmpty {
            throw ConfigCodecError(
                "\(configCorruptedMessage)：题目配置包含不支持的字段（\(unknownKeys.sorted().joined(separator: ", "))）"
            )
        }
        let modeRaw = JSONCoercion.asString(data["distribution_mode"]).isEmpty
            ? "random"
            : JSONCoercion.asString(data["distribution_mode"])

        var probabilities = data["probabilities"]
        var customWeights = nilIfNull(data["custom_weights"])
        if modeRaw == "custom", probConfigIsUnset(probabilities), customWeightsHasPositive(customWeights) {
            probabilities = customWeights
        }
        if modeRaw == "custom", isEmptyPayload(customWeights), let probList = probabilities as? [Any] {
            customWeights = probList
        }

        let providerQuestionId = JSONCoercion.asTrimmedString(data["provider_question_id"])
        let providerPageId = JSONCoercion.asTrimmedString(data["provider_page_id"])

        return QuestionEntry(
            questionType: JSONCoercion.asString(data["question_type"]).isEmpty
                ? "text"
                : JSONCoercion.asString(data["question_type"]),
            probabilities: nilIfNull(probabilities),
            texts: nilIfNull(data["texts"]).flatMap { $0 as? [Any] }.flatMap(toStringList),
            rows: JSONCoercion.asInt(data["rows"], default: 1),
            optionCount: JSONCoercion.asInt(data["option_count"], default: 0),
            distributionMode: modeRaw,
            customWeights: nilIfNull(customWeights),
            questionNum: intOrNil(data["question_num"]),
            questionTitle: stringOrNil(data["question_title"]),
            surveyProvider: ProviderType.normalizeProvider(JSONCoercion.asString(data["survey_provider"]), default: .wjx),
            providerQuestionId: providerQuestionId.isEmpty ? nil : providerQuestionId,
            providerPageId: providerPageId.isEmpty ? nil : providerPageId,
            aiEnabled: JSONCoercion.asBool(data["ai_enabled"], default: false),
            multiTextBlankModes: normalizeMultiTextBlankModes(data["multi_text_blank_modes"]),
            multiTextBlankAiFlags: normalizeMultiTextBlankAiFlags(data["multi_text_blank_ai_flags"]),
            multiTextBlankIntRanges: normalizeMultiTextBlankIntRanges(data["multi_text_blank_int_ranges"]),
            textRandomMode: JSONCoercion.asString(data["text_random_mode"]).isEmpty
                ? textRandomNone
                : JSONCoercion.asString(data["text_random_mode"]),
            textRandomIntRange: serializeRandomIntRange(data["text_random_int_range"]),
            optionFillTexts: payloadToOptionFillTexts(data["option_fill_texts"]),
            fillableOptionIndices: nilIfNull(data["fillable_option_indices"]).flatMap { $0 as? [Any] }.flatMap { list in
                list.compactMap { item -> Int? in
                    if let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.intValue }
                    if let text = item as? String { return Int(text.trimmingCharacters(in: .whitespaces)) }
                    return nil
                }
            },
            attachedOptionSelects: QuestionMetaNormalizer.normalizeDictList(data["attached_option_selects"]),
            isLocation: JSONCoercion.asBool(data["is_location"], default: false),
            locationParts: JSONCoercion.asStringList(data["location_parts"]),
            dimension: normalizeDimensionValue(data["dimension"]),
            psychoBias: normalizePsychoBias(data)
        )
    }

    /// 对标 clone_question_entries。
    public static func cloneQuestionEntries(_ entries: [QuestionEntry]) -> [QuestionEntry] {
        entries.compactMap { entry in
            try? deserializeQuestionEntry(serializeQuestionEntry(entry))
        }
    }

    // MARK: - RuntimeConfig

    /// 对标 build_runtime_config_snapshot：深拷贝快照。
    public static func buildRuntimeConfigSnapshot(
        _ config: RuntimeConfig,
        questionEntries: [QuestionEntry]? = nil,
        questionsInfo: [SurveyQuestionMeta]? = nil
    ) -> RuntimeConfig {
        var snapshot = config
        let defaultProvider = ProviderType.normalizeProvider(
            config.surveyProvider.rawValue,
            default: ProviderType.detectProvider(config.url)
        )
        snapshot.surveyProvider = defaultProvider
        let entrySource = questionEntries ?? config.questionEntries
        let infoSource = questionsInfo ?? config.questionsInfo
        snapshot.questionEntries = cloneQuestionEntries(entrySource)
        snapshot.questionsInfo = cloneSurveyQuestionMetas(infoSource, defaultProvider: defaultProvider)
        snapshot.answerRules = config.answerRules.map { $0 }
        snapshot.dimensionGroups = config.dimensionGroups
        snapshot.randomUaRatios = config.randomUaRatios
        return snapshot
    }

    /// 对标 normalize_runtime_config_payload / deserialize_runtime_config。
    public static func normalizeRuntimeConfigPayload(_ raw: [String: Any]) throws -> RuntimeConfig {
        var config = RuntimeConfig()

        let unknownKeys = Set(raw.keys).subtracting(runtimeConfigFields)
        if !unknownKeys.isEmpty {
            throw ConfigCodecError(
                "\(configCorruptedMessage)：配置包含不支持的字段（\(unknownKeys.sorted().joined(separator: ", "))）"
            )
        }

        config.url = JSONCoercion.asString(raw["url"])
        config.surveyTitle = JSONCoercion.asString(raw["survey_title"])
        config.surveyProvider = ProviderType.normalizeProvider(
            JSONCoercion.asString(raw["survey_provider"]),
            default: ProviderType.detectProvider(config.url)
        )
        config.target = JSONCoercion.asInt(raw["target"], default: 1)
        config.threads = JSONCoercion.asInt(raw["threads"], default: 1)
        config.submitInterval = tuplePair(raw["submit_interval"])
        config.answerDuration = normalizeAnswerDurationRange(raw["answer_duration"])
        config.answerDatetimeWindow = normalizeAnswerDatetimeWindow(raw["answer_datetime_window"])

        let customProxyApi = JSONCoercion.asTrimmedString(raw["custom_proxy_api"])
        var proxySource = JSONCoercion.asTrimmedString(raw["proxy_source"]).lowercased()
        if JSONCoercion.asTrimmedString(raw["proxy_source"]).isEmpty { proxySource = "default" }
        if !["default", "benefit", "custom"].contains(proxySource) { proxySource = "default" }
        config.proxySource = proxySource
        config.customProxyApi = customProxyApi
        config.randomIpEnabled = JSONCoercion.asBool(raw["random_ip_enabled"], default: false)

        if let rawAreaCode = raw["proxy_area_code"], !(rawAreaCode is NSNull) {
            config.proxyAreaCode = JSONCoercion.asString(rawAreaCode)
        } else {
            config.proxyAreaCode = nil
        }

        config.randomUaEnabled = JSONCoercion.asBool(raw["random_ua_enabled"], default: false)
        config.randomUaRatios = normalizeUserAgentRatios(raw["random_ua_ratios"])

        config.failStopEnabled = raw["fail_stop_enabled"] == nil ? true : JSONCoercion.asBool(raw["fail_stop_enabled"])
        config.pauseOnAliyunCaptcha = raw["pause_on_aliyun_captcha"] == nil ? true : JSONCoercion.asBool(raw["pause_on_aliyun_captcha"])
        config.reliabilityModeEnabled = raw["reliability_mode_enabled"] == nil ? true : JSONCoercion.asBool(raw["reliability_mode_enabled"])
        config.psychoTargetAlpha = normalizeTargetAlpha(raw["psycho_target_alpha"])

        config.reverseFillEnabled = JSONCoercion.asBool(raw["reverse_fill_enabled"], default: false)
        config.reverseFillSourcePath = JSONCoercion.asString(raw["reverse_fill_source_path"])
        let formatRaw = JSONCoercion.asTrimmedString(raw["reverse_fill_format"]).lowercased()
        config.reverseFillFormat = reverseFillFormats.contains(formatRaw) ? formatRaw : reverseFillFormatAuto
        config.reverseFillStartRow = max(1, JSONCoercion.asInt(raw["reverse_fill_start_row"], default: 1))
        config.reverseFillThreads = max(1, JSONCoercion.asInt(raw["reverse_fill_threads"], default: max(config.threads, 1)))

        config.answerRules = []
        config.dimensionGroups = normalizeDimensionGroups(raw["dimension_groups"])
        if let rawRules = raw["answer_rules"] as? [Any] {
            for item in rawRules {
                if let normalized = normalizeAnswerRule(item) {
                    config.answerRules.append(normalized)
                }
            }
        }

        let aiKeys: Set<String> = [
            "ai_mode", "ai_provider", "ai_api_key", "ai_base_url", "ai_api_protocol", "ai_model", "ai_system_prompt",
        ]
        let hasAiKeys = !aiKeys.isDisjoint(with: raw.keys)
        config.aiConfigPresent = hasAiKeys
        if hasAiKeys {
            var aiMode = JSONCoercion.asTrimmedString(raw["ai_mode"]).lowercased()
            if aiMode.isEmpty { aiMode = "free" }
            config.aiMode = ["free", "provider"].contains(aiMode) ? aiMode : "free"
            config.aiProvider = JSONCoercion.asString(raw["ai_provider"]).isEmpty ? "deepseek" : JSONCoercion.asString(raw["ai_provider"])
            config.aiApiKey = JSONCoercion.asString(raw["ai_api_key"])
            config.aiBaseUrl = JSONCoercion.asString(raw["ai_base_url"])
            config.aiApiProtocol = JSONCoercion.asString(raw["ai_api_protocol"]).isEmpty ? "auto" : JSONCoercion.asString(raw["ai_api_protocol"])
            config.aiModel = JSONCoercion.asString(raw["ai_model"])
            config.aiSystemPrompt = JSONCoercion.asString(raw["ai_system_prompt"])
        }

        config.questionEntries = []
        if let entriesData = raw["question_entries"] as? [Any] {
            for item in entriesData {
                guard let dict = item as? [String: Any] else { continue }
                let entry = try deserializeQuestionEntry(dict)
                if config.surveyProvider != .wjx,
                   let entryProviderId = entry.providerQuestionId, !entryProviderId.isEmpty,
                   entry.surveyProvider == .wjx {
                    var migrated = entry
                    migrated.surveyProvider = config.surveyProvider
                    config.questionEntries.append(migrated)
                } else {
                    config.questionEntries.append(entry)
                }
            }
        }

        if let questionsInfoData = raw["questions_info"] as? [Any] {
            var normalizedQuestions: [[String: Any]] = []
            for item in questionsInfoData {
                guard let dict = item as? [String: Any] else { continue }
                let metaFields = Set(dict.keys).subtracting(surveyQuestionMetaFields)
                if !metaFields.isEmpty {
                    throw ConfigCodecError(
                        "\(configCorruptedMessage)：题目元数据包含不支持的字段（\(metaFields.sorted().joined(separator: ", "))）"
                    )
                }
                normalizedQuestions.append(
                    QuestionMetaNormalizer.ensureQuestionProviderFields(dict, defaultProvider: config.surveyProvider)
                )
            }
            config.questionsInfo = ensureSurveyQuestionMetas(normalizedQuestions, defaultProvider: config.surveyProvider)
        } else {
            config.questionsInfo = []
        }

        let (sanitized, _) = sanitizeAnswerRules(config.answerRules, questionsInfo: config.questionsInfo)
        config.answerRules = sanitized
        return config
    }

    /// 对标 serialize_runtime_config。
    public static func serializeRuntimeConfig(_ config: RuntimeConfig) -> [String: Any] {
        [
            "url": config.url,
            "survey_title": config.surveyTitle,
            "survey_provider": config.surveyProvider.rawValue,
            "target": config.target,
            "threads": config.threads,
            "submit_interval": [config.submitInterval.0, config.submitInterval.1],
            "answer_duration": [config.answerDuration.0, config.answerDuration.1],
            "answer_datetime_window": [config.answerDatetimeWindow.0, config.answerDatetimeWindow.1],
            "random_ip_enabled": config.randomIpEnabled,
            "proxy_source": config.proxySource,
            "custom_proxy_api": config.customProxyApi,
            "proxy_area_code": config.proxyAreaCode ?? NSNull(),
            "random_ua_enabled": config.randomUaEnabled,
            "random_ua_ratios": config.randomUaRatios,
            "fail_stop_enabled": config.failStopEnabled,
            "pause_on_aliyun_captcha": config.pauseOnAliyunCaptcha,
            "reliability_mode_enabled": config.reliabilityModeEnabled,
            "psycho_target_alpha": config.psychoTargetAlpha,
            "ai_mode": config.aiMode,
            "ai_provider": config.aiProvider,
            "ai_api_key": config.aiApiKey,
            "ai_base_url": config.aiBaseUrl,
            "ai_api_protocol": config.aiApiProtocol,
            "ai_model": config.aiModel,
            "ai_system_prompt": config.aiSystemPrompt,
            "reverse_fill_enabled": config.reverseFillEnabled,
            "reverse_fill_source_path": config.reverseFillSourcePath,
            "reverse_fill_format": config.reverseFillFormat,
            "reverse_fill_start_row": config.reverseFillStartRow,
            "reverse_fill_threads": config.reverseFillThreads,
            "answer_rules": config.answerRules,
            "dimension_groups": config.dimensionGroups,
            "question_entries": config.questionEntries.map(serializeQuestionEntry),
            "questions_info": serializeSurveyQuestionMetas(config.questionsInfo),
        ]
    }

    public static func deserializeRuntimeConfig(_ payload: [String: Any]) throws -> RuntimeConfig {
        try normalizeRuntimeConfigPayload(payload)
    }

    /// 对标 _ensure_supported_config_payload（当前为直通实现）。
    public static func ensureSupportedConfigPayload(_ payload: [String: Any], configPath: String) -> [String: Any] {
        payload
    }

    // MARK: - 归一化辅助

    /// 对标 _prob_config_is_unset。
    static func probConfigIsUnset(_ value: Any?) -> Bool {
        if value == nil || value is NSNull { return true }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.doubleValue == -1
        }
        if let text = value as? String { return text == "-1" }
        if let list = value as? [Any] {
            if list.isEmpty { return true }
            return !list.contains { JSONCoercion.isPositiveNumber($0) }
        }
        return false
    }

    /// 对标 _custom_weights_has_positive：嵌套任意深度找正数。
    static func customWeightsHasPositive(_ weights: Any?) -> Bool {
        guard let list = weights as? [Any], !list.isEmpty else { return false }
        var stack: [Any] = list
        while let item = stack.popLast() {
            if let nested = item as? [Any] {
                stack.append(contentsOf: nested)
                continue
            }
            if JSONCoercion.isPositiveNumber(item) { return true }
        }
        return false
    }

    /// 对标 _normalize_psycho_bias。
    static func normalizePsychoBias(_ data: [String: Any]) -> String {
        let bias = JSONCoercion.asTrimmedString(data["psycho_bias"])
        if bias.isEmpty { return "custom" }
        return ["left", "center", "right"].contains(bias) ? bias : "custom"
    }

    /// 对标 _normalize_multi_text_blank_modes。
    static func normalizeMultiTextBlankModes(_ raw: Any?) -> [String] {
        guard let list = raw as? [Any] else { return [] }
        return list.map { item in
            let mode = JSONCoercion.asTrimmedString(item).lowercased()
            let value = mode.isEmpty ? textRandomNone : mode
            return textRandomModes.contains(value) ? value : textRandomNone
        }
    }

    /// 对标 _normalize_multi_text_blank_ai_flags。
    static func normalizeMultiTextBlankAiFlags(_ raw: Any?) -> [Bool] {
        guard let list = raw as? [Any] else { return [] }
        return list.map { JSONCoercion.asBool($0, default: false) }
    }

    /// 对标 _normalize_multi_text_blank_int_ranges。
    static func normalizeMultiTextBlankIntRanges(_ raw: Any?) -> [[Int]] {
        guard let list = raw as? [Any] else { return [] }
        return list.map { serializeRandomIntRange($0) }
    }

    /// 对标 _legacy_answer_duration_to_range：单值 ±10%。
    static func legacyAnswerDurationToRange(_ value: Int) -> (Int, Int) {
        let normalized = min(maxAnswerDurationSeconds, max(0, value))
        if normalized <= 0 { return defaultAnswerDurationRangeSeconds }
        let low = max(0, Int((Double(normalized) * 0.9).rounded()))
        let high = min(maxAnswerDurationSeconds, max(low, Int((Double(normalized) * 1.1).rounded())))
        return (low, high)
    }

    /// 对标 _normalize_answer_duration_range。
    static func normalizeAnswerDurationRange(_ value: Any?) -> (Int, Int) {
        if value == nil || value is NSNull { return defaultAnswerDurationRangeSeconds }
        if let list = value as? [Any] {
            if list.isEmpty { return defaultAnswerDurationRangeSeconds }
            if list.count >= 2 {
                let low = min(maxAnswerDurationSeconds, max(0, JSONCoercion.asInt(list[0], default: 0)))
                let high = min(maxAnswerDurationSeconds, max(low, JSONCoercion.asInt(list[1], default: 0)))
                if low == 0 && high == 0 { return defaultAnswerDurationRangeSeconds }
                if low == high { return legacyAnswerDurationToRange(low) }
                return (low, high)
            }
            return legacyAnswerDurationToRange(scalarDuration(list[0]) ?? 0)
        }
        guard let scalar = scalarDuration(value) else { return defaultAnswerDurationRangeSeconds }
        return legacyAnswerDurationToRange(scalar)
    }

    /// Python int(value) 语义：数字/整数字符串可解析，其余 nil（触发 except 回落默认）。
    static func scalarDuration(_ value: Any?) -> Int? {
        if let text = value as? String {
            return Int(text.trimmingCharacters(in: .whitespaces))
        }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.intValue
        }
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        return nil
    }

    /// 对标 _normalize_dimension_value："未分组" → nil。
    static func normalizeDimensionValue(_ raw: Any?) -> String? {
        let text = JSONCoercion.asTrimmedString(raw)
        if text.isEmpty || text == "未分组" { return nil }
        return text
    }

    /// 对标 _normalize_dimension_groups：去空、去"未分组"、去重。
    static func normalizeDimensionGroups(_ raw: Any?) -> [String] {
        guard let list = raw as? [Any] else { return [] }
        var groups: [String] = []
        var seen: Set<String> = []
        for item in list {
            guard let normalized = normalizeDimensionValue(item), !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            groups.append(normalized)
        }
        return groups
    }

    /// 对标 _tuple_pair。
    static func tuplePair(_ value: Any?) -> (Int, Int) {
        if let list = value as? [Any], list.count >= 2 {
            return (JSONCoercion.asInt(list[0]), JSONCoercion.asInt(list[1]))
        }
        return (0, 0)
    }
}

// MARK: - 私有辅助

let surveyQuestionMetaFields: Set<String> = [
    "num", "title", "display_num", "description", "type_code", "options", "rows", "row_texts", "page",
    "option_texts", "forced_option_index", "forced_option_text", "forced_texts", "fillable_options",
    "attached_option_selects", "has_attached_option_select", "is_location", "is_rating", "is_description",
    "rating_max", "text_inputs", "text_input_labels", "is_multi_text", "is_text_like", "is_slider_matrix",
    "has_jump", "jump_rules", "has_display_condition", "display_conditions", "has_dependent_display_logic",
    "controls_display_targets", "logic_parse_status", "question_media", "slider_min", "slider_max",
    "slider_step", "multi_min_limit", "multi_max_limit", "provider", "provider_question_id",
    "provider_page_id", "provider_type", "provider_page_raw", "unsupported", "unsupported_reason", "required",
]

func nilIfNull(_ value: Any?) -> Any? {
    (value == nil || value is NSNull) ? nil : value
}

func isEmptyPayload(_ value: Any?) -> Bool {
    guard let value else { return true }
    if value is NSNull { return true }
    if let list = value as? [Any] { return list.isEmpty }
    return false
}

func intOrNil(_ value: Any?) -> Int? {
    guard let value, !(value is NSNull) else { return nil }
    if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.intValue }
    if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespaces)) }
    return nil
}

func stringOrNil(_ value: Any?) -> String? {
    guard let value, !(value is NSNull) else { return nil }
    return JSONCoercion.asString(value)
}

func toStringList(_ value: Any?) -> [String]? {
    guard let list = value as? [Any] else { return nil }
    return list.map { item in item is NSNull ? "" : JSONCoercion.asString(item) }
}

/// option_fill_texts：元素可为字符串或 null（Swift 用 [Any?]，JSON 边界转 NSNull）。
func optionFillTextsToPayload(_ values: [Any?]?) -> Any {
    guard let values else { return NSNull() }
    return values.map { $0 ?? NSNull() }
}

func payloadToOptionFillTexts(_ payload: Any?) -> [Any?]? {
    guard let list = payload as? [Any] else { return nil }
    return list.map { $0 is NSNull ? nil : $0 }
}
