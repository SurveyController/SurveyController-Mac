import Foundation
import CoreFoundation

enum TencentLogic {
    private static let questionID = try! NSRegularExpression(pattern: #"\bq-[A-Za-z0-9_-]+\b"#, options: .caseInsensitive)
    private static let pageID = try! NSRegularExpression(pattern: #"\bp-[A-Za-z0-9_-]+\b"#, options: .caseInsensitive)
    private static let endings = ["submit", "finish", "complete", "end", "结束", "提交", "完成"]

    private struct Rules {
        var jumps: [ProviderJSON] = []
        var conditions: [ProviderJSON] = []
        var targets: [ProviderJSON] = []
        var hasJump = false
        var hasCondition = false
        var hasTargets = false
        var incomplete = false
    }

    static func attach(_ metadata: [SurveyQuestionMeta], raw: [ProviderJSON]) -> [SurveyQuestionMeta] {
        let questions = Dictionary(metadata.map { ($0.providerQuestionId, $0.num) }, uniquingKeysWith: { first, _ in first })
        let pages = Dictionary(metadata.map { ($0.providerPageId, $0.num) }, uniquingKeysWith: { first, _ in first })
        let final = (metadata.last?.num ?? 0) + 1
        var rules: [Int: Rules] = [:]
        var referencesByNumber: [Int: [String]] = [:]

        func addJump(number: Int, index: Int, value: Any?, optionText: String = "") {
            guard !isEmpty(value) else { return }
            rules[number, default: Rules()].hasJump = true
            let target = jumpTarget(value, questions: questions, pages: pages, final: final)
            if let target {
                rules[number, default: Rules()].jumps.append([
                    "option_index": index, "target_question": target, "option_text": optionText,
                    "terminates_survey": target == final,
                ])
            } else {
                rules[number, default: Rules()].incomplete = true
            }
        }

        for question in raw {
            guard let number = questions[question.text("id")] else { continue }
            addJump(number: number, index: -1, value: question["goto"])
            for (index, option) in question.objects("options").enumerated() {
                addJump(number: number, index: index, value: option["goto"], optionText: option.text("text"))
                guard !isEmpty(option["display"]) else { continue }
                rules[number, default: Rules()].hasTargets = true
                let references = ids(option["display"], matching: questionID)
                let targets = references.compactMap { questions[$0] }
                if references.isEmpty || targets.count != references.count {
                    rules[number, default: Rules()].incomplete = true
                }
                for target in targets {
                    rules[number, default: Rules()].targets.append([
                        "target_question_num": target, "condition_mode": "selected", "condition_option_indices": [index],
                    ])
                    rules[target, default: Rules()].hasCondition = true
                    rules[target, default: Rules()].conditions.append([
                        "condition_question_num": number, "condition_mode": "selected", "condition_option_indices": [index],
                    ])
                }
            }
            let refer = ids(question["refer"], matching: questionID)
            if !refer.isEmpty {
                referencesByNumber[number] = refer
                rules[number, default: Rules()].hasCondition = true
            }
            if !isEmpty(question["hidden"]) {
                rules[number, default: Rules()].hasCondition = true
            }
        }

        for (number, references) in referencesByNumber where rules[number]?.conditions.isEmpty != false {
            rules[number, default: Rules()].incomplete = true
            for reference in references {
                if let source = questions[reference] {
                    rules[source, default: Rules()].hasTargets = true
                    rules[source, default: Rules()].incomplete = true
                }
            }
        }

        return metadata.map { meta in
            guard let parsed = rules[meta.num] else { return meta }
            var result = meta
            result.hasJump = parsed.hasJump
            result.jumpRules = parsed.jumps
            result.hasDisplayCondition = parsed.hasCondition
            result.displayConditions = parsed.conditions
            result.hasDependentDisplayLogic = parsed.hasTargets
            result.controlsDisplayTargets = parsed.targets
            let incomplete = parsed.incomplete || (parsed.hasCondition && parsed.conditions.isEmpty)
            result.logicParseStatus = incomplete ? "unknown" : "complete"
            if incomplete {
                result.unsupported = true
                result.unsupportedReason = "腾讯问卷逻辑规则未完整解析"
            }
            return result
        }
    }

    private static func isEmpty(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return true }
        if let values = value as? [Any] { return values.isEmpty }
        if let values = value as? ProviderJSON { return values.isEmpty }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return !number.boolValue }
        return JSONCoercion.asTrimmedString(value).isEmpty
    }

    private static func ids(_ value: Any?, matching regex: NSRegularExpression, depth: Int = 0) -> [String] {
        guard let value, depth < 6 else { return [] }
        if let object = value as? ProviderJSON {
            return object.keys.sorted().flatMap { ids($0, matching: regex, depth: depth + 1) + ids(object[$0], matching: regex, depth: depth + 1) }
        }
        if let list = value as? [Any] {
            return list.flatMap { ids($0, matching: regex, depth: depth + 1) }
        }
        let text = JSONCoercion.asTrimmedString(value)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static func jumpTarget(_ value: Any?, questions: [String: Int], pages: [String: Int], final: Int) -> Int? {
        if isEmpty(value) { return nil }
        let text = JSONCoercion.asTrimmedString(value)
        if let number = Int(text), number > 0 { return number }
        if let number = ids(value, matching: questionID).compactMap({ questions[$0] }).first { return number }
        if let number = ids(value, matching: pageID).compactMap({ pages[$0] }).first { return number }
        let description = String(describing: value).lowercased()
        return endings.contains { description.contains($0) } ? final : nil
    }
}
