// 对标 software/providers/contracts.py
// 题目元数据的统一契约：解析器产出、配置存储、答案生成共同使用的领域模型。

import Foundation

public let logicParseStatusComplete = "complete"
public let logicParseStatusNone = "none"
public let logicParseStatusUnknown = "unknown"

private let validLogicParseStatuses: Set<String> = [logicParseStatusComplete, logicParseStatusNone, logicParseStatusUnknown]
private let terminateKeywords = ["结束作答", "结束答题", "结束填写", "终止作答", "停止作答"]

/// 题目元数据（平台无关契约）。
public struct SurveyQuestionMeta: @unchecked Sendable {
    public var num: Int
    public var title: String
    public var displayNum: Int?
    public var description: String
    public var typeCode: String
    public var options: Int
    public var rows: Int
    public var rowTexts: [String]
    public var page: Int
    public var optionTexts: [String]
    public var forcedOptionIndex: Int?
    public var forcedOptionText: String
    public var forcedTexts: [String]
    public var fillableOptions: [Int]
    public var attachedOptionSelects: [[String: Any]]
    public var hasAttachedOptionSelect: Bool
    public var isLocation: Bool
    public var isRating: Bool
    public var isDescription: Bool
    public var ratingMax: Int
    public var textInputs: Int
    public var textInputLabels: [String]
    public var isMultiText: Bool
    public var isTextLike: Bool
    public var isSliderMatrix: Bool
    public var hasJump: Bool
    public var jumpRules: [[String: Any]]
    public var hasDisplayCondition: Bool
    public var displayConditions: [[String: Any]]
    public var hasDependentDisplayLogic: Bool
    public var controlsDisplayTargets: [[String: Any]]
    public var logicParseStatus: String
    public var questionMedia: [[String: Any]]
    public var sliderMin: Any?
    public var sliderMax: Any?
    public var sliderStep: Any?
    public var multiMinLimit: Any?
    public var multiMaxLimit: Any?
    public var provider: SurveyProvider
    public var providerQuestionId: String
    public var providerPageId: String
    public var providerType: String
    public var providerPageRaw: Any?
    public var unsupported: Bool
    public var unsupportedReason: String
    public var required: Bool

    public init(
        num: Int = 1,
        title: String = "",
        displayNum: Int? = nil,
        description: String = "",
        typeCode: String = "0",
        options: Int = 0,
        rows: Int = 1,
        rowTexts: [String] = [],
        page: Int = 1,
        optionTexts: [String] = [],
        forcedOptionIndex: Int? = nil,
        forcedOptionText: String = "",
        forcedTexts: [String] = [],
        fillableOptions: [Int] = [],
        attachedOptionSelects: [[String: Any]] = [],
        hasAttachedOptionSelect: Bool = false,
        isLocation: Bool = false,
        isRating: Bool = false,
        isDescription: Bool = false,
        ratingMax: Int = 0,
        textInputs: Int = 0,
        textInputLabels: [String] = [],
        isMultiText: Bool = false,
        isTextLike: Bool = false,
        isSliderMatrix: Bool = false,
        hasJump: Bool = false,
        jumpRules: [[String: Any]] = [],
        hasDisplayCondition: Bool = false,
        displayConditions: [[String: Any]] = [],
        hasDependentDisplayLogic: Bool = false,
        controlsDisplayTargets: [[String: Any]] = [],
        logicParseStatus: String = logicParseStatusUnknown,
        questionMedia: [[String: Any]] = [],
        sliderMin: Any? = nil,
        sliderMax: Any? = nil,
        sliderStep: Any? = nil,
        multiMinLimit: Any? = nil,
        multiMaxLimit: Any? = nil,
        provider: SurveyProvider = .wjx,
        providerQuestionId: String = "",
        providerPageId: String = "",
        providerType: String = "",
        providerPageRaw: Any? = nil,
        unsupported: Bool = false,
        unsupportedReason: String = "",
        required: Bool = false
    ) {
        self.num = num
        self.title = title
        self.displayNum = displayNum
        self.description = description
        self.typeCode = typeCode
        self.options = options
        self.rows = rows
        self.rowTexts = rowTexts
        self.page = page
        self.optionTexts = optionTexts
        self.forcedOptionIndex = forcedOptionIndex
        self.forcedOptionText = forcedOptionText
        self.forcedTexts = forcedTexts
        self.fillableOptions = fillableOptions
        self.attachedOptionSelects = attachedOptionSelects
        self.hasAttachedOptionSelect = hasAttachedOptionSelect
        self.isLocation = isLocation
        self.isRating = isRating
        self.isDescription = isDescription
        self.ratingMax = ratingMax
        self.textInputs = textInputs
        self.textInputLabels = textInputLabels
        self.isMultiText = isMultiText
        self.isTextLike = isTextLike
        self.isSliderMatrix = isSliderMatrix
        self.hasJump = hasJump
        self.jumpRules = jumpRules
        self.hasDisplayCondition = hasDisplayCondition
        self.displayConditions = displayConditions
        self.hasDependentDisplayLogic = hasDependentDisplayLogic
        self.controlsDisplayTargets = controlsDisplayTargets
        self.logicParseStatus = logicParseStatus
        self.questionMedia = questionMedia
        self.sliderMin = sliderMin
        self.sliderMax = sliderMax
        self.sliderStep = sliderStep
        self.multiMinLimit = multiMinLimit
        self.multiMaxLimit = multiMaxLimit
        self.provider = provider
        self.providerQuestionId = providerQuestionId
        self.providerPageId = providerPageId
        self.providerType = providerType
        self.providerPageRaw = providerPageRaw
        self.unsupported = unsupported
        self.unsupportedReason = unsupportedReason
        self.required = required
    }
}

/// 对标 ensure_survey_question_meta：宽容归一化构造（index 作为 num 兜底）。
public func ensureSurveyQuestionMeta(
    _ question: Any?,
    defaultProvider: SurveyProvider = .wjx,
    index: Int = 1
) -> SurveyQuestionMeta {
    let normalized: [String: Any]
    if let meta = question as? SurveyQuestionMeta {
        normalized = surveyQuestionMetaToDict(meta)
    } else if let dict = question as? [String: Any] {
        normalized = dict
    } else {
        normalized = [:]
    }
    return normalizeSurveyQuestion(normalized, provider: defaultProvider, index: index)
}

/// 对标 ensure_survey_question_metas。
public func ensureSurveyQuestionMetas(
    _ questions: [Any]?,
    defaultProvider: SurveyProvider = .wjx
) -> [SurveyQuestionMeta] {
    var normalized: [SurveyQuestionMeta] = []
    for (offset, question) in (questions ?? []).enumerated() {
        if question is SurveyQuestionMeta || question is [String: Any] {
            normalized.append(ensureSurveyQuestionMeta(question, defaultProvider: defaultProvider, index: offset + 1))
        }
    }
    return normalized
}

/// 对标 normalize_survey_questions。
public func normalizeSurveyQuestions(_ provider: SurveyProvider, _ questions: [Any]?) -> [SurveyQuestionMeta] {
    ensureSurveyQuestionMetas(questions, defaultProvider: provider)
}

/// 对标 serialize_survey_question_metas。
public func serializeSurveyQuestionMetas(_ questions: [Any?]) -> [[String: Any]] {
    questions.compactMap { question -> [String: Any]? in
        if let meta = question as? SurveyQuestionMeta { return surveyQuestionMetaToDict(meta) }
        if let dict = question as? [String: Any] { return dict }
        return nil
    }
}

/// 对标 clone_survey_question_metas：序列化→再归一化，得到与源完全解耦的副本。
public func cloneSurveyQuestionMetas(
    _ questions: [Any]?,
    defaultProvider: SurveyProvider = .wjx
) -> [SurveyQuestionMeta] {
    let serialized = serializeSurveyQuestionMetas(questions ?? [])
    return ensureSurveyQuestionMetas(serialized, defaultProvider: defaultProvider)
}

/// 对标 SurveyDefinition。
public struct SurveyDefinition: @unchecked Sendable {
    public let provider: SurveyProvider
    public let title: String
    public let questions: [SurveyQuestionMeta]

    public init(provider: SurveyProvider, title: String, questions: [Any]) {
        self.provider = ProviderType.normalizeProvider(provider.rawValue)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.questions = ensureSurveyQuestionMetas(questions, defaultProvider: self.provider)
    }
}

/// 对标 build_survey_definition。
public func buildSurveyDefinition(_ provider: SurveyProvider, _ title: String, _ questions: [Any]) -> SurveyDefinition {
    SurveyDefinition(provider: provider, title: title, questions: questions)
}

/// 对标 survey_question_meta_to_dict：完整序列化。
public func surveyQuestionMetaToDict(_ question: SurveyQuestionMeta) -> [String: Any] {
    [
        "num": question.num,
        "title": question.title,
        "display_num": question.displayNum ?? NSNull(),
        "description": question.description,
        "type_code": question.typeCode,
        "options": question.options,
        "rows": question.rows,
        "row_texts": question.rowTexts,
        "page": question.page,
        "option_texts": question.optionTexts,
        "forced_option_index": question.forcedOptionIndex ?? NSNull(),
        "forced_option_text": question.forcedOptionText,
        "forced_texts": question.forcedTexts,
        "fillable_options": question.fillableOptions,
        "attached_option_selects": QuestionMetaNormalizer.normalizeDictList(question.attachedOptionSelects),
        "has_attached_option_select": question.hasAttachedOptionSelect,
        "is_location": question.isLocation,
        "is_rating": question.isRating,
        "is_description": question.isDescription,
        "rating_max": question.ratingMax,
        "text_inputs": question.textInputs,
        "text_input_labels": question.textInputLabels,
        "is_multi_text": question.isMultiText,
        "is_text_like": question.isTextLike,
        "is_slider_matrix": question.isSliderMatrix,
        "has_jump": question.hasJump,
        "jump_rules": QuestionMetaNormalizer.normalizeJumpRules(question.jumpRules),
        "has_display_condition": question.hasDisplayCondition,
        "display_conditions": QuestionMetaNormalizer.normalizeDictList(question.displayConditions),
        "has_dependent_display_logic": question.hasDependentDisplayLogic,
        "controls_display_targets": QuestionMetaNormalizer.normalizeDictList(question.controlsDisplayTargets),
        "logic_parse_status": QuestionMetaNormalizer.normalizeLogicParseStatus(question.logicParseStatus),
        "question_media": QuestionMetaNormalizer.normalizeQuestionMediaList(question.questionMedia),
        "slider_min": question.sliderMin ?? NSNull(),
        "slider_max": question.sliderMax ?? NSNull(),
        "slider_step": question.sliderStep ?? NSNull(),
        "multi_min_limit": question.multiMinLimit ?? NSNull(),
        "multi_max_limit": question.multiMaxLimit ?? NSNull(),
        "provider": question.provider.rawValue,
        "provider_question_id": question.providerQuestionId,
        "provider_page_id": question.providerPageId,
        "provider_type": question.providerType,
        "provider_page_raw": question.providerPageRaw ?? NSNull(),
        "unsupported": question.unsupported,
        "unsupported_reason": question.unsupportedReason,
        "required": question.required,
    ]
}

/// 对标 contracts.py 里的各 _normalize_* 辅助函数。
public enum QuestionMetaNormalizer {
    static func asInt(_ value: Any?, default defaultValue: Int, minimum: Int? = nil) -> Int {
        var number = JSONCoercion.asInt(value, default: defaultValue)
        if let minimum { number = max(minimum, number) }
        return number
    }

    /// 对标 _normalize_text_list。
    public static func normalizeTextList(_ raw: Any?) -> [String] {
        guard let list = raw as? [Any] else { return [] }
        return list.map { item in
            (item is NSNull ? "" : JSONCoercion.asString(item)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// 对标 _normalize_dict_list：元素必须是字典（或可转换的契约对象）。
    public static func normalizeDictList(_ raw: Any?) -> [[String: Any]] {
        guard let list = raw as? [Any] else { return [] }
        return list.compactMap { item -> [String: Any]? in
            if let dict = item as? [String: Any] { return dict }
            if let meta = item as? SurveyQuestionMeta { return surveyQuestionMetaToDict(meta) }
            return nil
        }
    }

    /// 对标 _normalize_jump_rules：补充 terminates_survey 标记。
    public static func normalizeJumpRules(_ raw: Any?) -> [[String: Any]] {
        let rules = normalizeDictList(raw)
        var normalizedRules: [[String: Any]] = []
        for rule in rules {
            var normalizedRule = rule
            if normalizedRule["terminates_survey"] == nil {
                let optionText = JSONCoercion.asTrimmedString(normalizedRule["option_text"])
                normalizedRule["terminates_survey"] = !optionText.isEmpty && terminateKeywords.contains { optionText.contains($0) }
            } else {
                normalizedRule["terminates_survey"] = JSONCoercion.asBool(normalizedRule["terminates_survey"])
            }
            normalizedRules.append(normalizedRule)
        }
        return normalizedRules
    }

    /// 对标 _normalize_logic_parse_status。
    public static func normalizeLogicParseStatus(_ raw: Any?) -> String {
        let value = JSONCoercion.asTrimmedString(raw).lowercased()
        return validLogicParseStatuses.contains(value) ? value : logicParseStatusUnknown
    }

    /// 对标 _normalize_question_media_list：仅保留合法图片条目。
    public static func normalizeQuestionMediaList(_ raw: Any?) -> [[String: Any]] {
        guard let list = raw as? [Any] else { return [] }
        var items: [[String: Any]] = []
        for item in list {
            guard let dict = item as? [String: Any] else { continue }
            let kind = JSONCoercion.asTrimmedString(dict["kind"]).lowercased()
            if kind != "image" { continue }
            let scope = JSONCoercion.asTrimmedString(dict["scope"]).lowercased()
            guard ["title", "option", "row"].contains(scope) else { continue }
            let sourceUrl = JSONCoercion.asTrimmedString(dict["source_url"])
            if sourceUrl.isEmpty { continue }
            let rawIndex = dict["index"]
            var normalizedIndex: Int? = nil
            if scope != "title" {
                if rawIndex == nil || rawIndex is NSNull { continue }
                let index = JSONCoercion.asInt(rawIndex, default: -1)
                if index < 0 { continue }
                normalizedIndex = index
            }
            let label = JSONCoercion.asTrimmedString(dict["label"])
            items.append([
                "kind": "image",
                "scope": scope,
                "index": normalizedIndex ?? NSNull(),
                "source_url": sourceUrl,
                "label": label,
            ])
        }
        return items
    }

    /// 对标 _infer_logic_parse_status。
    static func inferLogicParseStatus(_ normalized: [String: Any]) -> String {
        if normalized["logic_parse_status"] != nil {
            let explicit = JSONCoercion.asTrimmedString(normalized["logic_parse_status"]).lowercased()
            return validLogicParseStatuses.contains(explicit) ? explicit : logicParseStatusUnknown
        }
        let hasLogic = JSONCoercion.asBool(normalized["has_jump"])
            || JSONCoercion.asBool(normalized["has_display_condition"])
            || JSONCoercion.asBool(normalized["has_dependent_display_logic"])
        if !hasLogic { return logicParseStatusNone }
        let hasParsedLogic = !normalizeDictList(normalized["jump_rules"]).isEmpty
            || !normalizeDictList(normalized["display_conditions"]).isEmpty
            || !normalizeDictList(normalized["controls_display_targets"]).isEmpty
        return hasParsedLogic ? logicParseStatusComplete : logicParseStatusUnknown
    }

    /// 对标 _ensure_question_provider_fields。
    public static func ensureQuestionProviderFields(
        _ item: [String: Any],
        defaultProvider: SurveyProvider = .wjx
    ) -> [String: Any] {
        var normalized = item
        normalized["provider"] = ProviderType.normalizeProvider(
            JSONCoercion.asString(normalized["provider"]),
            default: defaultProvider
        ).rawValue
        normalized["provider_question_id"] = JSONCoercion.asTrimmedString(normalized["provider_question_id"])
        normalized["provider_page_id"] = JSONCoercion.asTrimmedString(normalized["provider_page_id"])
        normalized["provider_type"] = JSONCoercion.asTrimmedString(normalized["provider_type"])
        if normalized["provider_page_raw"] == nil { normalized["provider_page_raw"] = NSNull() }
        normalized["unsupported"] = JSONCoercion.asBool(normalized["unsupported"], default: false)
        normalized["unsupported_reason"] = JSONCoercion.asTrimmedString(normalized["unsupported_reason"])
        return normalized
    }
}

/// 对标 _normalize_question：宽容归一化的核心。
func normalizeSurveyQuestion(_ question: [String: Any], provider: SurveyProvider, index: Int) -> SurveyQuestionMeta {
    let pageNumber = QuestionMetaNormalizer.asInt(question["page"], default: 1, minimum: 1)
    let questionNumber = QuestionMetaNormalizer.asInt(question["num"], default: index, minimum: 1)

    var displayNumber: Int? = nil
    let rawDisplayNum = question["display_num"]
    if rawDisplayNum != nil && !(rawDisplayNum is NSNull) {
        // Python：int(raw) 失败 → None；数值本身（含 -1）保留
        if let text = rawDisplayNum as? String {
            displayNumber = Int(text.trimmingCharacters(in: .whitespaces))
        } else if let number = rawDisplayNum as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            displayNumber = number.intValue
        }
    }

    let optionTexts = QuestionMetaNormalizer.normalizeTextList(question["option_texts"])
    let rowTexts = QuestionMetaNormalizer.normalizeTextList(question["row_texts"])
    let textInputLabels = QuestionMetaNormalizer.normalizeTextList(question["text_input_labels"])
    let forcedTexts = QuestionMetaNormalizer.normalizeTextList(question["forced_texts"])

    let optionCount = QuestionMetaNormalizer.asInt(question["options"], default: optionTexts.count, minimum: 0)
    let rowCount = QuestionMetaNormalizer.asInt(question["rows"], default: max(rowTexts.count, 1), minimum: 1)

    let normalizedProvider = ProviderType.normalizeProvider(
        JSONCoercion.asString(question["provider"]),
        default: provider
    )

    var fillableOptions: [Int] = []
    if let rawList = question["fillable_options"] as? [Any] {
        for raw in rawList {
            let value = JSONCoercion.asInt(raw, default: Int.min)
            if value != Int.min { fillableOptions.append(value) }
        }
    }

    let providerType = JSONCoercion.asTrimmedString(question["provider_type"]).isEmpty
        ? JSONCoercion.asTrimmedString(question["type_code"])
        : JSONCoercion.asTrimmedString(question["provider_type"])

    let isDescription = JSONCoercion.asBool(question["is_description"]) || providerType.lowercased() == "description"
    var unsupported = JSONCoercion.asBool(question["unsupported"]) && !isDescription
    var unsupportedReason = JSONCoercion.asTrimmedString(question["unsupported_reason"])
    if unsupported && unsupportedReason.isEmpty {
        unsupportedReason = "当前平台暂不支持该题型"
    }

    var forcedOptionIndex: Int? = nil
    let rawForcedIndex = question["forced_option_index"]
    if rawForcedIndex != nil && !(rawForcedIndex is NSNull) {
        if let text = rawForcedIndex as? String {
            forcedOptionIndex = Int(text.trimmingCharacters(in: .whitespaces))
        } else if let number = rawForcedIndex as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            forcedOptionIndex = number.intValue
        }
    }

    let isRating = JSONCoercion.asBool(question["is_rating"])
    let ratingMax = QuestionMetaNormalizer.asInt(
        question["rating_max"],
        default: isRating ? optionCount : 0,
        minimum: 0
    )

    let typeCodeRaw = JSONCoercion.asTrimmedString(question["type_code"])
    let rawProviderPageRaw = question["provider_page_raw"]

    return SurveyQuestionMeta(
        num: questionNumber,
        title: JSONCoercion.asTrimmedString(question["title"]),
        displayNum: displayNumber,
        description: JSONCoercion.asTrimmedString(question["description"]),
        typeCode: typeCodeRaw.isEmpty ? "0" : typeCodeRaw,
        options: optionCount,
        rows: rowCount,
        rowTexts: rowTexts,
        page: pageNumber,
        optionTexts: optionTexts,
        forcedOptionIndex: forcedOptionIndex,
        forcedOptionText: JSONCoercion.asTrimmedString(question["forced_option_text"]),
        forcedTexts: forcedTexts,
        fillableOptions: fillableOptions,
        attachedOptionSelects: QuestionMetaNormalizer.normalizeDictList(question["attached_option_selects"]),
        hasAttachedOptionSelect: JSONCoercion.asBool(question["has_attached_option_select"])
            || !(question["attached_option_selects"] as? [Any] ?? []).isEmpty,
        isLocation: JSONCoercion.asBool(question["is_location"]),
        isRating: isRating,
        isDescription: isDescription,
        ratingMax: ratingMax,
        textInputs: QuestionMetaNormalizer.asInt(question["text_inputs"], default: 0, minimum: 0),
        textInputLabels: textInputLabels,
        isMultiText: JSONCoercion.asBool(question["is_multi_text"]),
        isTextLike: JSONCoercion.asBool(question["is_text_like"]),
        isSliderMatrix: JSONCoercion.asBool(question["is_slider_matrix"]),
        hasJump: JSONCoercion.asBool(question["has_jump"]),
        jumpRules: QuestionMetaNormalizer.normalizeJumpRules(question["jump_rules"]),
        hasDisplayCondition: JSONCoercion.asBool(question["has_display_condition"]),
        displayConditions: QuestionMetaNormalizer.normalizeDictList(question["display_conditions"]),
        hasDependentDisplayLogic: JSONCoercion.asBool(question["has_dependent_display_logic"]),
        controlsDisplayTargets: QuestionMetaNormalizer.normalizeDictList(question["controls_display_targets"]),
        logicParseStatus: QuestionMetaNormalizer.inferLogicParseStatus(question),
        questionMedia: QuestionMetaNormalizer.normalizeQuestionMediaList(question["question_media"]),
        sliderMin: rawIsNil(question["slider_min"]) ? nil : question["slider_min"],
        sliderMax: rawIsNil(question["slider_max"]) ? nil : question["slider_max"],
        sliderStep: rawIsNil(question["slider_step"]) ? nil : question["slider_step"],
        multiMinLimit: rawIsNil(question["multi_min_limit"]) ? nil : question["multi_min_limit"],
        multiMaxLimit: rawIsNil(question["multi_max_limit"]) ? nil : question["multi_max_limit"],
        provider: normalizedProvider,
        providerQuestionId: JSONCoercion.asTrimmedString(question["provider_question_id"]).isEmpty
            ? String(questionNumber)
            : JSONCoercion.asTrimmedString(question["provider_question_id"]),
        providerPageId: JSONCoercion.asTrimmedString(question["provider_page_id"]).isEmpty
            ? String(pageNumber)
            : JSONCoercion.asTrimmedString(question["provider_page_id"]),
        providerType: providerType,
        providerPageRaw: rawIsNil(rawProviderPageRaw) ? nil : rawProviderPageRaw,
        unsupported: unsupported,
        unsupportedReason: unsupportedReason,
        required: JSONCoercion.asBool(question["required"])
    )
}

private func rawIsNil(_ value: Any?) -> Bool {
    value == nil || value is NSNull
}
