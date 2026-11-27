import CryptoKit
import Foundation

enum CredamoProvider {
    private static let resolution = "1920px*1080px"
    private static let cipher = "P96D0A7D0M8C3R2D0M1"
    private static let tokenAlphabet = Array("ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678")

    private struct Endpoint {
        let origin: String
        let shortID: String

        init(url: String) throws {
            guard ProviderType.detectProvider(url) == .credamo,
                  let components = URLComponents(string: url), let host = components.host else {
                throw SurveyProviderUnavailableAtRuntimeError("见数问卷链接格式无效")
            }
            let route = [components.fragment ?? "", components.path].map { $0.split(separator: "/") }
            guard let candidate = route.lazy.compactMap({ parts -> Substring? in
                guard let index = parts.firstIndex(of: "s"), index + 1 < parts.count else { return nil }
                return parts[index + 1]
            }).first, candidate.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil,
                  candidate.hasSuffix("_") || candidate.hasSuffix("ano") else {
                throw SurveyProviderUnavailableAtRuntimeError("见数 HTTP 目前只支持公开免登录问卷")
            }
            origin = "https://\(host)"
            shortID = candidate.hasSuffix("_") ? String(candidate.dropLast()) + "ano" : String(candidate)
        }

        var page: String { "\(origin)/answer.html#/s/\(shortID)" }
    }

    static func parseSurvey(url: String, client: HTTPClient) async throws -> SurveyDefinition {
        let endpoint = try Endpoint(url: url)
        let detail = try await fetchDetail(endpoint, userAgent: nil, client: client)
        let questions = standardize(rawQuestions(detail))
        guard !questions.isEmpty else { throw SurveyProviderUnavailableAtRuntimeError("见数详情未返回题目") }
        let title = detail.firstText("surveyTitle", "title", "name", "projectName")
        let nested = detail.object("survey").firstText("surveyTitle", "title", "name")
        return SurveyDefinition(
            provider: .credamo,
            title: title.isEmpty ? (nested.isEmpty ? "Credamo 见数问卷" : nested) : title,
            questions: questions
        )
    }

    static func submit(_ config: ExecutionConfig, context source: WjxProvider.SubmitContext, client: HTTPClient = .shared) async throws -> Bool {
        var context = source
        let endpoint = try Endpoint(url: config.url)
        let detail = try await fetchDetail(endpoint, userAgent: context.userAgent, client: client)
        let raw = rawQuestions(detail)
        let records = try ProviderRegistry.answers(for: standardize(raw), context: &context)
        let byID = Dictionary(raw.map { ($0.firstText("questionId", "qstId", "id"), $0) }, uniquingKeysWith: { first, _ in first })
        let duration = max(1, Int((1000 * AnswerDurationSampler.sampleSeconds(config.answerDurationRangeSeconds, rng: context.rng)).rounded()))
        let timeCode = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let initURL = try ProviderJSONResponse.queryURL(
            "\(endpoint.origin)/v1/survey/answer/noauth/init/\(endpoint.shortID)",
            ["timeCode": timeCode, "accountCode": "CDM", "resolution": resolution]
        )
        let initResponse = try await client.get(initURL, headers: headers(endpoint, userAgent: context.userAgent))
        let initialized = try unwrap(ProviderJSONResponse.parse(initResponse))
        let token = initialized.text("answerToken")
        guard !token.isEmpty else { throw SurveyProviderUnavailableAtRuntimeError("见数问卷未建立作答会话") }
        let timestamp = initialized.int("timestamp", default: Int(context.now().timeIntervalSince1970 * 1000))
        let start = startTime(window: config.answerDatetimeWindowMs, fallback: timestamp, duration: duration)
        let encoded = try records.map { question, action -> (Int, ProviderJSON) in
            guard let item = byID[question.providerQuestionId] else {
                throw SurveyProviderUnavailableAtRuntimeError("见数问卷题目缺少标识，请重新解析")
            }
            var answer = try encode(item, action: action)
            answer["answerTime"] = max(1, duration / records.count)
            return (item.int("sortNo", default: question.num), answer)
        }
        let body: ProviderJSON = [
            "answerStartTime": start, "answerEndTime": start + duration, "status": 1,
            "answerQstList": encoded.sorted { $0.0 < $1.0 }.map(\.1),
            "shortUrl": endpoint.shortID, "resolution": resolution, "sourceDetail": 1,
        ]
        let proxy = try await ProviderRegistry.acquireProxy(context)
        if context.isStopRequested?() == true { return false }
        let payload = try await ProviderJSONResponse.submitted {
            try await client.postJSON(
                "\(endpoint.origin)/v1/survey/answer/noauth/save",
                query: ["timeCode": timeCode, "answerToken": token], json: body,
                headers: headers(endpoint, userAgent: context.userAgent, token: token),
                proxyAddress: proxy, followRedirects: false
            )
        }
        _ = try unwrap(payload)
        return true
    }

    static func startTime(window: (Int, Int), fallback: Int, duration: Int) -> Int {
        guard window.0 > 0, window.1 > window.0 else { return fallback }
        let latest = max(window.0, window.1 - duration)
        return Int.random(in: window.0...latest)
    }

    private static func fetchDetail(_ endpoint: Endpoint, userAgent: String?, client: HTTPClient) async throws -> ProviderJSON {
        let response = try await client.get(
            "\(endpoint.origin)/v1/survey/noauth/detail/get/\(endpoint.shortID)",
            headers: headers(endpoint, userAgent: userAgent)
        )
        return try unwrap(ProviderJSONResponse.parse(response))
    }

    private static func unwrap(_ payload: ProviderJSON) throws -> ProviderJSON {
        if let success = payload["success"], !JSONCoercion.asBool(success) {
            let message = payload.firstText("message", "msg", "code")
            throw SurveyProviderUnavailableAtRuntimeError(message.isEmpty ? "见数当前不可填写" : message)
        }
        return payload["data"] as? ProviderJSON ?? payload
    }

    private static func headers(_ endpoint: Endpoint, userAgent: String?, token: String = "") -> [String: String] {
        let union = String((0..<10).compactMap { _ in tokenAlphabet.randomElement() })
        let nonce = String((0..<16).compactMap { _ in tokenAlphabet.randomElement() })
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        var headers = [
            "Accept": "application/json, text/plain, */*", "Accept-Language": "zh-CN,zh;q=0.9",
            "Referer": endpoint.page, "User-Agent": WjxSubmitCodec.resolveUserAgent(userAgent),
            "unionId": union, "nonce": nonce, "timestamp": timestamp,
            "signature": signature(token: token, union: union, nonce: nonce, timestamp: timestamp),
        ]
        if !token.isEmpty { headers["Origin"] = endpoint.origin }
        return headers
    }

    static func signature(token: String, union: String, nonce: String, timestamp: String) -> String {
        func sha1(_ string: String) -> String {
            Insecure.SHA1.hash(data: Data(string.utf8)).map { String(format: "%02X", $0) }.joined()
        }
        let prefix = token + nonce + timestamp
        let suffix = union + cipher
        return sha1(prefix + sha1(prefix + suffix) + suffix)
    }

    static func rawQuestions(_ detail: ProviderJSON) -> [ProviderJSON] {
        var questions = detail.objects("questions")
        for block in detail.objects("blocks") {
            let blocks = block.objects("blockElements")
            for entry in blocks.isEmpty ? block.objects("elements") : blocks {
                let candidates = [entry.object("question"), entry.object("qst"), entry.object("surveyQuestion"), entry]
                if let question = candidates.first(where: { $0["questionType"] != nil || $0["qstId"] != nil || $0["questionId"] != nil }) {
                    questions.append(question)
                }
            }
        }
        return questions
    }

    static func standardize(_ raw: [ProviderJSON]) -> [SurveyQuestionMeta] {
        raw.enumerated().map { offset, question in
            let type = question.int("questionType")
            let selector = question.int("selector")
            let qstNo = question.firstText("qstNo", "questionNo", "qstNum")
            let number = Int(qstNo.filter(\.isNumber)) ?? offset + 1
            let nativeID = question.firstText("questionId", "qstId", "id")
            let providerType: String
            let typeCode: String
            switch type {
            case 1: (providerType, typeCode) = ("text", "1")
            case 2 where selector == 2: (providerType, typeCode) = ("multiple", "4")
            case 2 where selector == 3: (providerType, typeCode) = ("dropdown", "7")
            case 2: (providerType, typeCode) = ("single", "3")
            case 4, 25: (providerType, typeCode) = ("matrix", "6")
            case 6: (providerType, typeCode) = ("order", "11")
            case 11: (providerType, typeCode) = ("scale", "5")
            default: (providerType, typeCode) = (String(type), "0")
            }
            let matrix = providerType == "matrix"
            let choices = question.objects("choices")
            let options = matrix ? question.objects("answers") : choices
            let optionTexts = options.map {
                ProviderJSONResponse.normalizedText($0.firstText("display", "answerContent", "choiceContent", "choiceTitle", "answerTitle", "content", "text", "title", "name"))
            }
            let rowTexts = matrix ? choices.map { ProviderJSONResponse.normalizedText($0.firstText("display", "choiceContent", "choiceTitle", "content", "text", "title", "name")) } : []
            let fillable = type == 2 ? choices.indices.filter {
                choices[$0].flag("isFill") || choices[$0].flag("fillBlank") || choices[$0].flag("isFillBlank")
            } : []
            let hasLogic = ["jumpRules", "logicRules", "displayConditions"].contains {
                !question.object($0).isEmpty || !question.objects($0).isEmpty
            }
            let title = question.firstText("qstTitle", "qstName", "questionTitle", "questionName", "title", "name", "content", "display")
            return SurveyQuestionMeta(
                num: number, title: ProviderJSONResponse.normalizedText(title), displayNum: number,
                description: ProviderJSONResponse.normalizedText(question.firstText("tip", "tips", "remark", "description")),
                typeCode: typeCode, options: optionTexts.count, rows: max(1, rowTexts.count), rowTexts: rowTexts,
                page: max(1, question.int("page", default: question.int("pageNo", default: 1))),
                optionTexts: optionTexts, fillableOptions: Array(fillable), textInputs: type == 1 ? 1 : 0,
                isTextLike: type == 1, logicParseStatus: hasLogic ? "unknown" : "none",
                multiMinLimit: question["minChoices"], multiMaxLimit: question["maxChoices"],
                provider: .credamo, providerQuestionId: nativeID,
                providerType: providerType, unsupported: typeCode == "0" || nativeID.isEmpty || hasLogic,
                unsupportedReason: hasLogic ? "包含尚未解析的问卷逻辑" : (typeCode == "0" ? "暂不支持见数题型：\(providerType)" : ""),
                required: question.flag("required") || question.flag("mustAnswer")
            )
        }
    }

    static func encode(_ question: ProviderJSON, action: AnswerAction) throws -> ProviderJSON {
        let qstID = try identifier(question, "qstId", "id")
        let type = question.int("questionType")
        let choices = question.objects("choices")
        var item: ProviderJSON = ["qstId": qstID, "answerTime": 0, "answerContent": ""]
        func choice(_ index: Int) throws -> ProviderJSON {
            guard choices.indices.contains(index) else { throw SurveyProviderUnavailableAtRuntimeError("见数选项超出有效范围") }
            let fill = action.optionFillTexts.first { $0.0 == index }?.1 ?? ""
            return ["choiceId": try identifier(choices[index], "choiceId", "id"), "choiceContent": fill]
        }
        switch type {
        case 1:
            item["answerContent"] = action.textValues.joined(separator: "\n")
        case 4, 25:
            let columns = question.objects("answers")
            guard !choices.isEmpty, choices.count == action.matrixIndices.count else {
                throw SurveyProviderUnavailableAtRuntimeError("见数矩阵行数不匹配")
            }
            item["answerQstChoiceList"] = try zip(choices, action.matrixIndices).map { row, index -> ProviderJSON in
                guard columns.indices.contains(index) else { throw SurveyProviderUnavailableAtRuntimeError("见数矩阵列超出有效范围") }
                return [
                    "choiceId": try identifier(row, "choiceId", "id"),
                    "choiceAnswerList": [["answerId": try identifier(columns[index], "answerId", "id")]],
                ]
            }
        case 6:
            item["answerChoiceContent"] = try action.selectedIndices.enumerated().map { rank, index -> ProviderJSON in
                guard choices.indices.contains(index) else { throw SurveyProviderUnavailableAtRuntimeError("见数排序选项超出有效范围") }
                return ["choiceId": try identifier(choices[index], "choiceId", "id"), "choiceContent": rank + 1]
            }
        case 2 where question.int("selector") == 2:
            guard !action.selectedIndices.isEmpty else { throw SurveyProviderUnavailableAtRuntimeError("见数多选答案为空") }
            item["answerQstChoiceList"] = try action.selectedIndices.map(choice)
        case 2, 11:
            guard let index = action.scalarValue ?? action.selectedIndices.first else {
                throw SurveyProviderUnavailableAtRuntimeError("见数答案为空")
            }
            item["answerQstChoice"] = try choice(index)
        default:
            throw SurveyProviderUnavailableAtRuntimeError("见数题型暂不支持")
        }
        return item
    }

    private static func identifier(_ object: ProviderJSON, _ keys: String...) throws -> Any {
        for key in keys where !object.text(key).isEmpty {
            if let value = object[key] { return value }
        }
        throw SurveyProviderUnavailableAtRuntimeError("见数问卷题目或选项缺少 ID")
    }
}
