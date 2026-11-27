import Foundation

enum TencentProvider {
    private static let origin = "https://wj.qq.com"
    private static let locales = ["zhs", "zht", "zh", "en"]
    private static let typeCodes = [
        "radio": "3", "checkbox": "4", "select": "7", "text": "1", "textarea": "1", "number": "1",
        "nps": "5", "star": "5", "matrix_radio": "6", "matrix_star": "6",
    ]

    private struct Endpoint {
        let survey: String
        let hash: String

        init(_ url: String) throws {
            let parts = URLComponents(string: url)?.path.split(separator: "/") ?? []
            guard parts.count == 3, parts[0].range(of: #"^s\d+$"#, options: .regularExpression) != nil,
                  parts[1].allSatisfy(\.isNumber),
                  parts[2].range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
                throw SurveyProviderUnavailableAtRuntimeError("腾讯问卷链接格式无效")
            }
            survey = String(parts[1])
            hash = String(parts[2])
        }

        var page: String { "\(TencentProvider.origin)/s2/\(survey)/\(hash)/" }
        func base(_ part: String) -> String { "\(TencentProvider.origin)/api/v2/respondent/surveys/\(survey)/\(part)" }
    }

    static func parseSurvey(url: String, client: HTTPClient) async throws -> SurveyDefinition {
        let endpoint = try Endpoint(url)
        let headers = headers(endpoint, userAgent: nil)
        _ = try await fetch("session", endpoint: endpoint, headers: headers, client: client)
        var latestError: Error?
        for locale in locales {
            do {
                let meta = try await fetch("meta", endpoint: endpoint, headers: headers, locale: locale, client: client)
                let content = try await fetch("questions", endpoint: endpoint, headers: headers, locale: locale, client: client)
                let questions = standardize(content.objects("questions"))
                if !questions.isEmpty {
                    return SurveyDefinition(
                        provider: .qq,
                        title: ProviderJSONResponse.normalizedText(meta.text("title")),
                        questions: questions
                    )
                }
            } catch {
                latestError = error
            }
        }
        throw latestError ?? SurveyProviderUnavailableAtRuntimeError("腾讯问卷接口未返回题目")
    }

    static func submit(_ config: ExecutionConfig, context source: WjxProvider.SubmitContext, client: HTTPClient = .shared) async throws -> Bool {
        var context = source
        let endpoint = try Endpoint(config.url)
        var headers = headers(endpoint, userAgent: context.userAgent)
        let session = try await fetch("session", endpoint: endpoint, headers: headers, client: client)
        let sessionID = session.text("answer_session_id")
        if !sessionID.isEmpty { headers["X-Answer-Session"] = sessionID }
        let questions = try await fetch("questions", endpoint: endpoint, headers: headers, locale: "zhs", client: client)
        let raw = questions.objects("questions")
        let records = try await ProviderRegistry.answers(for: standardize(raw), context: &context, client: client)
        let byID = Dictionary(raw.map { ($0.text("id"), $0) }, uniquingKeysWith: { first, _ in first })
        var pages: [String: [ProviderJSON]] = [:]
        var pageOrder: [String] = []
        for (question, action) in records {
            guard !question.providerPageId.isEmpty, let source = byID[question.providerQuestionId] else {
                throw SurveyProviderUnavailableAtRuntimeError("腾讯问卷题目缺少标识，请重新解析")
            }
            let pageID = question.providerPageId
            if pages[pageID] == nil { pageOrder.append(pageID) }
            pages[pageID, default: []].append(contentsOf: try encode(source, action: action))
        }
        let duration = AnswerDurationSampler.sampleSeconds(config.answerDurationRangeSeconds, rng: context.rng)
        let body: ProviderJSON = [
            "survey_id": Int64(endpoint.survey) ?? 0, "hash": endpoint.hash,
            "answer_survey": [
                "duration": Int(duration.rounded()), "ua": WjxSubmitCodec.resolveUserAgent(context.userAgent),
                "referrer": "", "uid": UUID().uuidString.lowercased(), "sid": UUID().uuidString.lowercased(),
                "openid": "", "latitude": NSNull(), "longitude": NSNull(), "is_update": false,
                "locale": "zhs", "pages": pageOrder.map { ["id": $0, "questions": pages[$0] ?? []] },
            ] as ProviderJSON,
        ]
        let proxy = try await ProviderRegistry.acquireProxy(context)
        if context.isStopRequested?() == true { return false }
        let payload = try await ProviderJSONResponse.submitted {
            try await client.postJSON(
                endpoint.base("answers"),
                query: ["hash": endpoint.hash, "pv_uid": UUID().uuidString.lowercased(), "_": timestamp()],
                json: body, headers: headers, proxyAddress: proxy, followRedirects: false
            )
        }
        guard ["OK", "0"].contains(payload.text("code").uppercased()) else {
            throw SurveyProviderUnavailableAtRuntimeError(payload.firstText("message", "msg", "code"))
        }
        guard !payload.object("data").text("answer_hash").isEmpty else {
            throw SubmissionResultUnknownError(detail: "腾讯问卷提交结果缺少收录标识")
        }
        if sessionID.isEmpty {
            await config.selectionRuntime?.record(records.map(\.1))
            return true
        }
        let oldAnswer = session.object("answer_session")
        for attempt in 0..<3 {
            do {
                let current = try await fetch("session", endpoint: endpoint, headers: headers, client: client, proxy: proxy)
                let answer = current.object("answer_session")
                let id = answer.int("last_answer_id")
                if answer.int("last_submitted_at") > oldAnswer.int("last_submitted_at")
                    || (id > 0 && id != oldAnswer.int("last_answer_id")) {
                    await config.selectionRuntime?.record(records.map(\.1))
                    return true
                }
            } catch {
                throw SubmissionResultUnknownError(detail: "无法核对腾讯问卷收录状态")
            }
            if attempt < 2 { try await Task.sleep(for: .milliseconds(200)) }
        }
        throw SubmissionResultUnknownError(detail: "腾讯问卷未确认收录答案")
    }

    private static func headers(_ endpoint: Endpoint, userAgent: String?) -> [String: String] {
        [
            "Accept": "application/json, text/plain, */*",
            "Origin": origin,
            "Referer": endpoint.page,
            "User-Agent": WjxSubmitCodec.resolveUserAgent(userAgent),
        ]
    }

    private static func timestamp() -> String { String(Int(Date().timeIntervalSince1970 * 1000)) }

    private static func fetch(
        _ part: String, endpoint: Endpoint, headers: [String: String],
        locale: String? = nil, client: HTTPClient, proxy: String? = nil
    ) async throws -> ProviderJSON {
        var query = ["hash": endpoint.hash, "_": timestamp()]
        if let locale { query["locale"] = locale }
        let response = try await client.get(ProviderJSONResponse.queryURL(endpoint.base(part), query), headers: headers, proxyAddress: proxy)
        let payload = try ProviderJSONResponse.parse(response)
        guard ["OK", "0"].contains(payload.text("code").uppercased()), let data = payload["data"] as? ProviderJSON else {
            let message = payload.firstText("message", "msg", "code")
            throw SurveyProviderUnavailableAtRuntimeError(message.isEmpty ? "腾讯问卷接口未返回有效数据" : message)
        }
        return data
    }

    static func standardize(_ raw: [ProviderJSON]) -> [SurveyQuestionMeta] {
        var pages: [String: Int] = [:]
        var result: [SurveyQuestionMeta] = []
        for question in raw {
            let providerType = question.text("type").lowercased()
            let page = question.text("page_id")
            if pages[page] == nil { pages[page] = pages.count + 1 }
            guard providerType != "description" else { continue }
            let availableOptions = options(question)
            let optionTexts = availableOptions.map {
                ProviderJSONResponse.normalizedText($0.text("text")).replacingOccurrences(of: #"\{fillblank-[^{}]+\}"#, with: "", options: .regularExpression)
            }
            let rows = question.objects("sub_titles").map { ProviderJSONResponse.normalizedText($0.text("text")) }
            let fillable = availableOptions.indices.filter { blankId(availableOptions[$0]) != nil }
            let number = result.count + 1
            let isText = ["text", "textarea", "number"].contains(providerType)
            let rating = ["nps", "star"].contains(providerType)
            let hasLogic = ["logic", "jump", "display_logic", "jump_logic", "skip_logic"].contains {
                !question.object($0).isEmpty || !question.objects($0).isEmpty
            }
            result.append(SurveyQuestionMeta(
                num: number, title: ProviderJSONResponse.normalizedText(question.text("title")),
                displayNum: number, description: ProviderJSONResponse.normalizedText(question.text("description")),
                typeCode: typeCodes[providerType] ?? "0", options: optionTexts.count, rows: max(1, rows.count),
                rowTexts: rows, page: pages[page] ?? 1, optionTexts: optionTexts,
                fillableOptions: Array(fillable), isRating: rating, ratingMax: rating ? optionTexts.count : 0,
                textInputs: isText ? 1 : 0, isTextLike: isText,
                logicParseStatus: hasLogic ? "unknown" : "none",
                multiMinLimit: question["min_length"], multiMaxLimit: question["max_length"],
                provider: .qq, providerQuestionId: question.text("id"), providerPageId: page, providerType: providerType,
                unsupported: typeCodes[providerType] == nil || hasLogic,
                unsupportedReason: hasLogic ? "包含尚未解析的问卷逻辑" : (typeCodes[providerType] == nil ? "暂不支持腾讯题型：\(providerType)" : ""),
                required: question.flag("required")
            ))
        }
        return TencentLogic.attach(result, raw: raw)
    }

    static func encode(_ question: ProviderJSON, action: AnswerAction) throws -> [ProviderJSON] {
        let id = question.text("id")
        let type = question.text("type")
        let choices = options(question)
        guard !id.isEmpty else { throw SurveyProviderUnavailableAtRuntimeError("腾讯问卷题目缺少 ID") }
        if ["text", "textarea", "number"].contains(type) {
            return [["id": id, "type": type, "text": action.textValues.joined(separator: "\n")]]
        }
        if ["nps", "star"].contains(type) {
            let index = action.scalarValue ?? action.selectedIndices.first ?? -1
            guard choices.indices.contains(index) else { throw SurveyProviderUnavailableAtRuntimeError("腾讯问卷评分超出有效范围") }
            let score = choices[index].firstText("text", "id")
            return [["id": "\(id)-\(score)", "type": type, "answer": score]]
        }
        if type.hasPrefix("matrix_") {
            let rows = question.objects("sub_titles")
            guard !rows.isEmpty, rows.count == action.matrixIndices.count else {
                throw SurveyProviderUnavailableAtRuntimeError("腾讯问卷矩阵行数不匹配")
            }
            return try zip(rows, action.matrixIndices).map { row, index in
                guard choices.indices.contains(index), !row.text("id").isEmpty else {
                    throw SurveyProviderUnavailableAtRuntimeError("腾讯问卷矩阵选项不匹配")
                }
                let rowID = row.text("id")
                let key = type == "matrix_radio"
                    ? "\(id)_\(rowID)_\(choices[index].text("id"))"
                    : "\(id)-\(rowID)-\(choices[index].firstText("text", "id"))"
                return ["id": key, "type": type, "answer": "on"]
            }
        }

        let selected = Set(action.selectedIndices)
        guard !selected.isEmpty, selected.allSatisfy(choices.indices.contains),
              type == "checkbox" || selected.count == 1 else {
            throw SurveyProviderUnavailableAtRuntimeError("腾讯问卷选项超出有效范围")
        }
        let encodedOptions: [ProviderJSON] = try choices.enumerated().map { index, option in
            let optionID = option.text("id")
            guard !optionID.isEmpty else { throw SurveyProviderUnavailableAtRuntimeError("腾讯问卷选项缺少 ID") }
            return ["id": optionID, "text": option.text("text"), "checked": selected.contains(index) ? 1 : 0]
        }
        let blanks: [ProviderJSON] = try action.optionFillTexts.map { index, value in
            guard selected.contains(index), let identifier = blankId(choices[index]) else {
                throw SurveyProviderUnavailableAtRuntimeError("腾讯问卷附加填空缺少 ID")
            }
            return ["id": identifier, "text": value]
        }
        return [["id": id, "type": type, "blanks": blanks, "options": encodedOptions]]
    }

    private static func options(_ raw: ProviderJSON) -> [ProviderJSON] {
        let values = raw.objects("options")
        if raw["options"] != nil { return values }
        guard ["nps", "star", "matrix_star"].contains(raw.text("type")) else { return [] }
        let start = raw.text("type") == "nps" ? 0 : 1
        let end = min(100, raw.int("max", default: raw.text("type") == "nps" ? 10 : 5))
        return end >= start ? (start...end).map { ["id": String($0), "text": String($0)] } : []
    }

    private static func blankId(_ option: ProviderJSON) -> String? {
        let candidates = [option.text("text"), option.text("id")] + option.object("blank_setting").values.map(JSONCoercion.asTrimmedString)
        for text in candidates {
            if let range = text.range(of: #"fillblank-[A-Za-z0-9_-]+"#, options: .regularExpression) {
                return String(text[range])
            }
        }
        return nil
    }
}
