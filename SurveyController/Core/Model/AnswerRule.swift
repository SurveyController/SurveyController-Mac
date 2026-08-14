// 对标 software/core/questions/consistency.py（规则归一化与清洗部分）
// 一致性规则：如果条件题选中某选项，则目标题必须/不能选某些选项。

import Foundation

public let conditionModes: Set<String> = ["selected", "not_selected"]
public let actionModes: Set<String> = ["must_select", "must_not_select"]
/// 支持条件规则的题型（3 多选 / 4 单选 / 5 量表 / 6 矩阵）。
public let supportedRuleTypeCodes: Set<String> = ["3", "4", "5", "6"]

/// 对标 AnswerRule dataclass。
public struct AnswerRule: @unchecked Sendable, Equatable {
    public var id: String
    public var conditionQuestionNum: Int
    public var conditionMode: String
    public var conditionOptionIndices: [Int]
    public var targetQuestionNum: Int
    public var actionMode: String
    public var targetOptionIndices: [Int]
    public var conditionRowIndex: Int?
    public var targetRowIndex: Int?

    public init(
        id: String,
        conditionQuestionNum: Int,
        conditionMode: String,
        conditionOptionIndices: [Int],
        targetQuestionNum: Int,
        actionMode: String,
        targetOptionIndices: [Int],
        conditionRowIndex: Int? = nil,
        targetRowIndex: Int? = nil
    ) {
        self.id = id
        self.conditionQuestionNum = conditionQuestionNum
        self.conditionMode = conditionMode
        self.conditionOptionIndices = conditionOptionIndices
        self.targetQuestionNum = targetQuestionNum
        self.actionMode = actionMode
        self.targetOptionIndices = targetOptionIndices
        self.conditionRowIndex = conditionRowIndex
        self.targetRowIndex = targetRowIndex
    }

    /// 对标 normalize_rule_dict 产出的字典形状。
    public func toDict() -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "condition_question_num": conditionQuestionNum,
            "condition_mode": conditionMode,
            "condition_option_indices": conditionOptionIndices,
            "target_question_num": targetQuestionNum,
            "action_mode": actionMode,
            "target_option_indices": targetOptionIndices,
        ]
        if let conditionRowIndex { result["condition_row_index"] = conditionRowIndex }
        if let targetRowIndex { result["target_row_index"] = targetRowIndex }
        return result
    }
}

/// 对标 _to_int_list：去重、去负、升序。
func toIntList(_ values: Any?) -> [Int] {
    guard let list = values as? [Any] else { return [] }
    var result: [Int] = []
    var seen: Set<Int> = []
    for item in list {
        let index = JSONCoercion.asInt(item, default: -1)
        if index < 0 || seen.contains(index) { continue }
        seen.insert(index)
        result.append(index)
    }
    return result.sorted()
}

/// 对标 normalize_rule_dict：非法规则返回 nil。
public func normalizeAnswerRule(_ raw: Any?) -> [String: Any]? {
    guard let dict = raw as? [String: Any] else { return nil }
    let conditionQuestionNum = JSONCoercion.asInt(dict["condition_question_num"], default: -1)
    let targetQuestionNum = JSONCoercion.asInt(dict["target_question_num"], default: -1)
    let conditionMode = JSONCoercion.asTrimmedString(dict["condition_mode"])
    let actionMode = JSONCoercion.asTrimmedString(dict["action_mode"])
    if conditionQuestionNum <= 0 || targetQuestionNum <= 0 { return nil }
    if !conditionModes.contains(conditionMode) { return nil }
    if !actionModes.contains(actionMode) { return nil }
    let conditionOptionIndices = toIntList(dict["condition_option_indices"])
    let targetOptionIndices = toIntList(dict["target_option_indices"])
    if conditionOptionIndices.isEmpty || targetOptionIndices.isEmpty { return nil }

    var conditionRowIndex: Int? = nil
    if let rawCri = dict["condition_row_index"], !(rawCri is NSNull) {
        let cri = JSONCoercion.asInt(rawCri, default: -1)
        if cri >= 0 { conditionRowIndex = cri }
    }
    var targetRowIndex: Int? = nil
    if let rawTri = dict["target_row_index"], !(rawTri is NSNull) {
        let tri = JSONCoercion.asInt(rawTri, default: -1)
        if tri >= 0 { targetRowIndex = tri }
    }

    let ruleId = JSONCoercion.asTrimmedString(dict["id"]).isEmpty
        ? "rule-\(conditionQuestionNum)-\(targetQuestionNum)-\(conditionOptionIndices.count)-\(targetOptionIndices.count)"
        : JSONCoercion.asTrimmedString(dict["id"])

    var result: [String: Any] = [
        "id": ruleId,
        "condition_question_num": conditionQuestionNum,
        "condition_mode": conditionMode,
        "condition_option_indices": conditionOptionIndices,
        "target_question_num": targetQuestionNum,
        "action_mode": actionMode,
        "target_option_indices": targetOptionIndices,
    ]
    if let conditionRowIndex { result["condition_row_index"] = conditionRowIndex }
    if let targetRowIndex { result["target_row_index"] = targetRowIndex }
    return result
}

/// 对标 question_supports_answer_rule。
public func questionSupportsAnswerRule(_ question: SurveyQuestionMeta) -> Bool {
    let typeCode = question.typeCode.trimmingCharacters(in: .whitespaces)
    return supportedRuleTypeCodes.contains(typeCode)
}

/// 对标 sanitize_answer_rules：归一化 + 按题目元数据剔除不支持规则。
/// 返回（清洗后规则, 统计{invalid, unsupported}）。
public func sanitizeAnswerRules(
    _ answerRules: [[String: Any]]?,
    questionsInfo: [SurveyQuestionMeta]? = nil
) -> (rules: [[String: Any]], stats: [String: Int]) {
    var stats = ["invalid": 0, "unsupported": 0]
    var sanitized: [[String: Any]] = []

    var questionMap: [Int: SurveyQuestionMeta] = [:]
    for item in questionsInfo ?? [] {
        if item.num > 0 { questionMap[item.num] = item }
    }
    let hasQuestionInfo = !questionMap.isEmpty

    for item in answerRules ?? [] {
        guard let normalized = normalizeAnswerRule(item) else {
            stats["invalid", default: 0] += 1
            continue
        }
        if hasQuestionInfo {
            let conditionInfo = questionMap[JSONCoercion.asInt(normalized["condition_question_num"], default: 0)]
            let targetInfo = questionMap[JSONCoercion.asInt(normalized["target_question_num"], default: 0)]
            guard let conditionInfo, let targetInfo else {
                stats["unsupported", default: 0] += 1
                continue
            }
            if !questionSupportsAnswerRule(conditionInfo) || !questionSupportsAnswerRule(targetInfo) {
                stats["unsupported", default: 0] += 1
                continue
            }
        }
        sanitized.append(normalized)
    }
    return (sanitized, stats)
}
