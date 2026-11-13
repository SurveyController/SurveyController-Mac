// 对标 surveycore/wjx/provider/multilevel.py
// 问卷星多级下拉题：解析 hfLevelData 层级数据、拉取选项、把作答索引转换为提交文本。

import Foundation
import SwiftSoup

public struct WjxMultilevelError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }

    init(_ message: String) { self.message = message }
}

public enum WjxMultilevel {

    public static let providerType = "multilevel_dropdown"

    /// 问卷星多级下拉路径分隔符（U+2010，非普通连字符）。
    private static let splitChar = "‐"
    /// 选项文本末尾的树形展示符号，提交值需要保留、展示文本需要去掉。
    private static let displaySuffixes = Set(
        "┌┍┎┏┐┑┒┓└┕┖┗┘┙┚┛├┝┞┟┠┡┢┣┤┥┦┧┨┩┪┫┬┭┮┯┰┱┲┳┴┵┶┷┸┹┺┻┼┽┾┿╀╁╂╃╄╅╆╇"
    )
    private static let markerRegex = try! NSRegularExpression(pattern: #"╰[0-9]+╯"#)
    private static let externalDataRegex = try! NSRegularExpression(
        pattern: #"levelDataExternalUrl\s*=\s*['\"][^'\"]+"#
    )
    private static let activityIdRegex = try! NSRegularExpression(
        pattern: #"\bvar\s+activityId\s*=\s*(?:DecodeId\((\d+)\)|(\d+))"#
    )
    private static let decodeIdRegex = try! NSRegularExpression(
        pattern: #"function\s+DecodeId\([^)]*\)\s*\{\s*return\s+\w+\s*\^\s*(\d+)"#
    )

    public struct Options {
        public let optionTexts: [String]
        public let submitValues: [String]
        public let levelLabels: [String]
    }

    // MARK: - 层级数据解析（对标 parse_multilevel_options）

    public static func parseOptions(fromHtml html: String, encoded: Bool = false) throws -> Options {
        let doc = try SwiftSoup.parse(html)
        guard let dataInput = try doc.select("input#hfLevelData").first() else {
            throw WjxMultilevelError("问卷星多级下拉未返回 hfLevelData")
        }
        for script in try doc.select("script").array() {
            let text = (try? script.data()) ?? ""
            if firstMatch(externalDataRegex, in: text) != nil {
                throw WjxMultilevelError("问卷星多级下拉暂不支持外部数据源")
            }
        }

        var data = try dataInput.attr("value")
        if encoded {
            data = data.removingPercentEncoding ?? data
        }
        let separatorRange = data.range(of: "〒")
        let levels = separatorRange.map { String(data[..<$0.lowerBound]) } ?? data
        let labels = separatorRange.map { String(data[$0.upperBound...]) } ?? ""
        let columns = levels.components(separatedBy: "|")
        guard !levels.isEmpty, (1...6).contains(columns.count) else {
            throw WjxMultilevelError("问卷星多级下拉层级数据为空或超过六级")
        }

        var paths: [[String]] = []
        var terminalPaths: [[String]] = []
        var previousOptions: Set<String> = []

        for (levelIndex, column) in columns.enumerated() {
            let lines = column
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if levelIndex == 0 {
                guard !lines.isEmpty, !lines.contains(where: { $0.hasPrefix("---") }) else {
                    throw WjxMultilevelError("问卷星多级下拉首级选项无效")
                }
                paths = lines.map { [$0] }
                previousOptions = Set(lines)
                continue
            }

            var groups: [String: [String]] = [:]
            var parent = ""
            for line in lines {
                if line.hasPrefix("---") {
                    parent = String(line.dropFirst(3))
                    guard previousOptions.contains(parent) else {
                        throw WjxMultilevelError("问卷星多级下拉父选项不存在：\(parent)")
                    }
                    groups[parent] = []
                } else if !parent.isEmpty {
                    groups[parent, default: []].append(line)
                } else {
                    throw WjxMultilevelError("问卷星多级下拉子选项缺少父选项")
                }
            }

            var nextPaths: [[String]] = []
            for path in paths {
                guard let children = groups[path.last ?? ""], !children.isEmpty else {
                    throw WjxMultilevelError("问卷星多级下拉缺少子选项：\(path.last ?? "")")
                }
                let hasTerminalChild = children.contains { child in
                    guard let range = child.range(of: "々") else { return false }
                    return range.lowerBound != child.startIndex
                }
                if hasTerminalChild {
                    terminalPaths.append(path)
                } else {
                    nextPaths.append(contentsOf: children.map { path + [$0] })
                }
            }
            paths = nextPaths
            previousOptions = Set(groups.values.flatMap { $0 })
        }

        let finalPaths = terminalPaths + paths
        var submitValues: [String] = []
        var optionTexts: [String] = []
        for path in finalPaths {
            let values = path.map { stripMarkers($0) }
            submitValues.append(values.joined(separator: splitChar))
            optionTexts.append(values.map { stripDisplaySuffix($0) }.joined(separator: splitChar))
        }
        return Options(
            optionTexts: optionTexts,
            submitValues: submitValues,
            levelLabels: labels.isEmpty ? [] : labels.components(separatedBy: "|")
        )
    }

    // MARK: - 拉取选项（对标 load_multilevel_options）

    public static func loadOptions(
        _ questions: [SurveyQuestionMeta],
        html: String,
        url: String,
        client: HTTPClient
    ) async throws -> [SurveyQuestionMeta] {
        guard questions.contains(where: { $0.providerType == providerType }) else {
            return questions
        }

        let doc = try SwiftSoup.parse(html)
        let scripts = try doc.select("script").array()
            .map { (try? $0.data()) ?? "" }
            .joined(separator: "\n")

        guard let activityMatch = firstMatch(activityIdRegex, in: scripts) else {
            throw WjxMultilevelError("问卷星多级下拉缺少 activityId")
        }
        let encodedActivityId = activityMatch.count > 1 ? activityMatch[1] : ""
        let plainActivityId = activityMatch.count > 2 ? activityMatch[2] : ""
        let activityId: Int
        if !encodedActivityId.isEmpty {
            guard let decodeMatch = firstMatch(decodeIdRegex, in: scripts),
                  decodeMatch.count > 1,
                  let xorValue = Int(decodeMatch[1]),
                  let encoded = Int(encodedActivityId) else {
                throw WjxMultilevelError("问卷星多级下拉无法解析 activityId")
            }
            activityId = encoded ^ xorValue
        } else {
            guard let parsed = Int(plainActivityId) else {
                throw WjxMultilevelError("问卷星多级下拉无法解析 activityId")
            }
            activityId = parsed
        }

        let menuUrl = urljoin(url, "/joinnew/setmenuselnew.aspx")
        var headers = defaultHttpHeaders
        headers["Referer"] = url

        var result = questions
        for index in result.indices where result[index].providerType == providerType {
            var question = result[index]
            var raw = (question.providerPageRaw as? [String: Any]) ?? [:]
            let cid = JSONCoercion.asTrimmedString(raw["cid"])

            var params = [
                "activityid": String(activityId),
                "ct": "5",
                "pos": String(question.num),
            ]
            if !cid.isEmpty { params["cid"] = cid }

            var components = URLComponents(string: menuUrl)
            components?.queryItems = params
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let requestUrl = components?.url?.absoluteString else {
                throw WjxMultilevelError("问卷星多级下拉选项地址无效")
            }

            let response = try await client.get(requestUrl, headers: headers)
            try response.raiseForStatus()
            let options = try parseOptions(fromHtml: response.text, encoded: !cid.isEmpty)

            question.optionTexts = options.optionTexts
            question.options = options.optionTexts.count
            raw["submit_values"] = options.submitValues
            raw["level_labels"] = options.levelLabels
            question.providerPageRaw = raw
            result[index] = question
        }
        return result
    }

    // MARK: - 作答映射（对标 multilevel_answer_action）

    /// 多级下拉按文本路径提交，而不是选项序号。
    public static func applyAnswer(_ action: AnswerAction, question: SurveyQuestionMeta) throws -> AnswerAction {
        guard question.providerType == providerType else { return action }
        guard let raw = question.providerPageRaw as? [String: Any],
              let submitValues = raw["submit_values"] as? [String],
              let selectedIndex = action.selectedIndices.first else {
            throw WjxMultilevelError("问卷星第\(question.num)题多级下拉缺少提交数据")
        }
        guard 0 <= selectedIndex, selectedIndex < submitValues.count else {
            throw WjxMultilevelError("问卷星第\(question.num)题多级下拉选项越界")
        }
        var updated = action
        updated.kind = "text"
        updated.textValues = [submitValues[selectedIndex]]
        return updated
    }

    // MARK: - 私有工具

    private static func stripMarkers(_ value: String) -> String {
        guard !value.isEmpty else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return markerRegex.stringByReplacingMatches(in: value, range: range, withTemplate: "")
    }

    private static func stripDisplaySuffix(_ value: String) -> String {
        guard value.count > 1, let last = value.last, displaySuffixes.contains(last) else {
            return value
        }
        return String(value.dropLast())
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> [String]? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let valueRange = Range(match.range(at: index), in: text) else { return "" }
            return String(text[valueRange])
        }
    }

    private static func urljoin(_ base: String, _ path: String) -> String {
        guard let baseURL = URL(string: base),
              let joined = URL(string: path, relativeTo: baseURL) else {
            return path
        }
        return joined.absoluteURL.absoluteString
    }
}
