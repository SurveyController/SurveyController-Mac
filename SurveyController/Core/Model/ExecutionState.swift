// 对标 software/core/task/task_context.py（ExecutionState，v0.1 子集）
// 运行时可变状态：由引擎 actor 持有（Swift 并发替代 Python 的锁）。

import Foundation

/// 单次运行的可变状态。
public struct ExecutionState: @unchecked Sendable {
    public var config: ExecutionConfig
    /// 已答题目记录：题号 → 已选选项下标（一致性规则用）
    public var answeredChoices: [Int: Set<Int>] = [:]
    /// 免费AI 预填充缓存：thread → (题号 → [String])
    public var freeAiPrefillByThread: [String: [Int: [String]]] = [:]

    public init(config: ExecutionConfig) {
        self.config = config
    }

    public mutating func recordChoice(questionNum: Int, indices: Set<Int>) {
        answeredChoices[questionNum] = indices
    }

    public func getFreeAiPrefillAnswer(threadName: String, questionNum: Int) -> [String]? {
        freeAiPrefillByThread[threadName]?[questionNum]
    }

    public mutating func setFreeAiPrefillAnswer(threadName: String, questionNum: Int, answers: [String]) {
        freeAiPrefillByThread[threadName, default: [:]][questionNum] = answers
    }

    public mutating func clearFreeAiPrefillAnswers(threadName: String) {
        freeAiPrefillByThread[threadName] = nil
    }
}

/// 一致性规则约束（对标 get_multiple_rule_constraint / apply_single_like_consistency 的查询部分）。
public enum ConsistencyRules {
    /// 对标 get_multiple_rule_constraint：返回（必选, 禁选）。
    public static func multipleConstraint(
        _ rules: [[String: Any]], questionNum: Int, optionCount: Int
    ) -> (mustSelect: [Int], mustNotSelect: [Int]) {
        var mustSelect: Set<Int> = []
        var mustNotSelect: Set<Int> = []
        for rule in rules {
            guard JSONCoercion.asInt(rule["target_question_num"]) == questionNum else { continue }
            let targetIndices = JSONCoercion.asIntList(rule["target_option_indices"])
            let mode = JSONCoercion.asTrimmedString(rule["action_mode"])
            let targetRow = rule["target_row_index"] == nil ? nil : JSONCoercion.asInt(rule["target_row_index"])
            if targetRow != nil { continue } // 行级规则暂不作用于多选
            if mode == "must_select" {
                mustSelect.formUnion(targetIndices)
            } else if mode == "must_not_select" {
                mustNotSelect.formUnion(targetIndices)
            }
        }
        let required = mustSelect.filter { (0..<optionCount).contains($0) }.sorted()
        var blocked = mustNotSelect.filter { (0..<optionCount).contains($0) }
        blocked.subtract(required) // 必选优先
        return (required, Array(blocked).sorted())
    }

    /// 对标条件判定：来源题是否满足条件模式。
    public static func conditionMet(
        _ rule: [String: Any], answeredChoices: [Int: Set<Int>]
    ) -> Bool {
        let sourceNum = JSONCoercion.asInt(rule["condition_question_num"])
        guard sourceNum > 0, let selected = answeredChoices[sourceNum] else { return false }
        let indices = Set(JSONCoercion.asIntList(rule["condition_option_indices"]))
        let mode = JSONCoercion.asTrimmedString(rule["condition_mode"])
        if indices.isEmpty { return mode == "selected" }
        if mode == "selected" { return !selected.isDisjoint(with: indices) }
        if mode == "not_selected" { return selected.isDisjoint(with: indices) }
        return false
    }

    /// 对标 apply_single_like_consistency：满足规则的条件下强制目标选项。
    public static func singleLikeConstraint(
        _ rules: [[String: Any]], questionNum: Int, answeredChoices: [Int: Set<Int>]
    ) -> Int? {
        for rule in rules {
            guard JSONCoercion.asInt(rule["target_question_num"]) == questionNum,
                  JSONCoercion.asTrimmedString(rule["action_mode"]) == "must_select",
                  conditionMet(rule, answeredChoices: answeredChoices) else { continue }
            let indices = JSONCoercion.asIntList(rule["target_option_indices"])
            if let first = indices.first, first >= 0 { return first }
        }
        return nil
    }
}
