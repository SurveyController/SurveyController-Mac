import Foundation
import Security

struct AISettings: Sendable {
    var baseURL = ""
    var apiKey = ""
    var model = ""
    var protocolName = "auto"
    var systemPrompt = ""

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (try? endpoint()) != nil
    }

    func endpoint() throws -> (url: String, responses: Bool) {
        guard var destination = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(destination.scheme?.lowercased() ?? ""), destination.host != nil,
              destination.user == nil, destination.password == nil,
              destination.fragment == nil else {
            throw AIFillError.configuration("AI 服务地址必须是有效的 HTTP(S) URL")
        }
        while destination.path.hasSuffix("/") { destination.path.removeLast() }
        if destination.path.hasSuffix("/chat/completions") {
            return (destination.string ?? baseURL, false)
        }
        if destination.path.hasSuffix("/responses") {
            return (destination.string ?? baseURL, true)
        }
        if destination.path.hasSuffix("/completions") {
            throw AIFillError.configuration("请使用 /chat/completions 或 /responses")
        }
        let responses = protocolName == "responses"
        destination.path += responses ? "/responses" : "/chat/completions"
        guard let url = destination.string else { throw AIFillError.configuration("AI 服务地址无效") }
        return (url, responses)
    }
}

enum AIFillError: LocalizedError {
    case configuration(String)
    case request(String)
    case invalidAnswer

    var errorDescription: String? {
        switch self {
        case .configuration(let text), .request(let text): text
        case .invalidAnswer: "AI 返回的答案与所需空格数不一致"
        }
    }
}

enum AISettingsStore {
    private static let key = "surveycontroller.ai-settings"
    private static let service = "SurveyController.CustomAI"
    private static var attributes: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "default"]
    }

    static func load() -> AISettings {
        let values = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        var query = attributes
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var secret: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &secret)
        return AISettings(
            baseURL: values["url"] as? String ?? "",
            apiKey: status == errSecSuccess ? (secret as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? "" : "",
            model: values["model"] as? String ?? "",
            protocolName: values["protocol"] as? String ?? "auto",
            systemPrompt: values["prompt"] as? String ?? ""
        )
    }

    static func save(_ settings: AISettings) throws {
        let query = attributes as CFDictionary
        var status: OSStatus
        if settings.apiKey.isEmpty {
            status = SecItemDelete(query)
            if status == errSecItemNotFound { status = errSecSuccess }
        } else {
            let secret = Data(settings.apiKey.utf8)
            status = SecItemUpdate(query, [kSecValueData as String: secret] as CFDictionary)
            if status == errSecItemNotFound {
                var item = attributes
                item[kSecValueData as String] = secret
                status = SecItemAdd(item as CFDictionary, nil)
            }
        }
        guard status == errSecSuccess else {
            throw AIFillError.configuration("无法将 AI 密钥保存到钥匙串")
        }
        UserDefaults.standard.set([
            "url": settings.baseURL, "model": settings.model,
            "protocol": settings.protocolName, "prompt": settings.systemPrompt,
        ], forKey: key)
    }
}

enum AIAnswerResolver {
    static func resolve(
        _ actions: [AnswerAction],
        metadata: [Int: SurveyQuestionMeta],
        settings: AISettings?,
        client: HTTPClient = .shared
    ) async throws -> [AnswerAction] {
        var result = actions
        for index in result.indices {
            let action = result[index]
            let title = metadata[action.questionNum]?.title ?? "第 \(action.questionNum) 题"
            let blanks = action.textValues.indices.filter { action.textValues[$0] == optionFillAiToken }
            if !blanks.isEmpty {
                guard let settings else { throw AIFillError.configuration("请先配置自定义 AI") }
                let answers = try await generate(title, count: blanks.count, settings: settings, client: client)
                for (blank, answer) in zip(blanks, answers) { result[index].textValues[blank] = answer }
            }
            for option in action.optionFillTexts.indices where action.optionFillTexts[option].1 == optionFillAiToken {
                guard let settings else { throw AIFillError.configuration("请先配置自定义 AI") }
                let selected = action.optionFillTexts[option].0
                let labels = metadata[action.questionNum]?.optionTexts ?? []
                let label = labels.indices.contains(selected) ? labels[selected] : "选项 \(selected + 1)"
                let answers = try await generate("\(title) · \(label) 的补充文本", count: 1, settings: settings, client: client)
                result[index].optionFillTexts[option].1 = answers[0]
                if let position = action.selectedIndices.firstIndex(of: selected), result[index].selectedTexts.indices.contains(position) {
                    result[index].selectedTexts[position] = result[index].selectedTexts[position].replacingOccurrences(
                        of: optionFillAiToken, with: answers[0]
                    )
                }
            }
        }
        return result
    }

    static func generate(_ title: String, count: Int, settings: AISettings, client: HTTPClient) async throws -> [String] {
        let endpoint = try settings.endpoint()
        guard settings.isConfigured else { throw AIFillError.configuration("AI 服务缺少模型或 API 密钥") }
        let instruction = count == 1
            ? "请直接给出答案文本。"
            : "请按空格次序返回恰好 \(count) 项的 JSON 字符串数组。"
        let system = settings.systemPrompt.isEmpty ? "为问卷填空生成简洁答案。" : settings.systemPrompt
        let body: ProviderJSON = endpoint.responses
            ? ["model": settings.model, "instructions": system, "input": "\(title)\n\(instruction)"]
            : ["model": settings.model, "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": "\(title)\n\(instruction)"],
            ]]
        for attempt in 0..<3 {
            let response: HTTPResponse
            do {
                response = try await client.postJSON(
                    endpoint.url, json: body, headers: ["Authorization": "Bearer \(settings.apiKey)"], followRedirects: false
                )
            } catch TransportError.network(let detail) {
                if attempt == 2 { throw AIFillError.request(detail) }
                try await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
                continue
            }
            if response.statusCode == 429 || (500...599).contains(response.statusCode) {
                if attempt == 2 { throw AIFillError.request("AI 服务暂时不可用（HTTP \(response.statusCode)）") }
                try await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
                continue
            }
            guard response.isSuccess else {
                throw AIFillError.configuration("AI 服务拒绝请求（HTTP \(response.statusCode)）")
            }
            let payload = try ProviderJSONResponse.parse(response)
            let content: String
            if endpoint.responses {
                let text = payload.text("output_text")
                content = text.isEmpty ? payload.objects("output").flatMap { $0.objects("content") }.map { $0.text("text") }.joined(separator: "\n") : text
            } else {
                content = payload.objects("choices").first?.object("message").text("content") ?? ""
            }
            return try parseAnswers(content, count: count)
        }
        throw AIFillError.invalidAnswer
    }

    static func parseAnswers(_ input: String, count: Int) throws -> [String] {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```"), value.hasSuffix("```"), let newline = value.firstIndex(of: "\n") {
            value = String(value[value.index(after: newline)...].dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let list = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String]
        let raw = list ?? (count == 1 ? [value] : value.components(separatedBy: "||"))
        let answers = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard count > 0, answers.count == count, answers.allSatisfy({ !$0.isEmpty }) else { throw AIFillError.invalidAnswer }
        return answers
    }
}
