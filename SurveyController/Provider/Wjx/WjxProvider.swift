// 对标 wjx/provider/parser.py + wjx/provider/http_runtime.py（brush_wjx_http）
// 问卷星平台适配器：解析 + 提交全流程。

import Foundation

public struct WjxParseResult: @unchecked Sendable {
    public let title: String
    public let questions: [SurveyQuestionMeta]
}

public enum WjxProvider {

    static let pageLoadTimeoutSeconds: TimeInterval = 20
    static let submitTimeoutSeconds: TimeInterval = 30

    // MARK: - 解析（对标 parse_wjx_survey）

    /// 对标 parse_wjx_survey：GET 页面（最多 3 次重试空页面）→ 解析题目与标题。
    public static func parseSurvey(
        url urlString: String,
        client: HTTPClient = .shared
    ) async throws -> WjxParseResult {
        let normalizedUrl = ProviderType.normalizeSurveyParseUrl(urlString)
        let headers = defaultHttpHeaders

        var html = ""
        var lastError: Error? = nil
        for _ in 0..<3 {
            let response = try await client.get(normalizedUrl, headers: headers)
            try response.raiseForStatus()
            if !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                html = response.text
                break
            }
            lastError = NSError(domain: "WjxProvider", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "问卷星页面内容为空"])
        }
        if html.isEmpty {
            throw lastError ?? NSError(domain: "WjxProvider", code: 1,
                                       userInfo: [NSLocalizedDescriptionKey: "问卷星页面内容为空"])
        }

        try WjxHtmlParser.raiseWjxPageStateErrors(html)
        let questions = try WjxHtmlParser.parseSurveyQuestions(fromHtml: html)
        let title = WjxHtmlParser.extractSurveyTitle(fromHtml: html) ?? "问卷星问卷"
        return WjxParseResult(title: title, questions: questions)
    }

    // MARK: - 提交（对标 brush_wjx_http）

    public struct SubmitContext: @unchecked Sendable {
        public var state: ExecutionState
        public var threadName: String
        public var userAgent: String?
        public var userAgentProfile: UserAgentProfile?
        public var proxyAddress: String?
        /// 提交前惰性获取随机 IP（返回代理地址或 nil）
        public var submitProxyLeaseFactory: (() async throws -> String?)?
        public var rng: RandomSource
        public var now: () -> Date

        public init(
            state: ExecutionState,
            threadName: String = "",
            userAgent: String? = nil,
            userAgentProfile: UserAgentProfile? = nil,
            proxyAddress: String? = nil,
            submitProxyLeaseFactory: (() async throws -> String?)? = nil,
            rng: RandomSource = SystemRandomSource(),
            now: @escaping () -> Date = Date.init
        ) {
            self.state = state
            self.threadName = threadName
            self.userAgent = userAgent
            self.userAgentProfile = userAgentProfile
            self.proxyAddress = proxyAddress
            self.submitProxyLeaseFactory = submitProxyLeaseFactory
            self.rng = rng
            self.now = now
        }
    }

    /// 对标 brush_wjx_http：构造答案 → 组装参数 → POST processjq.ashx → 分类响应。
    /// 返回 false 表示停止信号已触发或未生成答案；抛错表示提交失败。
    @discardableResult
    public static func submit(
        _ config: ExecutionConfig,
        context: SubmitContext,
        client: HTTPClient = .shared
    ) async throws -> Bool {
        var context = context
        let shortid = try WjxSubmitCodec.shortidFromUrl(config.url)
        let userAgentValue = WjxSubmitCodec.resolveUserAgent(context.userAgent)
        let headers: [String: String] = [
            "User-Agent": userAgentValue,
            "Referer": config.url,
            "Accept": defaultHttpHeaders["Accept"] ?? "",
            "Accept-Language": defaultHttpHeaders["Accept-Language"] ?? "",
            "Connection": defaultHttpHeaders["Connection"] ?? "",
        ]

        // 页面加载（不走代理，仅用于 sceneId 与状态检查）
        let pageResponse = try await client.get(config.url, headers: headers)
        try pageResponse.raiseForStatus()
        do {
            try WjxHtmlParser.raiseWjxPageStateErrors(pageResponse.text)
        } catch let error as SurveyProviderStatusError {
            throw SurveyProviderUnavailableAtRuntimeError(error.message)
        }
        let pageHtml = pageResponse.text

        // 构造答案计划
        let questions = config.questionsOrdered
        for question in questions where question.unsupported {
            throw NSError(domain: "WjxProvider", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "问卷星第\(question.num)题暂不支持：\(question.unsupportedReason.isEmpty ? question.typeCode : question.unsupportedReason)"])
        }

        let plan = try HttpLogicPlanner.buildPlan(questions) { question in
            try WjxAnswerBuilder.buildAnswerAction(
                question, state: &context.state,
                threadName: context.threadName, rng: context.rng
            )
        }
        let actions = plan.actions
        if actions.isEmpty { return false }

        let submitdata = try WjxSubmitCodec.submitdataFromActions(
            actions, questions: questions, skippedQuestionNums: plan.skippedQuestionNums
        )

        // 时间与签名参数
        let currentMs = Int(context.now().timeIntervalSince1970 * 1000)
        let ktimes = WjxSubmitCodec.sampleKtimes(
            answerDurationRangeSeconds: config.answerDurationRangeSeconds,
            rng: context.rng
        )
        let startSeconds = WjxSubmitCodec.resolveSubmitStartSeconds(currentMs: currentMs, ktimes: ktimes)
        let sceneId = WjxSubmitCodec.extractSceneId(pageHtml)
        let jqnonce = UUID().uuidString.lowercased()
        let domain = WjxSubmitCodec.submitDomain(config.url)
        let channelProfile = WjxSubmitCodec.resolveChannelProfile(
            userAgent: userAgentValue,
            userAgentProfile: context.userAgentProfile,
            rng: context.rng
        )

        let params = WjxSubmitCodec.buildSubmitParams(
            shortid: shortid,
            startSeconds: startSeconds,
            ktimes: ktimes,
            currentMs: currentMs,
            channelProfile: channelProfile,
            jqnonce: jqnonce,
            rng: context.rng
        )

        // 随机 IP：惰性获取提交代理
        var submitProxyAddress = context.proxyAddress?
            .trimmingCharacters(in: .whitespaces) ?? nil
        if submitProxyAddress?.isEmpty == true { submitProxyAddress = nil }
        if let factory = context.submitProxyLeaseFactory {
            submitProxyAddress = try await factory() ?? submitProxyAddress
        }
        if submitProxyAddress?.isEmpty == true { submitProxyAddress = nil }
        if config.randomProxyIpEnabled && submitProxyAddress == nil {
            throw SubmitProxyUnavailableError("提交前未获取到随机 IP")
        }

        let submitUrl = "https://\(domain)/joinnew/processjq.ashx"
        var submitHeaders = headers
        submitHeaders["Accept"] = "text/plain, */*; q=0.01"
        submitHeaders["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
        submitHeaders["Origin"] = "https://\(domain)"
        submitHeaders["X-Requested-With"] = "XMLHttpRequest"

        let response = try await client.postForm(
            submitUrl,
            query: params,
            formData: ["submitdata": submitdata, "sceneId": sceneId],
            headers: submitHeaders,
            proxyAddress: submitProxyAddress
        )
        try response.raiseForStatus()

        let responseText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if WjxSubmitCodec.classifyResponse(responseText) != .success {
            throw WjxSubmitCodec.submitRejectedError(
                responseText,
                questionLabel: { questionNum in
                    guard let question = config.questionsMetadata[questionNum] else {
                        return "第\(questionNum)题"
                    }
                    let displayNum = question.displayNum ?? 0
                    let prefix = displayNum > 0 ? displayNum : questionNum
                    return question.title.isEmpty ? "第\(prefix)题" : "第\(prefix)题（\(question.title)）"
                },
                proxyAddress: submitProxyAddress
            )
        }
        return true
    }
}
