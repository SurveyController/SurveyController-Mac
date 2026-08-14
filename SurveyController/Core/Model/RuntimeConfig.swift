// 对标 software/core/config/schema.py
// 运行时配置：序列化进配置文件（schema v6）的完整任务配置。

import Foundation

public let reverseFillFormatAuto = "auto"
public let reverseFillFormatWjxSequence = "wjx_sequence"
public let reverseFillFormatWjxScore = "wjx_score"
public let reverseFillFormatWjxText = "wjx_text"
public let reverseFillFormats: Set<String> = [
    reverseFillFormatAuto, reverseFillFormatWjxSequence, reverseFillFormatWjxScore, reverseFillFormatWjxText,
]

public let defaultAnswerDurationRangeSeconds = (60, 120)
public let maxAnswerDurationSeconds = 30 * 60

/// 对标 RuntimeConfig dataclass。
public struct RuntimeConfig: @unchecked Sendable {
    public var url: String = ""
    public var surveyTitle: String = ""
    public var surveyProvider: SurveyProvider = .wjx
    public var target: Int = 1
    public var threads: Int = 1
    public var submitInterval: (Int, Int) = (0, 0)
    public var answerDuration: (Int, Int) = (60, 120)
    public var answerDatetimeWindow: (String, String) = ("", "")
    public var randomIpEnabled: Bool = false
    public var proxySource: String = "default"
    public var customProxyApi: String = ""
    public var proxyAreaCode: String?
    public var randomUaEnabled: Bool = false
    public var randomUaRatios: [String: Int] = ["wechat": 33, "mobile": 33, "pc": 34]
    public var failStopEnabled: Bool = true
    public var pauseOnAliyunCaptcha: Bool = true
    public var reliabilityModeEnabled: Bool = true
    public var psychoTargetAlpha: Double = 0.85
    public var aiMode: String = "free"
    public var aiProvider: String = "deepseek"
    public var aiApiKey: String = ""
    public var aiBaseUrl: String = ""
    public var aiApiProtocol: String = "auto"
    public var aiModel: String = ""
    public var aiSystemPrompt: String = ""
    public var reverseFillEnabled: Bool = false
    public var reverseFillSourcePath: String = ""
    public var reverseFillFormat: String = reverseFillFormatAuto
    public var reverseFillStartRow: Int = 1
    public var reverseFillThreads: Int = 1
    public var answerRules: [[String: Any]] = []
    public var dimensionGroups: [String] = []
    public var questionEntries: [QuestionEntry] = []
    public var questionsInfo: [SurveyQuestionMeta] = []
    /// 配置文件里是否显式出现 AI 字段（对标 _ai_config_present，不入序列化）。
    public var aiConfigPresent: Bool = false

    public init() {}
}

/// 对标 normalize_target_alpha（psychometric.py）：夹紧到 [0.60, 0.95]。
public func normalizeTargetAlpha(_ value: Any?, default defaultValue: Double = 0.85) -> Double {
    let minAlpha = 0.60
    let maxAlpha = 0.95
    var alpha = JSONCoercion.asDouble(value, default: defaultValue)
    if alpha.isNaN { alpha = defaultValue }
    return max(minAlpha, min(maxAlpha, alpha))
}
