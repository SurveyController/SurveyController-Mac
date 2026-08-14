// 对标 software/providers/common.py
// 平台常量、URL 识别与归一化。业务逻辑与 Python 源码 1:1。

import Foundation

/// 支持的问卷平台。
public enum SurveyProvider: String, CaseIterable, Sendable, Hashable {
    case wjx
    case qq
    case credamo
}

/// 所有平台 URL 识别规则的唯一入口（不要在业务代码里散落 URL(string:) 判断，
/// Foundation 与 Python urlparse 对非规范输入的行为不同）。
public enum ProviderType {
    static let wjxAllowedHosts: Set<String> = ["wjx.top", "wjx.cn", "wjx.com"]
    static let wjxSurveyHosts: Set<String> = ["v.wjx.cn", "www.wjx.cn", "www.wjx.top"]
    static let qqAllowedHost = "wj.qq.com"
    static let credamoAllowedHosts: Set<String> = ["credamo.com", "credamo.cn"]

    static let qqSurveyPathRegex = try! NSRegularExpression(
        pattern: #"^/s\d+/\d+/[A-Za-z0-9_-]+/?$"#,
        options: [.caseInsensitive]
    )
    static let credamoSurveyPathRegex = try! NSRegularExpression(
        pattern: #"^/answer\.html"#,
        options: [.caseInsensitive]
    )
    static let credamoShortSurveyPathRegex = try! NSRegularExpression(
        pattern: #"^/s/[A-Za-z0-9_-]+/?$"#,
        options: [.caseInsensitive]
    )

    /// 对标 normalize_survey_provider：归一化 provider 值，未知值回落 default（再回落 wjx）。
    public static func normalizeProvider(_ value: String?, default defaultValue: SurveyProvider = .wjx) -> SurveyProvider {
        let provider = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return SurveyProvider(rawValue: provider) ?? defaultValue
    }

    /// 对标 _parse_url_host：返回 (host, path)，无法解析时 ("", "")。
    static func parseUrlHost(_ urlValue: String) -> (host: String, path: String) {
        let text = urlValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return ("", "") }
        let candidate = text.contains("://") ? text : "https://" + text

        guard let schemeRange = candidate.range(of: "://") else { return ("", "") }
        var rest = String(candidate[schemeRange.upperBound...])

        // netloc 到第一个 / ? # 为止；path 到 ? 或 # 为止（对标 urlparse 语义）。
        let authorityEnd = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? rest.endIndex
        let authority = String(rest[..<authorityEnd])
        let host = authority.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first
            .map(String.init)?.lowercased() ?? ""

        rest = String(rest[authorityEnd...])
        let pathEnd = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? rest.endIndex
        let path = String(rest[..<pathEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (host, path)
    }

    /// 对标 is_wjx_domain。
    public static func isWjxDomain(_ urlValue: String) -> Bool {
        let (host, _) = parseUrlHost(urlValue)
        if host.isEmpty { return false }
        return belongs(host: host, to: wjxAllowedHosts)
    }

    /// 对标 is_wjx_survey_url。
    public static func isWjxSurveyUrl(_ urlValue: String) -> Bool {
        let (host, _) = parseUrlHost(urlValue)
        if host.isEmpty { return false }
        return wjxSurveyHosts.contains(host) || host.hasSuffix(".v.wjx.cn")
    }

    /// 对标 is_qq_survey_url。
    public static func isQqSurveyUrl(_ urlValue: String) -> Bool {
        let (host, path) = parseUrlHost(urlValue)
        guard host == qqAllowedHost else { return false }
        return matches(qqSurveyPathRegex, path: path)
    }

    /// 对标 is_credamo_survey_url。
    public static func isCredamoSurveyUrl(_ urlValue: String) -> Bool {
        let (host, path) = parseUrlHost(urlValue)
        if host.isEmpty { return false }
        if !belongs(host: host, to: credamoAllowedHosts) { return false }
        return matches(credamoSurveyPathRegex, path: path) || matches(credamoShortSurveyPathRegex, path: path)
    }

    /// 对标 detect_survey_provider：credamo → qq → wjx 域 → default。
    /// 注意 Python 语义：default 传入空串时最终仍回落 "wjx"。
    public static func detectProvider(_ urlValue: String, default defaultValue: String = "wjx") -> SurveyProvider {
        if isCredamoSurveyUrl(urlValue) { return .credamo }
        if isQqSurveyUrl(urlValue) { return .qq }
        if isWjxDomain(urlValue) { return .wjx }
        return normalizeProvider(defaultValue)
    }

    /// 对标 supports_answer_datetime_window（作答时间窗口仅见数支持）。
    public static func supportsAnswerDatetimeWindow(_ provider: String?) -> Bool {
        normalizeProvider(provider) == .credamo
    }

    /// 对标 is_supported_survey_url。
    public static func isSupportedSurveyUrl(_ urlValue: String) -> Bool {
        isCredamoSurveyUrl(urlValue) || isQqSurveyUrl(urlValue) || isWjxDomain(urlValue)
    }

    /// 对标 normalize_survey_parse_url：补全 scheme、小写 host，
    /// 并把见数短链 /s/xxx 重写为 /answer.html#/s/xxx。
    public static func normalizeSurveyParseUrl(_ urlValue: String) -> String {
        let text = urlValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        let candidate = text.contains("://") ? text : "https://" + text

        guard let schemeRange = candidate.range(of: "://") else { return text }
        let rawScheme = String(candidate[..<schemeRange.lowerBound])
        var rest = String(candidate[schemeRange.upperBound...])

        let authorityEnd = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? rest.endIndex
        let netloc = String(rest[..<authorityEnd]).lowercased()
        rest = String(rest[authorityEnd...])

        let pathEnd = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? rest.endIndex
        let path = String(rest[..<pathEnd])
        var query = ""
        var fragment = ""
        if let queryStart = rest.firstIndex(of: "?") {
            let queryEnd = rest[queryStart...].firstIndex(of: "#") ?? rest.endIndex
            query = String(rest[rest.index(after: queryStart)..<queryEnd])
            if let hashIndex = rest[queryStart...].firstIndex(of: "#") {
                fragment = String(rest[rest.index(after: hashIndex)...])
            }
        } else if let hashIndex = rest.firstIndex(of: "#") {
            fragment = String(rest[rest.index(after: hashIndex)...])
        }

        let scheme = rawScheme.isEmpty ? "https" : rawScheme.lowercased()
        var normalized = "\(scheme)://\(netloc)\(path)"
        if !query.isEmpty { normalized += "?\(query)" }
        if !fragment.isEmpty { normalized += "#\(fragment)" }

        if detectProvider(normalized, default: "") != .credamo {
            return normalized
        }
        if path.lowercased().hasPrefix("/s/") && fragment.isEmpty {
            return "\(scheme)://\(netloc)/answer.html\(query.isEmpty ? "" : "?\(query)")#\(path)"
        }
        return normalized
    }

    /// 对标 make_provider_question_key："provider:pageId:questionId"，缺一返回空串。
    public static func makeProviderQuestionKey(
        provider: String?,
        providerPageId: String?,
        providerQuestionId: String?
    ) -> String {
        let normalizedProvider = normalizeProvider(provider)
        let pageId = (providerPageId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let questionId = (providerQuestionId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if pageId.isEmpty || questionId.isEmpty { return "" }
        return "\(normalizedProvider.rawValue):\(pageId):\(questionId)"
    }

    static func belongs(host: String, to domains: Set<String>) -> Bool {
        domains.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    static func matches(_ regex: NSRegularExpression, path: String) -> Bool {
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return regex.firstMatch(in: path, options: [], range: range) != nil
    }
}
