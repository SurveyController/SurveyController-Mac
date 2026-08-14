// 对标 software/providers/answering/actions.py
// 平台无关的答案动作：答案生成器产出，各平台编解码器消费。

import Foundation

/// 单个题目的作答动作。
public struct AnswerAction: @unchecked Sendable, Equatable {
    public var questionNum: Int
    public var kind: String
    public var questionId: String
    public var rootIndex: Int
    public var inputType: String
    public var selectedIndices: [Int]
    public var matrixIndices: [Int]
    public var scalarValue: Int?
    public var textValues: [String]
    public var sliderValue: Double?
    /// (选项下标, 填空文本)
    public var optionFillTexts: [(Int, String)]
    public var selectedTexts: [String]
    public var recordType: String
    /// (题号, 选项下标, 矩阵列下标?) —— 分布收敛运行时记录用
    public var pendingDistributionChoices: [(Int, Int, Int?)]

    public init(
        questionNum: Int = 0,
        kind: String = "",
        questionId: String = "",
        rootIndex: Int = -1,
        inputType: String = "",
        selectedIndices: [Int] = [],
        matrixIndices: [Int] = [],
        scalarValue: Int? = nil,
        textValues: [String] = [],
        sliderValue: Double? = nil,
        optionFillTexts: [(Int, String)] = [],
        selectedTexts: [String] = [],
        recordType: String = "",
        pendingDistributionChoices: [(Int, Int, Int?)] = []
    ) {
        self.questionNum = questionNum
        self.kind = kind
        self.questionId = questionId
        self.rootIndex = rootIndex
        self.inputType = inputType
        self.selectedIndices = selectedIndices
        self.matrixIndices = matrixIndices
        self.scalarValue = scalarValue
        self.textValues = textValues
        self.sliderValue = sliderValue
        self.optionFillTexts = optionFillTexts
        self.selectedTexts = selectedTexts
        self.recordType = recordType
        self.pendingDistributionChoices = pendingDistributionChoices
    }

    /// 对标 action_payload。
    public func payload() -> [String: Any] {
        [
            "questionNum": questionNum,
            "questionId": questionId,
            "rootIndex": rootIndex,
            "kind": kind,
            "inputType": inputType,
            "selectedIndices": selectedIndices,
            "matrixIndices": matrixIndices,
            "scalarValue": scalarValue ?? NSNull(),
            "textValues": textValues,
            "sliderValue": sliderValue ?? NSNull(),
            "optionFillTexts": optionFillTexts
                .filter { !$1.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { ["optionIndex": $0, "value": $1] },
        ]
    }
}

// 元组数组无法自动合成 Equatable，手写比较
extension AnswerAction {
    public static func == (lhs: AnswerAction, rhs: AnswerAction) -> Bool {
        lhs.questionNum == rhs.questionNum
            && lhs.kind == rhs.kind
            && lhs.questionId == rhs.questionId
            && lhs.rootIndex == rhs.rootIndex
            && lhs.inputType == rhs.inputType
            && lhs.selectedIndices == rhs.selectedIndices
            && lhs.matrixIndices == rhs.matrixIndices
            && lhs.scalarValue == rhs.scalarValue
            && lhs.textValues == rhs.textValues
            && lhs.sliderValue == rhs.sliderValue
            && lhs.optionFillTexts.map { "\($0.0)|\($0.1)" } == rhs.optionFillTexts.map { "\($0.0)|\($0.1)" }
            && lhs.selectedTexts == rhs.selectedTexts
            && lhs.recordType == rhs.recordType
    }
}
