import Foundation

enum ProviderRegistry {
    static func parseSurvey(_ input: String, client: HTTPClient = .shared) async throws -> SurveyDefinition {
        let url = ProviderType.normalizeSurveyParseUrl(input)
        guard ProviderType.isSupportedSurveyUrl(url) else {
            throw SurveyProviderUnavailableAtRuntimeError("请输入问卷星、腾讯问卷或见数的公开问卷链接")
        }
        switch ProviderType.detectProvider(url) {
        case .wjx:
            let result = try await WjxProvider.parseSurvey(url: url, client: client)
            return SurveyDefinition(provider: .wjx, title: result.title, questions: result.questions.filter { !$0.isDescription })
        case .qq:
            return try await TencentProvider.parseSurvey(url: url, client: client)
        case .credamo:
            return try await CredamoProvider.parseSurvey(url: url, client: client)
        }
    }

    static func submit(_ config: ExecutionConfig, context: WjxProvider.SubmitContext) async throws -> Bool {
        switch config.surveyProvider {
        case .wjx: return try await WjxProvider.submit(config, context: context)
        case .qq: return try await TencentProvider.submit(config, context: context)
        case .credamo: return try await CredamoProvider.submit(config, context: context)
        }
    }

    static func answers(
        for currentQuestions: [SurveyQuestionMeta],
        context: inout WjxProvider.SubmitContext
    ) throws -> [(SurveyQuestionMeta, AnswerAction)] {
        let existing = context.state.config.questionsOrdered.filter { !$0.isDescription }
        let current = currentQuestions.filter { !$0.isDescription }
        var bindings: [Int: SurveyQuestionMeta] = [:]
        for question in current {
            let previous = existing.first {
                $0.providerQuestionId == question.providerQuestionId && !$0.providerQuestionId.isEmpty
                    && $0.providerPageId == question.providerPageId
            }
            guard let previous, previous.typeCode == question.typeCode, !question.unsupported,
                  previous.optionTexts == question.optionTexts, previous.rowTexts == question.rowTexts else {
                throw SurveyProviderUnavailableAtRuntimeError("第 \(question.num) 题结构已变更或暂不支持，请重新解析问卷")
            }
            bindings[previous.num] = question
        }
        guard bindings.count == existing.count else {
            throw SurveyProviderUnavailableAtRuntimeError("问卷题目数量已变更，请重新解析问卷")
        }
        let plan = try HttpLogicPlanner.buildPlan(existing) { question in
            try WjxAnswerBuilder.buildAnswerAction(
                question, state: &context.state, threadName: context.threadName, rng: context.rng
            )
        }
        guard !plan.actions.isEmpty else { throw SurveyProviderUnavailableAtRuntimeError("问卷没有可提交的答案") }
        return plan.actions.compactMap { action in bindings[action.questionNum].map { ($0, action) } }
    }

    static func acquireProxy(_ context: WjxProvider.SubmitContext) async throws -> String? {
        let proxy: String?
        if let acquire = context.submitProxyLeaseFactory {
            proxy = try await acquire() ?? context.proxyAddress
        } else {
            proxy = context.proxyAddress
        }
        if context.state.config.randomProxyIpEnabled && (proxy ?? "").isEmpty {
            throw SubmitProxyUnavailableError("提交前未获取到随机 IP")
        }
        return proxy
    }
}

typealias ProviderJSON = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func text(_ key: String) -> String { JSONCoercion.asTrimmedString(self[key]) }
    func int(_ key: String, default fallback: Int = 0) -> Int { JSONCoercion.asInt(self[key], default: fallback) }
    func flag(_ key: String) -> Bool { JSONCoercion.asBool(self[key]) }
    func object(_ key: String) -> ProviderJSON { self[key] as? ProviderJSON ?? [:] }
    func objects(_ key: String) -> [ProviderJSON] { self[key] as? [ProviderJSON] ?? [] }

    func firstText(_ keys: String...) -> String {
        keys.lazy.map(text).first { !$0.isEmpty } ?? ""
    }
}

enum ProviderJSONResponse {
    static func parse(_ response: HTTPResponse) throws -> ProviderJSON {
        try response.raiseForStatus()
        guard let object = try JSONSerialization.jsonObject(with: response.body) as? ProviderJSON else {
            throw TransportError.network("问卷服务返回了无效的数据")
        }
        return object
    }

    static func submitted(_ request: () async throws -> HTTPResponse) async throws -> ProviderJSON {
        let response: HTTPResponse
        do {
            response = try await request()
        } catch TransportError.network(let reason) {
            throw SubmissionResultUnknownError(detail: reason)
        }
        if response.statusCode == 407 { throw TransportError.proxyConnection("代理要求身份验证") }
        if (300..<400).contains(response.statusCode) {
            throw SurveyProviderUnavailableAtRuntimeError("问卷提交请求收到重定向，已停止本轮")
        }
        do {
            return try parse(response)
        } catch {
            if response.isSuccess {
                throw SubmissionResultUnknownError(detail: "问卷服务返回了无法识别的提交结果")
            }
            throw error
        }
    }

    static func queryURL(_ base: String, _ values: [String: String]) throws -> String {
        guard var url = URLComponents(string: base) else { throw TransportError.network("问卷链接无效") }
        url.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let result = url.string else { throw TransportError.network("问卷链接无效") }
        return result
    }

    static func normalizedText(_ text: String) -> String {
        text.replacingOccurrences(of: #"!?\[[^\]]*\]\([^)]*\)|<[^>]*>"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
