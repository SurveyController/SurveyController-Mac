// 对标 wjx/provider/http_runtime.py（纯编解码函数）+ wjx/provider/regexes.py（sceneId 模式）
// 提交协议的最敏感部分，全部 golden-value 测试覆盖。

import Foundation

public enum WjxSubmitResult: String {
    case success
    case verification
    case rejected
}

public let wjxSubmissionVerificationMessage = "问卷星触发智能验证，当前链路已停止。请启用随机 IP 后再提交。"
public let wjxProxySubmissionVerificationMessage = "问卷星触发智能验证，当前随机 IP 已被风控，正在更换随机 IP 重试。"

/// 对标 WjxChannelProfile：按 UA 类型区分提交渠道参数。
public struct WjxChannelProfile: Sendable, Equatable {
    public let category: String
    public let source: String
    public let extraParams: [String: String]

    public init(category: String, source: String, extraParams: [String: String]) {
        self.category = category
        self.source = source
        self.extraParams = extraParams
    }
}

public enum WjxSubmitCodec {
    static let defaultSceneId = "q0hcfsca"
    /// 对标 _WJX_SPECIAL_CHAR_REPLACEMENTS（顺序即替换顺序）。
    static let specialCharReplacements: [(String, String)] = [
        ("$", "ξ"),
        ("}", "｝"),
        ("^", "ˆ"),
        ("|", "¦"),
        ("!", "！"),
        ("<", "＜"),
    ]

    static let submissionVerificationMarkers = ["需要安全校验，请重新提交", "请输入验证码"]

    // MARK: - URL

    /// 对标 _shortid_from_url。
    public static func shortidFromUrl(_ url: String) throws -> String {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        var path = ""
        if let schemeRange = text.range(of: "://") {
            let rest = String(text[schemeRange.upperBound...])
            let pathStart = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" })
            if let pathStart {
                let rawPath = String(rest[pathStart...])
                let end = rawPath.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? rawPath.endIndex
                path = String(rawPath[..<end])
            }
        } else {
            path = text
        }
        let last = path.split(separator: "/").last.map(String.init) ?? ""
        let shortid = last.replacingOccurrences(of: ".aspx", with: "").trimmingCharacters(in: .whitespaces)
        if shortid.isEmpty {
            throw NSError(domain: "WjxSubmitCodec", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "问卷星链接缺少 shortid"])
        }
        return shortid
    }

    /// 对标 _submit_domain。
    public static func submitDomain(_ url: String) -> String {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        var host = ""
        if let schemeRange = text.range(of: "://") {
            let rest = String(text[schemeRange.upperBound...])
            let authorityEnd = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? rest.endIndex
            host = String(rest[..<authorityEnd]).lowercased()
        }
        return host.contains("ks.wjx.com") ? "ks.wjx.com" : "v.wjx.cn"
    }

    // MARK: - 时间参数

    /// 对标 _format_wjx_starttime：非补零 "y/M/d H:m:s"。
    public static func formatStartTime(_ timestampSeconds: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(timestampSeconds))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return "\(components.year ?? 0)/\(components.month ?? 0)/\(components.day ?? 0) "
            + "\(components.hour ?? 0):\(components.minute ?? 0):\(components.second ?? 0)"
    }

    /// 对标 _resolve_wjx_submit_start_seconds。
    public static func resolveSubmitStartSeconds(currentMs: Int, ktimes: Int) -> Int {
        let currentSeconds = max(1, currentMs / 1000)
        let durationSeconds = max(1, ktimes)
        return max(1, currentSeconds - durationSeconds)
    }

    // MARK: - sceneId

    static let sceneIdPatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"\bsceneId\s*[:=]\s*["']([^"']+)["']"#, options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: #"\bscene_id\s*[:=]\s*["']([^"']+)["']"#, options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: #"\bdata-scene-id\s*=\s*["']([^"']+)["']"#, options: [.caseInsensitive]),
    ]

    /// 对标 _extract_wjx_scene_id。
    public static func extractSceneId(_ pageHtml: String) -> String {
        let text = unescapeHtmlEntities(pageHtml)
        if text.isEmpty { return defaultSceneId }
        for pattern in sceneIdPatterns {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = pattern.firstMatch(in: text, options: [], range: range),
               match.numberOfRanges >= 2,
               let valueRange = Range(match.range(at: 1), in: text) {
                let value = String(text[valueRange]).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return defaultSceneId
    }

    // MARK: - 签名与转义

    /// 对标 _build_jqsign：jqnonce 逐字符 XOR；t = ktimes % 10（整除 10 取 1）。
    public static func buildJqsign(_ jqnonce: String, ktimes: Int) -> String {
        let remainder = ktimes % 10
        let tValue = remainder == 0 ? 1 : remainder
        var result = ""
        result.reserveCapacity(jqnonce.count)
        for scalar in jqnonce.unicodeScalars {
            let xored = scalar.value ^ UInt32(tValue)
            result.unicodeScalars.append(UnicodeScalar(xored) ?? scalar)
        }
        return result
    }

    /// 对标 _escape_wjx_submit_text。
    public static func escapeSubmitText(_ value: Any?) -> String {
        var text = JSONCoercion.asString(value).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        for (source, target) in specialCharReplacements {
            text = text.replacingOccurrences(of: source, with: target)
        }
        return text
    }

    // MARK: - 渠道

    public static func isWechatUserAgent(_ userAgent: String?) -> Bool {
        (userAgent ?? "").lowercased().contains("micromessenger")
    }

    public static func resolveUserAgent(_ userAgent: String?) -> String {
        let text = (userAgent ?? "").trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { return text }
        return defaultUserAgent
    }

    /// 对标 _resolve_wjx_channel_profile。
    public static func resolveChannelProfile(
        userAgent: String?,
        userAgentProfile: UserAgentProfile? = nil,
        rng: RandomSource = SystemRandomSource()
    ) -> WjxChannelProfile {
        var category = (userAgentProfile?.category ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if category.isEmpty {
            category = isWechatUserAgent(userAgent) ? "wechat" : "pc"
        }
        if category == "wechat" {
            let openid = rng.nextInt(lower: 100_000_000, upper: 999_999_999)
            let unionId = rng.nextInt(lower: 100_000_000, upper: 999_999_999)
            return WjxChannelProfile(
                category: "wechat",
                source: "微信",
                extraParams: [
                    "wxfs": "100",
                    "access_token": "1",
                    "openid": String(openid),
                    "unionId": String(unionId),
                    "wxappid": "wx8fe84c5d52db247a",
                    "iwx": "1",
                ]
            )
        }
        if category == "mobile" {
            return WjxChannelProfile(category: "mobile", source: "手机访问", extraParams: [:])
        }
        return WjxChannelProfile(category: "pc", source: "直链访问", extraParams: [:])
    }

    // MARK: - submitdata

    /// 对标 _format_selected_indices。
    static func formatSelectedIndices(
        _ indices: [Int],
        optionFillTexts: [(Int, String)] = []
    ) -> String {
        var fills: [Int: String] = [:]
        for (index, value) in optionFillTexts {
            let escaped = escapeSubmitText(value)
            if !escaped.isEmpty { fills[index] = escaped }
        }
        var parts: [String] = []
        for index in indices {
            var value = String(index + 1)
            if let fill = fills[index], !fill.isEmpty {
                value = "\(value)^\(fill)"
            }
            parts.append(value)
        }
        return parts.joined(separator: "|")
    }

    /// 对标 _submitdata_answer。
    public static func submitdataAnswer(_ action: AnswerAction) -> String {
        switch action.kind {
        case "choice", "select":
            return formatSelectedIndices(action.selectedIndices, optionFillTexts: action.optionFillTexts)
        case "text":
            let separator = action.textValues.count > 1 ? "^" : ""
            return action.textValues.map { escapeSubmitText($0) }.joined(separator: separator)
        case "matrix":
            return action.matrixIndices.enumerated().map { "\($0.offset + 1)!\($0.element + 1)" }
                .joined(separator: ",")
        case "slider":
            guard let sliderValue = action.sliderValue else { return "" }
            return pythonFloatString(sliderValue)
        case "order":
            return action.selectedIndices.map { String($0 + 1) }.joined(separator: ",")
        default:
            return ""
        }
    }

    /// 对标 _skipped_submitdata_answer。
    public static func skippedSubmitdataAnswer(_ question: SurveyQuestionMeta) -> String {
        let typeCode = question.typeCode.trimmingCharacters(in: .whitespaces)
        let optionCount = max(1, question.options)
        let rows = max(1, question.rows)
        switch typeCode {
        case "3", "4", "5", "7":
            return "-3"
        case "11":
            return (0..<optionCount).map { _ in "-3" }.joined(separator: ",")
        case "6":
            return (0..<rows).map { "\($0 + 1)!-3" }.joined(separator: ",")
        case "1", "2", "8", "9", "33", "34":
            return "(跳过)"
        default:
            return "-3"
        }
    }

    /// 对标 _submitdata_from_actions。
    public static func submitdataFromActions(
        _ actions: [AnswerAction],
        questions: [SurveyQuestionMeta]? = nil,
        skippedQuestionNums: [Int] = []
    ) throws -> String {
        var actionByNum: [Int: AnswerAction] = [:]
        for action in actions where action.questionNum > 0 {
            actionByNum[action.questionNum] = action
        }
        var skippedNums: Set<Int> = []
        for item in skippedQuestionNums where item > 0 {
            skippedNums.insert(item)
        }
        var questionByNum: [Int: SurveyQuestionMeta] = [:]
        for question in questions ?? [] where question.num > 0 {
            questionByNum[question.num] = question
        }

        let orderedNums = Set(actionByNum.keys).union(skippedNums).sorted()
        var parts: [String] = []
        for questionNum in orderedNums {
            let answer: String
            if let action = actionByNum[questionNum] {
                answer = submitdataAnswer(action)
            } else if let question = questionByNum[questionNum] {
                answer = skippedSubmitdataAnswer(question)
            } else {
                answer = "-3"
            }
            if questionNum <= 0 || answer.isEmpty { continue }
            parts.append("\(questionNum)$\(answer.replacingOccurrences(of: "，", with: ","))")
        }
        if parts.isEmpty {
            throw NSError(domain: "WjxSubmitCodec", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "问卷星没有生成可提交答案"])
        }
        return parts.joined(separator: "}")
    }

    // MARK: - 响应分类

    /// 对标 is_wjx_submission_verification_response。
    public static func isSubmissionVerificationResponse(_ responseText: String) -> Bool {
        let text = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return false }
        return submissionVerificationMarkers.contains { text.contains($0) }
    }

    /// 对标 classify_wjx_submit_response。
    public static func classifyResponse(_ responseText: String) -> WjxSubmitResult {
        let text = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSubmissionVerificationResponse(text) { return .verification }
        let lowered = text.lowercased()
        let success = lowered.contains("complete.aspx")
            || lowered.contains("success")
            || lowered.hasPrefix("10")
            || lowered == "1"
            || lowered == "ok"
        let failure = ["抱歉", "不符合", "错误", "重新提交"].contains { text.contains($0) }
        if success && !failure { return .success }
        return .rejected
    }

    /// 对标 _raise_submit_rejected 的错误信息构造。
    public static func submitRejectedError(
        _ responseText: String,
        questionLabel: (Int) -> String = { "第\($0)题" },
        proxyAddress: String? = nil
    ) -> Error {
        let text = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSubmissionVerificationResponse(text) {
            let message = (proxyAddress ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                ? wjxSubmissionVerificationMessage
                : wjxProxySubmissionVerificationMessage
            return SubmissionVerificationRequiredError(message)
        }
        let parts = splitMax(text, separator: "〒", maxSplits: 2)
        guard parts.count == 3 else {
            return NSError(domain: "WjxSubmitCodec", code: 3,
                           userInfo: [NSLocalizedDescriptionKey: "问卷星提交被拒绝：\(String(text.prefix(200)))"])
        }
        let questionNum = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
        let reason = parts[2].isEmpty ? text : parts[2]
        if questionNum > 0 {
            return NSError(domain: "WjxSubmitCodec", code: 4,
                           userInfo: [NSLocalizedDescriptionKey: "问卷星提交被拒绝：\(questionLabel(questionNum))，\(reason)"])
        }
        return NSError(domain: "WjxSubmitCodec", code: 5,
                       userInfo: [NSLocalizedDescriptionKey: "问卷星提交被拒绝：\(reason)"])
    }

    // MARK: - 提交参数

    /// 对标 brush_wjx_http 里的 params 构造（除 jqsign/jqnonce/channel 外）。
    public static func buildSubmitParams(
        shortid: String,
        startSeconds: Int,
        ktimes: Int,
        currentMs: Int,
        channelProfile: WjxChannelProfile,
        jqnonce: String,
        rng: RandomSource = SystemRandomSource()
    ) -> [String: String] {
        var params: [String: String] = [
            "shortid": shortid,
            "starttime": formatStartTime(startSeconds),
            "cst": String(startSeconds * 1000),
            "source": channelProfile.source,
            "submittype": "1",
            "ktimes": String(ktimes),
            "rn": pythonFloatString(2_000_000_000 + rng.nextDouble() * 100_000_000),
            "jcn": shortid,
            "nw": "1",
            "jwt": "4",
            "jpm": "62",
            "capt": "2",
            "t": String(currentMs),
            "jqnonce": jqnonce,
            "jqsign": buildJqsign(jqnonce, ktimes: ktimes),
        ]
        for (key, value) in channelProfile.extraParams {
            params[key] = value
        }
        return params
    }

    /// 对标 _sample_ktimes（默认 90 秒，失败回落）。
    public static func sampleKtimes(
        answerDurationRangeSeconds: (Int, Int),
        rng: RandomSource = SystemRandomSource()
    ) -> Int {
        let defaultSeconds = 90
        let sampled = AnswerDurationSampler.sampleSeconds(
            answerDurationRangeSeconds,
            surveyProvider: "wjx",
            defaultUnconfiguredSeconds: defaultSeconds,
            rng: rng
        )
        if sampled > 0 {
            return max(1, Int(sampled.rounded()))
        }
        return defaultSeconds
    }

    // MARK: - 辅助

    /// Python str.split(sep, maxsplit)：最多 maxSplits 次分割，余下并入最后一段。
    static func splitMax(_ text: String, separator: Character, maxSplits: Int) -> [String] {
        var parts: [String] = []
        var remaining = Substring(text)
        while parts.count < maxSplits, let index = remaining.firstIndex(of: separator) {
            parts.append(String(remaining[..<index]))
            remaining = remaining[remaining.index(after: index)...]
        }
        parts.append(String(remaining))
        return parts
    }

    /// Python str(float)：整数值保留 ".0"（Swift Double 插值行为一致）。
    static func pythonFloatString(_ value: Double) -> String {
        "\(value)"
    }

    /// Python html.unescape 的常用子集。
    static func unescapeHtmlEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        let named = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&apos;": "'", "&nbsp;": " ", "&#39;": "'", "&#x27;": "'",
            "&#x2F;": "/", "&#47;": "/",
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // 数字实体 &#123; / &#x1F;
        if let regex = try? NSRegularExpression(pattern: #"&#(x?)([0-9A-Fa-f]+);"#) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            let matches = regex.matches(in: result, options: [], range: range).reversed()
            for match in matches {
                guard match.numberOfRanges >= 3,
                      let hexRange = Range(match.range(at: 2), in: result),
                      let radixRange = Range(match.range(at: 1), in: result) else { continue }
                let radix: Int = result[radixRange].isEmpty ? 10 : 16
                if let code = UInt32(result[hexRange], radix: radix), let scalar = UnicodeScalar(code) {
                    if let full = Range(match.range(at: 0), in: result) {
                        result.replaceSubrange(full, with: String(Character(scalar)))
                    }
                }
            }
        }
        return result
    }
}
