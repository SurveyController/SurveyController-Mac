// 对标 software/providers/http_logic.py
// 纯 HTTP 提交的问卷逻辑模拟器：显隐条件、跳题、提前结束。

import Foundation

public let supportedConditionModes: Set<String> = ["selected", "not_selected"]
let terminateJumpKeywords = ["结束作答", "结束答题", "结束填写", "终止作答", "停止作答"]

/// 对标 HttpLogicPlan。
public struct HttpLogicPlan: Sendable {
    public let actions: [AnswerAction]
    public let skippedQuestionNums: [Int]
    public let terminatedEarly: Bool

    public init(actions: [AnswerAction], skippedQuestionNums: [Int] = [], terminatedEarly: Bool = false) {
        self.actions = actions
        self.skippedQuestionNums = skippedQuestionNums
        self.terminatedEarly = terminatedEarly
    }
}

public enum HttpLogicPlanner {

    static func jumpRuleTerminatesSurvey(_ rule: [String: Any]) -> Bool {
        if rule["terminates_survey"] != nil {
            return JSONCoercion.asBool(rule["terminates_survey"])
        }
        let optionText = JSONCoercion.asTrimmedString(rule["option_text"])
        return !optionText.isEmpty && terminateJumpKeywords.contains { optionText.contains($0) }
    }

    static func orderedQuestions(_ questions: [SurveyQuestionMeta]) -> [SurveyQuestionMeta] {
        questions
            .filter { $0.num > 0 }
            .sorted { (lhs, rhs) in (lhs.page, lhs.num) < (rhs.page, rhs.num) }
    }

    /// 对标 question_has_survey_logic。
    public static func questionHasSurveyLogic(_ question: SurveyQuestionMeta) -> Bool {
        question.hasJump || question.hasDisplayCondition || question.hasDependentDisplayLogic
    }

    static func logicStatusIsCompleteEnough(_ question: SurveyQuestionMeta) -> Bool {
        let logicStatus = question.logicParseStatus.trimmingCharacters(in: .whitespaces).lowercased()
        if logicStatus == logicParseStatusComplete { return true }
        if logicStatus != logicParseStatusUnknown { return false }

        if question.hasJump && question.jumpRules.isEmpty { return false }
        if question.hasDisplayCondition && question.displayConditions.isEmpty { return false }
        if question.hasDependentDisplayLogic && question.controlsDisplayTargets.isEmpty { return false }
        return true
    }

    /// 对标 get_http_logic_fallback_reason：返回不支持纯 HTTP 提交的原因（空串 = 支持）。
    public static func fallbackReason(_ questions: [SurveyQuestionMeta]) -> String {
        let ordered = orderedQuestions(questions)
        let maxQuestionNum = ordered.map { $0.num }.max() ?? 0

        for question in ordered {
            let questionNum = question.num
            if questionNum <= 0 || !questionHasSurveyLogic(question) { continue }

            if !logicStatusIsCompleteEnough(question) {
                return "第\(questionNum)题逻辑规则未完整解析"
            }

            for condition in question.displayConditions {
                let sourceQuestionNum = JSONCoercion.asInt(condition["condition_question_num"])
                let conditionMode = JSONCoercion.asTrimmedString(condition["condition_mode"]).isEmpty
                    ? "selected"
                    : JSONCoercion.asTrimmedString(condition["condition_mode"])
                if sourceQuestionNum <= 0 {
                    return "第\(questionNum)题显隐条件缺少来源题号"
                }
                if sourceQuestionNum >= questionNum {
                    return "第\(questionNum)题显隐条件依赖未来题目"
                }
                if !supportedConditionModes.contains(conditionMode) {
                    return "第\(questionNum)题显隐条件模式不支持：\(conditionMode)"
                }
            }

            for target in question.controlsDisplayTargets {
                let targetQuestionNum = JSONCoercion.asInt(target["target_question_num"])
                let conditionMode = JSONCoercion.asTrimmedString(target["condition_mode"]).isEmpty
                    ? "selected"
                    : JSONCoercion.asTrimmedString(target["condition_mode"])
                if targetQuestionNum <= questionNum {
                    return "第\(questionNum)题控制显示规则存在回跳"
                }
                if !supportedConditionModes.contains(conditionMode) {
                    return "第\(questionNum)题控制显示模式不支持：\(conditionMode)"
                }
            }

            for rule in question.jumpRules {
                let jumpTarget = JSONCoercion.asInt(rule["jumpto"])
                if jumpRuleTerminatesSurvey(rule) { continue }
                if jumpTarget <= questionNum {
                    return "第\(questionNum)题跳题目标回跳到已过题目"
                }
                if maxQuestionNum > 0 && jumpTarget > maxQuestionNum + 1 {
                    return "第\(questionNum)题跳题目标超出问卷范围"
                }
            }
        }
        return ""
    }

    static func actionSelectedIndices(_ action: AnswerAction) -> Set<Int> {
        if action.kind == "matrix" {
            return Set(action.matrixIndices.filter { $0 >= 0 })
        }
        return Set(action.selectedIndices.filter { $0 >= 0 })
    }

    /// 对标 _condition_is_met。
    static func conditionIsMet(
        _ actionByQuestionNum: [Int: AnswerAction], _ condition: [String: Any]
    ) -> Bool {
        let sourceQuestionNum = JSONCoercion.asInt(condition["condition_question_num"])
        if sourceQuestionNum <= 0 { return false }
        guard let sourceAction = actionByQuestionNum[sourceQuestionNum] else { return false }

        let conditionMode = JSONCoercion.asTrimmedString(condition["condition_mode"]).isEmpty
            ? "selected"
            : JSONCoercion.asTrimmedString(condition["condition_mode"])
        let normalizedIndices = Set(JSONCoercion.asIntList(condition["condition_option_indices"]).filter { $0 >= 0 })
        let selectedIndices = actionSelectedIndices(sourceAction)

        if normalizedIndices.isEmpty { return conditionMode == "selected" }
        if conditionMode == "selected" { return !selectedIndices.isDisjoint(with: normalizedIndices) }
        if conditionMode == "not_selected" { return selectedIndices.isDisjoint(with: normalizedIndices) }
        return false
    }

    /// 对标 _question_is_visible：同一(来源,模式)组内任一命中即可，组间必须全部命中。
    static func questionIsVisible(
        _ question: SurveyQuestionMeta, _ actionByQuestionNum: [Int: AnswerAction]
    ) -> Bool {
        let conditions = question.displayConditions
        if conditions.isEmpty { return !question.hasDisplayCondition }

        var groupedConditions: [String: [[String: Any]]] = [:]
        for condition in conditions {
            let sourceQuestionNum = JSONCoercion.asInt(condition["condition_question_num"])
            if sourceQuestionNum <= 0 { continue }
            let mode = JSONCoercion.asTrimmedString(condition["condition_mode"]).isEmpty
                ? "selected"
                : JSONCoercion.asTrimmedString(condition["condition_mode"])
            groupedConditions["\(sourceQuestionNum):\(mode)", default: []].append(condition)
        }
        if groupedConditions.isEmpty { return !question.hasDisplayCondition }

        for grouped in groupedConditions.values {
            if !grouped.contains(where: { conditionIsMet(actionByQuestionNum, $0) }) {
                return false
            }
        }
        return true
    }

    /// 对标 _resolve_jump_target：返回 (跳转目标, 是否终止作答)。
    static func resolveJumpTarget(
        _ question: SurveyQuestionMeta, _ action: AnswerAction
    ) -> (target: Int?, terminates: Bool) {
        let selectedIndices = actionSelectedIndices(action)
        var unconditionalTarget: Int? = nil
        var unconditionalTerminates = false

        for rule in question.jumpRules {
            let jumpTarget = JSONCoercion.asInt(rule["jumpto"])
            if jumpTarget <= 0 { continue }
            let terminatesSurvey = jumpRuleTerminatesSurvey(rule)
            let optionIndex = JSONCoercion.asInt(rule["option_index"])
            if optionIndex < 0 {
                if unconditionalTarget == nil {
                    unconditionalTarget = jumpTarget
                    unconditionalTerminates = terminatesSurvey
                }
                continue
            }
            if selectedIndices.contains(optionIndex) {
                return (jumpTarget, terminatesSurvey)
            }
        }
        return (unconditionalTarget, unconditionalTerminates)
    }

    /// 对标 build_http_logic_plan（同步版本：Swift 构建器不涉及 IO）。
    public static func buildPlan(
        _ questions: [SurveyQuestionMeta],
        buildAction: (SurveyQuestionMeta) throws -> AnswerAction?,
        respectJumpLogic: Bool = true
    ) throws -> HttpLogicPlan {
        let ordered = orderedQuestions(questions)
        let fallbackReasonText = fallbackReason(ordered)
        if !fallbackReasonText.isEmpty {
            throw NSError(domain: "HttpLogicPlanner", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "\(fallbackReasonText)，暂不支持纯 HTTP 提交"])
        }

        let maxQuestionNum = ordered.map { $0.num }.max() ?? 0
        var actionByQuestionNum: [Int: AnswerAction] = [:]
        var actions: [AnswerAction] = []
        var skippedQuestionNums: [Int] = []
        var jumpTargetNum: Int? = nil

        for question in ordered {
            let questionNum = question.num
            if questionNum <= 0 { continue }

            if let target = jumpTargetNum {
                if questionNum < target {
                    skippedQuestionNums.append(questionNum)
                    continue
                }
                jumpTargetNum = nil
            }

            if !questionIsVisible(question, actionByQuestionNum) {
                skippedQuestionNums.append(questionNum)
                continue
            }

            guard let action = try buildAction(question) else {
                throw NSError(domain: "HttpLogicPlanner", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "第\(questionNum)题暂不支持纯 HTTP 提交"])
            }
            actionByQuestionNum[questionNum] = action
            actions.append(action)

            if respectJumpLogic {
                let (jumpTarget, terminatesSurvey) = resolveJumpTarget(question, action)
                guard let jumpTarget else { continue }
                if terminatesSurvey || jumpTarget > maxQuestionNum {
                    return HttpLogicPlan(
                        actions: actions,
                        skippedQuestionNums: skippedQuestionNums,
                        terminatedEarly: true
                    )
                }
                jumpTargetNum = jumpTarget
            }
        }
        return HttpLogicPlan(actions: actions, skippedQuestionNums: skippedQuestionNums, terminatedEarly: false)
    }
}
