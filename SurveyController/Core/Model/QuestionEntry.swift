// 对标 software/core/questions/schema.py
// 题目作答配置条目：用户在配置向导里编辑的对象，序列化进配置文件的 question_entries。

import Foundation

public let textRandomNameToken = "__RANDOM_NAME__"
public let textRandomMobileToken = "__RANDOM_MOBILE__"
public let textRandomIdCardToken = "__RANDOM_ID_CARD__"
public let textRandomNone = "none"
public let textRandomName = "name"
public let textRandomMobile = "mobile"
public let textRandomIdCard = "id_card"
public let textRandomInteger = "integer"

/// 全局信度维度标记（未显式分组时的默认维度）。
public let globalReliabilityDimension = "__global_reliability__"

public let textRandomModes: Set<String> = [textRandomNone, textRandomName, textRandomMobile, textRandomIdCard, textRandomInteger]

/// 对标 QuestionEntry dataclass。
/// probabilities/custom_weights 形状不固定（标量/浮点数组/嵌套数组），用 [Any] 承载。
public struct QuestionEntry: @unchecked Sendable {
    public var questionType: String
    public var probabilities: Any?
    public var texts: [String]?
    public var rows: Int
    public var optionCount: Int
    public var distributionMode: String
    public var customWeights: Any?
    public var questionNum: Int?
    public var questionTitle: String?
    public var surveyProvider: SurveyProvider
    public var providerQuestionId: String?
    public var providerPageId: String?
    public var aiEnabled: Bool
    public var multiTextBlankModes: [String]
    public var multiTextBlankAiFlags: [Bool]
    public var multiTextBlankIntRanges: [[Int]]
    public var textRandomMode: String
    public var textRandomIntRange: [Int]
    public var optionFillTexts: [Any?]?
    public var fillableOptionIndices: [Int]?
    public var attachedOptionSelects: [[String: Any]]
    public var isLocation: Bool
    public var locationParts: [String]
    public var dimension: String?
    public var psychoBias: String

    public init(
        questionType: String = "text",
        probabilities: Any? = nil,
        texts: [String]? = nil,
        rows: Int = 1,
        optionCount: Int = 0,
        distributionMode: String = "random",
        customWeights: Any? = nil,
        questionNum: Int? = nil,
        questionTitle: String? = nil,
        surveyProvider: SurveyProvider = .wjx,
        providerQuestionId: String? = nil,
        providerPageId: String? = nil,
        aiEnabled: Bool = false,
        multiTextBlankModes: [String] = [],
        multiTextBlankAiFlags: [Bool] = [],
        multiTextBlankIntRanges: [[Int]] = [],
        textRandomMode: String = textRandomNone,
        textRandomIntRange: [Int] = [],
        optionFillTexts: [Any?]? = nil,
        fillableOptionIndices: [Int]? = nil,
        attachedOptionSelects: [[String: Any]] = [],
        isLocation: Bool = false,
        locationParts: [String] = [],
        dimension: String? = nil,
        psychoBias: String = "custom"
    ) {
        self.questionType = questionType
        self.probabilities = probabilities
        self.texts = texts
        self.rows = rows
        self.optionCount = optionCount
        self.distributionMode = distributionMode
        self.customWeights = customWeights
        self.questionNum = questionNum
        self.questionTitle = questionTitle
        self.surveyProvider = surveyProvider
        self.providerQuestionId = providerQuestionId
        self.providerPageId = providerPageId
        self.aiEnabled = aiEnabled
        self.multiTextBlankModes = multiTextBlankModes
        self.multiTextBlankAiFlags = multiTextBlankAiFlags
        self.multiTextBlankIntRanges = multiTextBlankIntRanges
        self.textRandomMode = textRandomMode
        self.textRandomIntRange = textRandomIntRange
        self.optionFillTexts = optionFillTexts
        self.fillableOptionIndices = fillableOptionIndices
        self.attachedOptionSelects = attachedOptionSelects
        self.isLocation = isLocation
        self.locationParts = locationParts
        self.dimension = dimension
        self.psychoBias = psychoBias
    }
}

/// 对标 _infer_option_count。
public func inferOptionCount(_ entry: QuestionEntry) -> Int {
    func nestedLength(_ raw: Any?) -> Int? {
        guard let list = raw as? [Any] else { return nil }
        var lengths: [Int] = []
        for item in list {
            if item is [Any] { lengths.append((item as! [Any]).count) }
        }
        return lengths.max()
    }

    if entry.questionType == "matrix" {
        if let nested = nestedLength(entry.customWeights) { return nested }
        if let nested = nestedLength(entry.probabilities) { return nested }
    }
    if entry.optionCount > 0 { return entry.optionCount }
    if let weights = entry.customWeights as? [Any], !weights.isEmpty { return weights.count }
    if let probabilities = entry.probabilities as? [Any], !probabilities.isEmpty { return probabilities.count }
    if let texts = entry.texts, !texts.isEmpty { return texts.count }
    if entry.questionType == "scale" || entry.questionType == "score" { return 5 }
    return 0
}

/// 对标 software/core/questions/utils.py 的 try_parse_random_int_range / serialize_random_int_range。
public func tryParseRandomIntRange(_ raw: Any?) -> (min: Int, max: Int)? {
    func coerceInt(_ value: Any?) -> Int? {
        let text = JSONCoercion.asTrimmedString(value)
        guard !text.isEmpty else { return nil }
        return Int(text)
    }

    var minValue: Int? = nil
    var maxValue: Int? = nil
    if let dict = raw as? [String: Any] {
        minValue = coerceInt(dict["min"])
        maxValue = coerceInt(dict["max"])
    } else if let list = raw as? [Any], list.count >= 2 {
        minValue = coerceInt(list[0])
        maxValue = coerceInt(list[1])
    } else {
        return nil
    }

    guard var min = minValue, var max = maxValue else { return nil }
    if min > max { swap(&min, &max) }
    return (min, max)
}

public func serializeRandomIntRange(_ raw: Any?) -> [Int] {
    guard let parsed = tryParseRandomIntRange(raw) else { return [] }
    return [parsed.min, parsed.max]
}
