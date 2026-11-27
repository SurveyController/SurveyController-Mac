import Foundation

struct ReverseFillSample: Sendable {
    let row: Int
    let answers: [Int: AnswerAction]
}

struct ReverseFillSpec: Sendable {
    let totalRows: Int
    let samples: [ReverseFillSample]
    let unmatched: [Int]
    let invalidRows: [Int]

    static func build(
        rows: [[Int: String]],
        questions: [SurveyQuestionMeta],
        entries: [QuestionEntry],
        format: String,
        startRow: Int
    ) -> Self {
        let header = rows.first ?? [:]
        let entriesByNumber = Dictionary(entries.compactMap { entry in
            entry.questionNum.map { ($0, entry.questionType) }
        }, uniquingKeysWith: { first, _ in first })
        let plans = questions.compactMap { question -> Plan? in
            guard let type = entriesByNumber[question.num], supports(question, type: type) else { return nil }
            let keys = Set([key(question.title)] + labelVariants(question.title)).subtracting([""])
            let match = header.keys.sorted().filter { index in
                guard let label = header[index] else { return false }
                if let number = questionNumber(label) {
                    return number == question.num || number == question.displayNum
                }
                return !keys.isDisjoint(with: labelVariants(label))
            }
            return Plan(question: question, type: type, columns: match)
        }
        var samples: [ReverseFillSample] = []
        var invalidRows: [Int] = []
        let matched = plans.filter { !$0.columns.isEmpty }
        let data = rows.enumerated().dropFirst(max(1, startRow - 1))
        for (index, row) in data where row.values.contains(where: { !text($0).isEmpty }) {
            var answers: [Int: AnswerAction] = [:]
            var valid = true
            for plan in matched {
                do {
                    if let action = try answer(for: plan, row: row, header: header, format: format) {
                        answers[plan.question.num] = action
                    }
                } catch {
                    valid = false
                    break
                }
            }
            if valid && !answers.isEmpty {
                samples.append(ReverseFillSample(row: index + 1, answers: answers))
            } else {
                invalidRows.append(index + 1)
            }
        }
        return Self(
            totalRows: samples.count + invalidRows.count,
            samples: samples,
            unmatched: plans.filter { $0.columns.isEmpty }.map(\.question.num),
            invalidRows: invalidRows
        )
    }

    private struct Plan {
        let question: SurveyQuestionMeta
        let type: String
        let columns: [Int]
    }

    private enum RowError: Error { case invalidAnswer }

    private static func supports(_ question: SurveyQuestionMeta, type: String) -> Bool {
        guard ["single", "multiple", "dropdown", "scale", "score", "matrix", "text", "multi_text"].contains(type),
              !question.isLocation, !question.unsupported else { return false }
        if ["single", "multiple", "dropdown"].contains(type) {
            return question.fillableOptions.isEmpty && question.attachedOptionSelects.isEmpty
        }
        return true
    }

    private static func answer(
        for plan: Plan,
        row: [Int: String],
        header: [Int: String],
        format: String
    ) throws -> AnswerAction? {
        let question = plan.question
        let values = plan.columns.map { text(row[$0] ?? "") }
        guard values.contains(where: { !$0.isEmpty }) else { return nil }
        let names = question.optionTexts
        let optionCount = names.isEmpty ? question.options : names.count
        func choice(_ raw: String) throws -> Int {
            if format != reverseFillFormatWjxSequence {
                let matches = names.indices.filter { key(names[$0]) == key(raw) }
                if matches.count == 1 { return matches[0] }
                if matches.count > 1 { throw RowError.invalidAnswer }
            }
            if format != reverseFillFormatWjxText,
               let number = Double(raw), number.isFinite, number.rounded() == number,
               number >= 1, number <= Double(optionCount) {
                return Int(number) - 1
            }
            throw RowError.invalidAnswer
        }

        switch plan.type {
        case "text", "multi_text":
            guard values.count == max(1, question.textInputs), values.allSatisfy({ !$0.isEmpty }) else {
                throw RowError.invalidAnswer
            }
            return AnswerAction(questionNum: question.num, kind: "text", textValues: values, recordType: "text")
        case "matrix":
            guard values.count == max(1, question.rows) else { throw RowError.invalidAnswer }
            return AnswerAction(questionNum: question.num, kind: "matrix", matrixIndices: try values.map(choice), recordType: "matrix")
        case "multiple":
            let indexes: [Int]
            let numbered = plan.columns.map { optionNumber(header[$0] ?? "") }
            if values.count == 1, numbered.first?.flatMap({ $0 }) == nil {
                indexes = try Set(values[0].components(separatedBy: "┋").map(choice)).sorted()
            } else {
                guard values.count == optionCount, values.allSatisfy({ ["0", "1", "0.0", "1.0"].contains($0) }) else {
                    throw RowError.invalidAnswer
                }
                let mapped = try plan.columns.enumerated().map { offset, column -> Int in
                    if let number = numbered[offset] { return number - 1 }
                    let label = key(header[column] ?? "")
                    let matches = names.indices.filter { label.hasSuffix("(" + key(names[$0]) + ")") }
                    guard matches.count == 1 else { throw RowError.invalidAnswer }
                    return matches[0]
                }
                guard mapped.allSatisfy({ (0..<optionCount).contains($0) }), Set(mapped).count == optionCount else {
                    throw RowError.invalidAnswer
                }
                indexes = zip(mapped, values).compactMap { Double($0.1) == 1 ? $0.0 : nil }.sorted()
            }
            let minimum = max(1, JSONCoercion.asInt(question.multiMinLimit, default: 1))
            let maximum = JSONCoercion.asInt(question.multiMaxLimit, default: optionCount)
            guard indexes.count >= minimum, indexes.count <= maximum else { throw RowError.invalidAnswer }
            return AnswerAction(
                questionNum: question.num, kind: "choice", inputType: "checkbox",
                selectedIndices: indexes, selectedTexts: indexes.compactMap { names.indices.contains($0) ? names[$0] : nil },
                recordType: "multiple"
            )
        default:
            guard values.count == 1 else { throw RowError.invalidAnswer }
            let index = try choice(values[0])
            return AnswerAction(
                questionNum: question.num, kind: plan.type == "dropdown" ? "select" : "choice",
                inputType: plan.type == "dropdown" ? "" : "radio", selectedIndices: [index],
                selectedTexts: names.indices.contains(index) ? [names[index]] : [],
                recordType: plan.type
            )
        }
    }

    private static func text(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func key(_ value: String) -> String {
        text(value).lowercased()
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .filter { !$0.isWhitespace }
    }

    private static func labelVariants(_ label: String) -> [String] {
        let base = key(label)
        let stripped = base.replacingOccurrences(of: #"^[\(\[（【]?\d+[\)\]）】]?[.．、:：_-]*"#, with: "", options: .regularExpression)
        return [base, stripped]
    }

    private static func questionNumber(_ header: String) -> Int? {
        capturedNumber(header, pattern: #"^\s*[（(【\[]?(\d+)[）)】\].．、:：_-]"#)
    }

    private static func optionNumber(_ header: String) -> Int? {
        capturedNumber(header, pattern: #"[（(]\s*选项\s*(\d+)\s*[）)]\s*$"#)
    }

    private static func capturedNumber(_ value: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return Int(value[range])
    }
}

actor ReverseFillRuntime {
    private let samples: [ReverseFillSample]
    private var next = 0
    private var retry: [ReverseFillSample] = []
    private var attempted: Set<Int> = []

    init(_ spec: ReverseFillSpec) { self.samples = spec.samples }

    func reserve() -> ReverseFillSample? {
        if let sample = retry.popLast() { return sample }
        guard samples.indices.contains(next) else { return nil }
        let value = samples[next]
        next += 1
        return value
    }

    func release(_ sample: ReverseFillSample) { retry.append(sample) }

    func retryOnce(_ sample: ReverseFillSample) {
        if attempted.insert(sample.row).inserted { release(sample) }
    }
}
