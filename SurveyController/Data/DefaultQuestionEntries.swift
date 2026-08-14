// 对标 software/core/questions/default_builder.py（build_default_question_entries）
// 解析出的题目 → 默认作答配置条目。

import Foundation

public enum DefaultQuestionEntries {

    /// 按题目元数据生成默认 QuestionEntry（概率 -1 = 均匀随机）。
    public static func build(from questions: [SurveyQuestionMeta]) -> [QuestionEntry] {
        questions.map { question in
            let entryType = entryType(for: question)
            return QuestionEntry(
                questionType: entryType,
                probabilities: entryType == "multiple" ? [-1.0] : -1,
                texts: entryType == "text" || entryType == "multi_text"
                    ? [question.textInputs > 1 ? defaultFillText : defaultFillText]
                    : nil,
                rows: max(1, question.rows),
                optionCount: question.options,
                questionNum: question.num,
                questionTitle: question.title,
                surveyProvider: question.provider,
                providerQuestionId: question.providerQuestionId,
                providerPageId: question.providerPageId,
                multiTextBlankModes: entryType == "multi_text"
                    ? [String](repeating: textRandomNone, count: max(2, question.textInputs))
                    : [],
                isLocation: question.isLocation || entryType == "location"
            )
        }
    }

    /// 题型映射（对标 wjx 答案构建器的 entry_type 分发）。
    public static func entryType(for question: SurveyQuestionMeta) -> String {
        if question.isLocation { return "location" }
        if question.unsupported || question.isDescription { return "unsupported" }
        if question.isSliderMatrix { return "matrix" }
        switch question.typeCode {
        case "3": return "single"
        case "4": return "multiple"
        case "5": return question.isRating ? "score" : "scale"
        case "6": return "matrix"
        case "7": return "dropdown"
        case "8": return "slider"
        case "11": return "order"
        case "1", "2", "9":
            return question.isMultiText || question.textInputs > 1 ? "multi_text" : "text"
        default:
            if question.isTextLike { return question.textInputs > 1 ? "multi_text" : "text" }
            return "single"
        }
    }
}
