// 对标 wjx/provider/html_parser.py + html_parser_common.py + html_parser_choice.py
//        + html_parser_matrix.py + html_parser_rules.py + regexes.py + questions/multiple_limits.py
// 问卷星问卷 HTML → [SurveyQuestionMeta]。
// v0.1 覆盖：3单选/4多选/5量表评分/6矩阵/7下拉/8滑块/9矩阵填空/1、2填空（含多空、gapfill）/
//           11排序；跳题、显示条件、强制选项、多选数量限制、媒体、必答、说明块、地区题。
// 未覆盖（后续版本补齐）：下拉附加选项（attached_option_selects 细化）、文本输入标签的边角场景。

import Foundation
import SwiftSoup

public enum WjxHtmlParser {

    // MARK: - 正则（对标 regexes.py）

    static let titleSuffixRegex = try! NSRegularExpression(
        pattern: #"(?:\s*[-|｜丨_－—]+\s*)?问卷星(.*)?$"#,
        options: [.caseInsensitive]
    )
    static let questionPrefixRegex = try! NSRegularExpression(
        pattern: #"^\*?\s*(?:第\s*(\d+)\s*题|Q\s*(\d+)|(\d+)\s*[.．、])\s*"#,
        options: [.caseInsensitive]
    )
    static let jumpTargetRegex = try! NSRegularExpression(
        pattern: #"^(?:(-?\d+)|跳到第\s*(\d+)\s*题)$"#
    )
    static let relationChunkRegex = try! NSRegularExpression(
        pattern: #"^(\d+)\s*,\s*(\d+(?:\s*,\s*\d+)*)$"#
    )
    static let forceSelectCommandRegex = try! NSRegularExpression(pattern: #"请(?:务必|一定|必须|直接)?\s*选(?:择)?"#)
    static let forceSelectSentenceSplitRegex = try! NSRegularExpression(pattern: #"[。；;！？!\n\r]"#)
    static let forceSelectIndexTargetRegex = try! NSRegularExpression(pattern: #"^第?\s*(\d{1,3})\s*(?:个|项|选项|分|星)?$"#)
    static let forceSelectLabelTargetRegex = try! NSRegularExpression(pattern: #"^([A-Za-z])\s*(?:项|选项|答案)?$"#)
    static let forceSelectOptionLabelRegex = try! NSRegularExpression(
        pattern: #"^(?:第\s*)?[\(（【\[]?\s*([A-Za-z])\s*[\)）】\]]?(?=$|[.、:：\-\s]|[\u{4e00}-\u{9fff}])"#
    )
    static let modlenClassRegex = try! NSRegularExpression(pattern: #"modlen(\d+)"#)
    static let displaySpaceRegex = try! NSRegularExpression(pattern: #"\s+"#)
    static let divIdRegex = try! NSRegularExpression(pattern: #"div(\d+)"#)

    static let textInputAllowedTypes: Set<String> = ["text", "tel", "email", "number", "search", "url", "password"]
    static let knownNonTextQuestionTypes: Set<String> = ["3", "4", "5", "6", "7", "8", "11", "12", "13", "15", "16", "17"]
    static let selectPlaceholderPrefixes = ["请选择", "请先选择"]
    static let locationVerifyMarkers = ["地图", "省市", "省份", "城市", "地区"]
    static let terminateKeywords = ["结束作答", "结束答题", "结束填写", "终止作答", "停止作答"]

    // MARK: - 入口

    /// 对标 parse_survey_questions_from_html。
    public static func parseSurveyQuestions(fromHtml html: String) throws -> [SurveyQuestionMeta] {
        let doc = try SwiftSoup.parse(html)
        guard let container = try doc.select("div#divQuestion").first() else { return [] }
        var fieldsets = try container.select("fieldset").array()
        if fieldsets.isEmpty { fieldsets = [container] }

        var questionsInfo: [[String: Any]] = []
        for (pageIndex, fieldset) in fieldsets.enumerated() {
            let topicDivs = try fieldset.select("div[topic]").array().filter { div in
                !hasQuestionAncestor(div, until: fieldset)
            }
            var currentDisplayNum: Int? = nil
            var visibleQuestionCounter = 0

            for questionDiv in topicDivs {
                let rawHeadingText = extractDisplayHeadingText(questionDiv)
                guard let questionNumber = extractQuestionNumber(fromDiv: questionDiv) else {
                    if let headingNum = extractDisplayQuestionNumber(rawHeadingText) {
                        currentDisplayNum = headingNum
                    }
                    continue
                }

                var typeCode = normalizeAttr(questionDiv.attrText("type")).isEmpty ? "0" : normalizeAttr(questionDiv.attrText("type"))
                if typeCode != "11" && looksLikeReorder(questionDiv) {
                    typeCode = "11"
                }
                let isDescription = looksLikeDescription(questionDiv, typeCode: typeCode)
                let isRequired = questionIsRequired(questionDiv)
                var isRating = false
                var ratingMax = 0
                if typeCode == "5" {
                    isRating = looksLikeRating(questionDiv)
                    if isRating {
                        ratingMax = extractRatingOptionCount(questionDiv)
                    }
                }
                let isLocation = ["1", "2"].contains(typeCode) && questionIsLocation(questionDiv)

                var displayNum = extractDisplayQuestionNumber(rawHeadingText)
                if displayNum == nil {
                    displayNum = currentDisplayNum
                } else if let dn = displayNum, dn > 0 {
                    currentDisplayNum = dn
                }
                if !selfOrAncestorsHidden(questionDiv) {
                    visibleQuestionCounter += 1
                    if displayNum == nil || displayNum != visibleQuestionCounter {
                        displayNum = visibleQuestionCounter
                        currentDisplayNum = displayNum
                    }
                }

                let titleText = extractQuestionTitle(questionDiv, fallbackNumber: questionNumber)
                let metadata = try extractQuestionMetadata(doc, questionDiv, questionNumber: questionNumber, typeCode: typeCode)
                var optionTexts = metadata.optionTexts
                var optionCount = metadata.optionCount

                if isRating {
                    let ratingTexts = extractRatingOptionTexts(questionDiv)
                    if !ratingTexts.isEmpty { optionTexts = ratingTexts }
                    optionCount = max(optionCount, ratingMax, optionTexts.count)
                    if optionCount > 0 {
                        let hasMeaningful = optionTexts.contains { textLooksMeaningful($0) }
                        if optionTexts.isEmpty || !hasMeaningful {
                            optionTexts = (0..<optionCount).map { String($0 + 1) }
                        }
                    }
                } else if typeCode == "5" {
                    let scaleTexts = extractRatingOptionTexts(questionDiv)
                    if !scaleTexts.isEmpty {
                        optionTexts = scaleTexts
                        optionCount = scaleTexts.count
                    }
                }

                var attachedOptionSelects: [[String: Any]] = []
                if ["3", "4"].contains(typeCode) {
                    attachedOptionSelects = extractChoiceAttachedSelects(questionDiv)
                }

                let (hasJump, jumpRules) = try extractJumpRules(questionDiv, optionTexts: optionTexts)
                let (hasDisplayCondition, displayConditions) = try extractDisplayConditions(questionDiv)
                let isSliderMatrix = looksLikeSliderMatrix(questionDiv)
                var sliderMin: Double? = nil
                var sliderMax: Double? = nil
                var sliderStep: Double? = nil
                if typeCode == "8" || isSliderMatrix {
                    (sliderMin, sliderMax, sliderStep) = extractSliderRange(questionDiv, questionNumber: questionNumber)
                }

                let textInputCount = countTextInputs(questionDiv)
                let textInputLabels = textInputCount > 1 ? extractTextInputLabels(questionDiv) : []
                let hasGapfill = normalizeAttr(questionDiv.attrText("gapfill")) == "1"
                let isTextLikeQuestion = shouldTreatAsTextLike(
                    typeCode, optionCount: optionCount, textInputCount: textInputCount,
                    hasSliderMatrix: isSliderMatrix, isLocation: isLocation
                )
                let isMultiText = shouldMarkAsMultiText(
                    typeCode, optionCount: optionCount, textInputCount: textInputCount,
                    isLocation: isLocation, hasGapfill: hasGapfill, hasSliderMatrix: isSliderMatrix
                )

                var forcedOptionIndex: Int? = nil
                var forcedOptionText: String? = nil
                if ["3", "5", "7"].contains(typeCode) {
                    (forcedOptionIndex, forcedOptionText) = extractForceSelectOption(questionDiv, titleText: titleText, optionTexts: optionTexts)
                }

                questionsInfo.append([
                    "num": questionNumber,
                    "display_num": displayNum ?? NSNull(),
                    "title": titleText,
                    "type_code": typeCode,
                    "options": optionCount,
                    "rows": metadata.matrixRows,
                    "row_texts": metadata.rowTexts,
                    "page": pageIndex + 1,
                    "option_texts": optionTexts,
                    "forced_option_index": forcedOptionIndex ?? NSNull(),
                    "forced_option_text": forcedOptionText ?? "",
                    "fillable_options": metadata.fillableIndices,
                    "attached_option_selects": attachedOptionSelects,
                    "has_attached_option_select": !attachedOptionSelects.isEmpty,
                    "is_location": isLocation,
                    "is_rating": isRating,
                    "is_description": isDescription,
                    "rating_max": ratingMax,
                    "text_inputs": textInputCount,
                    "text_input_labels": textInputLabels,
                    "is_multi_text": isMultiText,
                    "is_text_like": isTextLikeQuestion,
                    "is_slider_matrix": isSliderMatrix,
                    "has_jump": hasJump,
                    "jump_rules": jumpRules,
                    "has_display_condition": hasDisplayCondition,
                    "display_conditions": displayConditions,
                    "logic_parse_status": logicParseStatusNone,
                    "question_media": collectQuestionMedia(questionDiv, rowTexts: metadata.rowTexts, optionTexts: optionTexts),
                    "slider_min": sliderMin ?? NSNull(),
                    "slider_max": sliderMax ?? NSNull(),
                    "slider_step": sliderStep ?? NSNull(),
                    "multi_min_limit": metadata.multiMinLimit ?? NSNull(),
                    "multi_max_limit": metadata.multiMaxLimit ?? NSNull(),
                    "required": isRequired,
                ])
            }
        }

        attachDisplayConditionMetadata(&questionsInfo)
        for index in questionsInfo.indices {
            let question = questionsInfo[index]
            let hasLogic = JSONCoercion.asBool(question["has_jump"])
                || JSONCoercion.asBool(question["has_display_condition"])
                || JSONCoercion.asBool(question["has_dependent_display_logic"])
            questionsInfo[index]["logic_parse_status"] = hasLogic ? logicParseStatusComplete : logicParseStatusNone
        }
        return ensureSurveyQuestionMetas(questionsInfo, defaultProvider: .wjx)
    }

    /// 对标 extract_survey_title_from_html。
    public static func extractSurveyTitle(fromHtml html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        var candidates: [String] = []
        let selectors = [
            "#divTitle h1", "#divTitle", ".surveytitle", ".survey-title", ".surveyTitle",
            ".wjdcTitle", ".htitle", ".topic_tit", "#htitle", "#lbTitle",
        ]
        for selector in selectors {
            if let element = try? doc.select(selector).first(), let _ = try? element.text() {
                let text = normalizeHtmlText(try? element.text())
                if !text.isEmpty { candidates.append(text) }
            }
        }
        if candidates.isEmpty {
            for tagName in ["h1", "h2"] {
                if let header = try? doc.select(tagName).first() {
                    let text = normalizeHtmlText(try? header.text())
                    if !text.isEmpty { candidates.append(text) }
                    if !candidates.isEmpty { break }
                }
            }
        }
        if let titleTag = try? doc.select("title").first() {
            let text = normalizeHtmlText(try? titleTag.text())
            if !text.isEmpty { candidates.append(text) }
        }
        for raw in candidates {
            var cleaned = raw
            if let range = titleSuffixRegex.firstMatch(
                in: cleaned,
                range: NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            ), let r = Range(range.range, in: cleaned) {
                cleaned = String(cleaned[..<r.lowerBound])
            }
            cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " -_|"))
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    // MARK: - 页面状态错误（对标 parser.py _raise_wjx_page_state_errors）

    static let pausedSurveyRegex = try! NSRegularExpression(pattern: #"此问卷[（(]\s*(\d+)\s*[）)]已暂停"#)
    static let notOpenTimeRegex = try! NSRegularExpression(
        pattern: #"此问卷将于\s*(\d{4})\s*(?:-|/|年)\s*(\d{1,2})\s*(?:-|/|月)\s*(\d{1,2})\s*(日)?\s*(\d{1,2})\s*(?::|时)\s*(\d{1,2})(?:\s*(?::|分)\s*(\d{1,2})\s*秒?)?\s*开放"#
    )

    /// 对标 _raise_wjx_page_state_errors：识别暂停/停止/企业版/未开放状态页。
    public static func raiseWjxPageStateErrors(_ html: String) throws {
        let text = WjxSubmitCodec.unescapeHtmlEntities(html)
        if let match = firstMatch(pausedSurveyRegex, text) {
            throw SurveyPausedError("问卷已暂停（ID: \(match)），无法填写")
        }
        if text.contains("问卷已停止") || text.contains("问卷已结束") || text.contains("抱歉，该问卷已被停止") {
            throw SurveyStoppedError("问卷已停止收集，无法填写")
        }
        if text.contains("企业版") && (text.contains("升级") || text.contains("到期")) {
            throw SurveyEnterpriseUnavailableError("问卷为企业版且不可用")
        }
        if let match = notOpenTimeRegex.firstMatch(
            in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)
        ) {
            var components: [String] = []
            for i in 1...match.numberOfRanges - 1 {
                if let r = Range(match.range(at: i), in: text) { components.append(String(text[r])) }
            }
            throw SurveyNotOpenError("问卷将于 \(components.prefix(6).joined(separator: " ")) 开放")
        }
    }

    static func firstMatch(_ regex: NSRegularExpression, _ text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    // MARK: - 文本归一化

    static func normalizeHtmlText(_ value: String?) -> String {
        guard var text = value, !text.isEmpty else { return "" }
        text = WjxSubmitCodec.unescapeHtmlEntities(text)
        text = replaceSpaces(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceSpaces(_ text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = ""
        var last = text.startIndex
        if let match = displaySpaceRegex.firstMatch(in: text, options: [], range: range) {
            result = displaySpaceRegex.stringByReplacingMatches(
                in: text, options: [], range: range, withTemplate: " "
            )
            _ = last
        } else {
            result = text
        }
        return result
    }

    /// 对标 normalize_match_text：unescape + NFKC + 折叠空白。
    static func normalizeMatchText(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        var text = WjxSubmitCodec.unescapeHtmlEntities(JSONCoercion.asString(value))
        text = text.precomposedStringWithCompatibilityMapping
        text = displaySpaceRegex.stringByReplacingMatches(
            in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text), withTemplate: " "
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 题目编号与标题

    static func extractQuestionNumber(fromDiv questionDiv: Element) -> Int? {
        let topicAttr = normalizeAttr(questionDiv.attrText("topic"))
        if !topicAttr.isEmpty, let number = Int(topicAttr) { return number }
        let idAttr = questionDictId(questionDiv)
        if let match = divIdRegex.firstMatch(in: idAttr, range: NSRange(idAttr.startIndex..<idAttr.endIndex, in: idAttr)),
           let r = Range(match.range(at: 1), in: idAttr) {
            return Int(idAttr[r])
        }
        return nil
    }

    private static func questionDictId(_ element: Element) -> String {
        normalizeAttr(element.attrText("id"))
    }

    static func normalizeAttr(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 对标 WJX_QUESTION_PREFIX_RE。
    static func extractPrefixedQuestionNumber(_ rawTitle: Any?) -> Int? {
        let text = normalizeMatchText(rawTitle)
        if text.isEmpty { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = questionPrefixRegex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 4 else { return nil }
        for groupIndex in 1...3 {
            if let r = Range(match.range(at: groupIndex), in: text), let number = Int(text[r]), number > 0 {
                return number
            }
        }
        return nil
    }

    static func extractDisplayQuestionNumber(_ rawTitle: String) -> Int? {
        extractPrefixedQuestionNumber(rawTitle)
    }

    static func cleanupQuestionTitle(_ rawTitle: String) -> String {
        var title = normalizeHtmlText(rawTitle)
        if title.isEmpty { return "" }
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        title = questionPrefixRegex.stringByReplacingMatches(in: title, options: [], range: range, withTemplate: "")
        title = title.replacingOccurrences(of: "【单选题】", with: "")
        title = title.replacingOccurrences(of: "【多选题】", with: "")
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 对标 _extract_question_title。
    static func extractQuestionTitle(_ questionDiv: Element, fallbackNumber: Int) -> String {
        if let titleElement = firstDescendant(questionDiv, classValue: "topichtml") {
            let titleText = cleanupQuestionTitle((try? titleElement.text()) ?? "")
            if !titleText.isEmpty { return titleText }
        }
        if let labelElement = firstDescendant(questionDiv, classValue: "field-label") {
            let titleText = cleanupQuestionTitle((try? labelElement.text()) ?? "")
            if !titleText.isEmpty { return titleText }
        }
        return "第\(fallbackNumber)题"
    }

    /// 对标 _extract_display_heading_text。
    static func extractDisplayHeadingText(_ questionDiv: Element) -> String {
        if let fieldLabel = firstDescendant(questionDiv, classValue: "field-label") {
            var parts: [String] = []
            for className in ["topicnumber", "topichtml"] {
                guard let element = firstDescendant(fieldLabel, classValue: className) else { continue }
                let text = normalizeHtmlText(try? element.text())
                if !text.isEmpty { parts.append(text) }
            }
            if !parts.isEmpty { return normalizeHtmlText(parts.joined(separator: " ")) }
        }
        for className in ["topichtml", "field-label", "qtypetip"] {
            guard let titleElement = firstDescendant(questionDiv, classValue: className) else { continue }
            let text = normalizeHtmlText(try? titleElement.text())
            if !text.isEmpty { return text }
        }
        if let blockquote = try? questionDiv.select("blockquote").first() {
            let text = normalizeHtmlText(try? blockquote.text())
            if !text.isEmpty { return text }
        }
        return normalizeHtmlText(try? questionDiv.text())
    }

    // MARK: - 隐藏与嵌套

    static func questionDivIsInitiallyHidden(_ questionDiv: Element) -> Bool {
        let styleText = normalizeAttr(questionDiv.attrText("style")).lowercased()
        let hiddenAttr = normalizeAttr(questionDiv.attrText("hidden")).lowercased()
        let classText = (questionDiv.classValue()).lowercased()
        return styleText.contains("display:none")
            || styleText.contains("display: none")
            || styleText.contains("visibility:hidden")
            || styleText.contains("visibility: hidden")
            || ["hidden", "true", "1"].contains(hiddenAttr)
            || classText.contains("display-none")
    }

    static func selfOrAncestorsHidden(_ questionDiv: Element) -> Bool {
        var current: Element? = questionDiv
        while let element = current {
            if questionDivIsInitiallyHidden(element) { return true }
            current = element.parent()
        }
        return false
    }

    static func hasQuestionAncestor(_ questionDiv: Element, until fieldset: Element) -> Bool {
        var current = questionDiv.parent()
        while let element = current, element != fieldset {
            if element.tagName() == "div", !normalizeAttr(element.attrText("topic")).isEmpty {
                return true
            }
            current = element.parent()
        }
        return false
    }

    // MARK: - 必答 / 说明 / 地区 / 排序

    static func questionIsRequired(_ questionDiv: Element) -> Bool {
        for (attr, allowed) in [("req", ["1", "true", "True"]), ("required", ["1", "true", "required"]),
                                ("must", ["1", "true", "True"]), ("wjxreq", ["1", "true", "True"])] {
            let value = normalizeAttr(questionDiv.attrText(attr))
            if allowed.contains(value) { return true }
        }
        if normalizeAttr(questionDiv.attrText("aria-required")).lowercased() == "true" { return true }

        let markerSelectors = [".req", ".required", ".must", ".star", ".red", ".wjxreq", "[aria-required='true']"]
        for selector in markerSelectors {
            if let found = try? questionDiv.select(selector).first(), found != nil {
                return true
            }
        }

        let headingText = extractDisplayHeadingText(questionDiv)
        if headingText.hasPrefix("*") { return true }
        if headingText.contains("必答") { return true }
        let text = normalizeHtmlText(try? questionDiv.text())
        if text.hasPrefix("*") { return true }
        return false
    }

    static func looksLikeDescription(_ questionDiv: Element, typeCode: String) -> Bool {
        let relation = normalizeAttr(questionDiv.attrText("relation"))
        let styleText = normalizeAttr(questionDiv.attrText("style")).lowercased()
        let isUnreachablePlaceholder = relation == "-1"
            && styleText.replacingOccurrences(of: " ", with: "").contains("display:none")
            && !questionIsRequired(questionDiv)
        if isUnreachablePlaceholder { return true }

        guard ["3", "4"].contains(typeCode) else { return false }
        if let choiceInputs = try? questionDiv.select("input[type=radio], input[type=checkbox]").array(), !choiceInputs.isEmpty {
            return false
        }
        if hasDescendant(questionDiv, selector: ".ui-controlgroup") { return false }
        if hasDescendant(questionDiv, selector: ".jqradio, .jqcheck") { return false }
        return true
    }

    static func looksLikeReorder(_ questionDiv: Element) -> Bool {
        if hasDescendant(questionDiv, selector: ".sortnum, .sortnum-sel, .order-number, .order-index") {
            return true
        }
        guard let listItems = try? questionDiv.select("ul li, ol li").array(), !listItems.isEmpty else {
            return false
        }
        return hasDescendant(questionDiv, selector: ".ui-sortable, .ui-sortable-handle, [class*='sort']")
    }

    static func questionIsLocation(_ questionDiv: Element) -> Bool {
        if hasDescendant(questionDiv, selector: ".get_Local") { return true }
        guard let inputs = try? questionDiv.select("input").array() else { return false }
        for inputElement in inputs {
            let verifyValue = normalizeAttr(inputElement.attrText("verify"))
            if locationVerifyMarkers.contains(where: { verifyValue.contains($0) }) { return true }
            let onclickValue = normalizeAttr(inputElement.attrText("onclick")).lowercased()
            if onclickValue.contains("opencitybox") { return true }
        }
        return false
    }

    static func hasDescendant(_ element: Element, selector: String) -> Bool {
        guard let nodes = try? element.select(selector).array() else { return false }
        return !nodes.isEmpty
    }

    static func firstDescendant(_ element: Element, classValue: String) -> Element? {
        try? element.select("." + classValue).first()
    }

    // MARK: - 量表/评分

    static func looksLikeNumericScale(_ questionDiv: Element) -> Bool {
        var anchors: [Element] = []
        if let found = try? questionDiv.select("ul[tp='d'] li a, .scale-rating ul li a, .scale-rating a[val]").array() {
            anchors = found
        }
        var texts: [String] = []
        for anchor in anchors {
            var text = normalizeHtmlText(try? anchor.text())
            if text.isEmpty {
                for key in ["title", "aria-label", "val", "value", "dval", "data-value", "data-val"] {
                    text = normalizeHtmlText(anchor.attrText(key))
                    if !text.isEmpty { break }
                }
            }
            if !text.isEmpty { texts.append(text) }
        }
        if texts.isEmpty { return false }
        let numericRegex = try! NSRegularExpression(pattern: #"^\d{1,2}$"#)
        let numericCount = texts.filter { text in
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return numericRegex.firstMatch(in: text, options: [], range: range) != nil
        }.count
        let hasScaleTitle = hasDescendant(
            questionDiv,
            selector: ".scaleTitle, .scaleTitle_frist, .scaleTitle_last, .scaleTitleFirst, .scaleTitleLast"
        )
        let total = texts.count
        return total >= 5 && numericCount >= max(3, Int(Double(total) * 0.7)) && (total >= 9 || hasScaleTitle)
    }

    static func looksLikeRating(_ questionDiv: Element) -> Bool {
        if looksLikeNumericScale(questionDiv) { return false }
        if hasDescendant(questionDiv, selector: ".evaluateTagWrap") { return true }
        if hasDescendant(questionDiv, selector: "a.rate-off, a.rate-on, .rate-off, .rate-on") { return true }
        if hasDescendant(questionDiv, selector: ".scale-rating .iconfontNew, .iconfontNew") { return true }
        return false
    }

    static func extractRatingOptionCount(_ questionDiv: Element) -> Int {
        if let ratingList = try? questionDiv.select("ul").array().first(where: { ul in
            let classNames = ul.classValue()
            let range = NSRange(classNames.startIndex..<classNames.endIndex, in: classNames)
            return modlenClassRegex.firstMatch(in: classNames, options: [], range: range) != nil
        }) {
            let classNames = ratingList.classValue()
            let range = NSRange(classNames.startIndex..<classNames.endIndex, in: classNames)
            if let match = modlenClassRegex.firstMatch(in: classNames, options: [], range: range),
               let r = Range(match.range(at: 1), in: classNames), let count = Int(classNames[r]) {
                return count
            }
        }
        if let options = try? questionDiv.select(".scale-rating ul li").array(), !options.isEmpty {
            return options.count
        }
        if let options = try? questionDiv.select("a.rate-off, a.rate-on").array(), !options.isEmpty {
            return options.count
        }
        return 0
    }

    static func extractRatingOptionTexts(_ questionDiv: Element) -> [String] {
        let selectors = [".scale-rating ul li a", ".scale-rating a[val]", "ul[tp='d'] li a", "ul[class*='modlen'] li a"]
        var anchors: [Element] = []
        for selector in selectors {
            if let found = try? questionDiv.select(selector).array(), !found.isEmpty {
                anchors = found
                break
            }
        }
        if anchors.isEmpty { return [] }
        var texts: [String] = []
        var seen: Set<String> = []
        for (index, anchor) in anchors.enumerated() {
            var text = extractOptionTextFromAttrs(anchor)
            if !textLooksMeaningful(text) { text = normalizeHtmlText(try? anchor.text()) }
            if !textLooksMeaningful(text) { text = normalizeHtmlText(anchor.attrText("title")) }
            if !textLooksMeaningful(text) { text = normalizeHtmlText(anchor.attrText("val")) }
            if !textLooksMeaningful(text) { text = String(index + 1) }
            if seen.contains(text) { continue }
            seen.insert(text)
            texts.append(text)
        }
        return texts
    }

    static func textLooksMeaningful(_ text: String) -> Bool {
        if text.isEmpty { return false }
        return text.contains { char in
            char.isLetter || char.isNumber
        }
    }

    static func extractOptionTextFromAttrs(_ target: Element?) -> String {
        guard let target else { return "" }
        let primaryKeys = ["title", "data-title", "data-text", "data-label", "aria-label", "alt", "htitle"]
        for key in primaryKeys {
            let text = normalizeHtmlText(target.attrText(key))
            if !text.isEmpty { return text }
        }
        if let children = try? target.select("a, span, label").array() {
            for child in children.prefix(4) {
                for key in primaryKeys {
                    let text = normalizeHtmlText(child.attrText(key))
                    if !text.isEmpty { return text }
                }
            }
        }
        let fallbackKeys = ["val", "value", "data-value", "data-val"]
        for key in fallbackKeys {
            let text = normalizeHtmlText(target.attrText(key))
            if !text.isEmpty { return text }
        }
        if let children = try? target.select("a, span, label").array() {
            for child in children.prefix(4) {
                for key in fallbackKeys {
                    let text = normalizeHtmlText(child.attrText(key))
                    if !text.isEmpty { return text }
                }
            }
        }
        return ""
    }

    // MARK: - 选项文本（choice 3/4/5/11、select 7）

    struct QuestionMetadata {
        var optionTexts: [String] = []
        var optionCount: Int = 0
        var matrixRows: Int = 0
        var rowTexts: [String] = []
        var fillableIndices: [Int] = []
        var multiMinLimit: Int? = nil
        var multiMaxLimit: Int? = nil
    }

    static func collectChoiceOptionTexts(_ questionDiv: Element) -> (texts: [String], fillableIndices: [Int]) {
        var texts: [String] = []
        var fillableIndices: [Int] = []
        var optionElements: [Element] = []
        for selector in [".ui-controlgroup > div", "ul > li"] {
            if let found = try? questionDiv.select(selector).array(), !found.isEmpty {
                optionElements = found
                break
            }
        }
        if !optionElements.isEmpty {
            for element in optionElements {
                let labelElement = (try? element.select(".label").first()) ?? nil
                var text = normalizeHtmlText(try? labelElement?.text())
                if text.isEmpty { text = extractOptionTextFromAttrs(element) }
                if text.isEmpty { continue }
                let optionIndex = texts.count
                texts.append(text)
                if elementContainsTextInput(element) {
                    fillableIndices.append(optionIndex)
                }
            }
        }
        if texts.isEmpty {
            var seen: Set<String> = []
            for selector in [".label", "li span", "li"] {
                guard let elements = try? questionDiv.select(selector).array() else { continue }
                for element in elements {
                    var text = normalizeHtmlText(try? element.text())
                    if text.isEmpty { text = extractOptionTextFromAttrs(element) }
                    if text.isEmpty || seen.contains(text) { continue }
                    texts.append(text)
                    seen.insert(text)
                }
                if !texts.isEmpty { break }
            }
        }
        if fillableIndices.isEmpty && !texts.isEmpty && questionDivHasSharedTextInput(questionDiv) {
            fillableIndices.append(texts.count - 1)
        }
        return (texts, Array(Set(fillableIndices)).sorted())
    }

    static func isTextInputElement(_ element: Element) -> Bool {
        let tagName = element.tagName().lowercased()
        let inputType = normalizeAttr(element.attrText("type")).lowercased()
        if tagName == "textarea" { return true }
        return tagName == "input" && ["", "text", "search", "tel", "number"].contains(inputType)
    }

    static func elementContainsTextInput(_ element: Element) -> Bool {
        if isTextInputElement(element) { return true }
        guard let candidates = try? element.select("input, textarea").array() else { return false }
        return candidates.contains { isTextInputElement($0) }
    }

    static func questionDivHasSharedTextInput(_ questionDiv: Element) -> Bool {
        if let sharedInputs = try? questionDiv.select(".ui-other input, .ui-other textarea").array() {
            if sharedInputs.contains(where: { elementContainsTextInput($0) }) { return true }
        }
        if let keywordInputs = try? questionDiv.select(
            "input[id*='other'], input[name*='other'], textarea[id*='other'], textarea[name*='other']"
        ).array() {
            if keywordInputs.contains(where: { elementContainsTextInput($0) }) { return true }
        }
        return false
    }

    static func isSelectPlaceholderOption(index: Int, value: String, text: String) -> Bool {
        if index != 0 { return false }
        let normalizedValue = normalizeHtmlText(value)
        let normalizedText = normalizeHtmlText(text)
        if normalizedText.isEmpty { return true }
        if ["", "0", "-1", "-2"].contains(normalizedValue) { return true }
        let compactText = normalizedText.replacingOccurrences(of: " ", with: "")
        return selectPlaceholderPrefixes.contains { compactText.hasPrefix($0) }
    }

    static func collectSelectOptionTexts(_ questionDiv: Element, soup: Document, questionNumber: Int) -> [String] {
        var selectElement = try? questionDiv.select("select").first()
        if selectElement == nil {
            selectElement = try? soup.select("select#q\(questionNumber)").first()
        }
        guard let select = selectElement else { return [] }
        var options: [String] = []
        guard let optionElements = try? select.select("option").array() else { return [] }
        for (index, option) in optionElements.enumerated() {
            let value = normalizeHtmlText(option.attrText("value"))
            let text = normalizeHtmlText(try? option.text())
            if isSelectPlaceholderOption(index: index, value: value, text: text) { continue }
            if text.isEmpty { continue }
            options.append(text)
        }
        return options
    }

    static func extractChoiceAttachedSelects(_ questionDiv: Element) -> [[String: Any]] {
        var optionElements: [Element] = []
        for selector in [".ui-controlgroup > div", "ul > li"] {
            if let found = try? questionDiv.select(selector).array(), !found.isEmpty {
                optionElements = found
                break
            }
        }
        var attachedSelects: [[String: Any]] = []
        for (optionIndex, element) in optionElements.enumerated() {
            var optionText = ""
            if let labelElement = try? element.select(".label").first() {
                optionText = normalizeHtmlText(try? labelElement.text())
            }
            if optionText.isEmpty { optionText = extractOptionTextFromAttrs(element) }
            var selectOptions: [String] = []
            if let selectElement = try? element.select("select").first() {
                selectOptions = selectOptionTexts(fromSelect: selectElement)
            }
            if selectOptions.isEmpty {
                if let inputCandidates = try? element.select("input").array() {
                    for inputElement in inputCandidates {
                        selectOptions = extractCustomSelectOptionTexts(inputElement)
                        if !selectOptions.isEmpty { break }
                    }
                }
            }
            if selectOptions.isEmpty { continue }
            attachedSelects.append([
                "option_index": optionIndex,
                "option_text": optionText,
                "select_options": selectOptions,
                "select_option_count": selectOptions.count,
            ])
        }
        return attachedSelects
    }

    static func selectOptionTexts(fromSelect selectElement: Element?) -> [String] {
        guard let selectElement,
              let optionElements = try? selectElement.select("option").array() else { return [] }
        var options: [String] = []
        for (index, option) in optionElements.enumerated() {
            let value = normalizeHtmlText(option.attrText("value"))
            let text = normalizeHtmlText(try? option.text())
            if isSelectPlaceholderOption(index: index, value: value, text: text) { continue }
            if text.isEmpty { continue }
            options.append(text)
        }
        return options
    }

    static func extractCustomSelectOptionTexts(_ element: Element?) -> [String] {
        guard let element else { return [] }
        var rawValues: [String] = []
        for key in ["cusom", "custom", "data-custom", "data-cusom"] {
            let raw = normalizeAttr(element.attrText(key))
            if !raw.isEmpty { rawValues.append(raw) }
        }
        var options: [String] = []
        let splitRegex = try! NSRegularExpression(pattern: #"[,，\n\r|/]+"#)
        for raw in rawValues {
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            let parts = splitRegex.matches(in: raw, options: [], range: range)
                .map { Range($0.range, in: raw).map { String(raw[$0]) } ?? "" }
            if parts.isEmpty {
                let text = normalizeHtmlText(raw)
                if !text.isEmpty { options.append(text) }
            } else {
                for part in parts {
                    let text = normalizeHtmlText(part)
                    if text.isEmpty { continue }
                    let compactText = text.replacingOccurrences(of: " ", with: "")
                    if selectPlaceholderPrefixes.contains(where: { compactText.hasPrefix($0) }) { continue }
                    options.append(text)
                }
            }
        }
        var deduped: [String] = []
        var seen: Set<String> = []
        for option in options where !seen.contains(option) {
            seen.insert(option)
            deduped.append(option)
        }
        return deduped
    }

    // MARK: - 矩阵（type 6）

    static func collectMatrixOptionTexts(
        _ soup: Document, _ questionDiv: Element, questionNumber: Int
    ) -> (rows: Int, optionTexts: [String], rowTexts: [String]) {
        var optionTexts: [String] = []
        var matrixRows = 0
        var rowTexts: [String] = []

        var table: Element? = try? questionDiv.select("#divRefTab\(questionNumber)").first()
        if table == nil { table = try? soup.select("#divRefTab\(questionNumber)").first() }

        if let table, let rows = try? table.select("tr").array() {
            for row in rows {
                let rowIndexAttr = normalizeAttr(row.attrText("rowindex"))
                if let rowIndex = Int(rowIndexAttr), rowIndexAttr == String(rowIndex) {
                    matrixRows += 1
                    if let cells = try? row.select("td, th").array(), !cells.isEmpty {
                        rowTexts.append(extractRowLabel(row, cells: cells))
                    }
                }
            }
        }

        if matrixRows == 0, let table {
            var dataRows: [(label: String, cellCount: Int)] = []
            let headerId = "drv\(questionNumber)_1"
            if let rows = try? table.select("tr").array() {
                for row in rows {
                    if normalizeAttr(row.attrText("id")) == headerId { continue }
                    guard let cells = try? row.select("td, th").array() else { continue }
                    if cells.count <= 1 { continue }
                    let firstText = extractRowLabel(row, cells: cells)
                    let otherTexts = cells.dropFirst().map { normalizeHtmlText(try? $0.text()) }
                    if firstText.isEmpty && !otherTexts.contains(where: { !$0.isEmpty }) { continue }
                    dataRows.append((firstText, cells.count))
                }
            }
            matrixRows = dataRows.count
            rowTexts = dataRows.map { $0.label }
            if optionTexts.isEmpty && !dataRows.isEmpty {
                let maxCols = dataRows.map { max(0, $0.cellCount - 1) }.max() ?? 0
                if maxCols > 0 {
                    optionTexts = (0..<maxCols).map { String($0 + 1) }
                }
            }
        }

        if matrixRows == 0 {
            var rowIndices: [Int] = []
            var colIndices: [Int] = []
            if let inputs = try? questionDiv.select("input").array() {
                let namePattern = try! NSRegularExpression(pattern: #"q\(questionNumber)[_-](\d+)(?:[_-](\d+))?"#)
                for item in inputs {
                    let rawName = normalizeAttr(item.attrText("name")).isEmpty
                        ? normalizeAttr(item.attrText("id"))
                        : normalizeAttr(item.attrText("name"))
                    if rawName.isEmpty { continue }
                    let range = NSRange(rawName.startIndex..<rawName.endIndex, in: rawName)
                    guard let match = namePattern.firstMatch(in: rawName, options: [], range: range) else { continue }
                    if let r = Range(match.range(at: 1), in: rawName), let rowIdx = Int(rawName[r]) {
                        rowIndices.append(rowIdx)
                    }
                    if let r = Range(match.range(at: 2), in: rawName), let colIdx = Int(rawName[r]) {
                        colIndices.append(colIdx)
                    }
                }
            }
            if !rowIndices.isEmpty {
                matrixRows = rowIndices.max() ?? 0
                rowTexts = Array(repeating: "", count: matrixRows)
            }
            if optionTexts.isEmpty && !colIndices.isEmpty {
                let maxCols = colIndices.max() ?? 0
                if maxCols > 0 { optionTexts = (0..<maxCols).map { String($0 + 1) } }
            }
        }

        if let table, optionTexts.isEmpty {
            optionTexts = extractMatrixHeaderTexts(table)
        }
        optionTexts = postprocessMatrixOptionTexts(optionTexts)

        return (matrixRows, optionTexts, rowTexts)
    }

    static func extractRowLabel(_ row: Element, cells: [Element]) -> String {
        var labelText = ""
        if let firstCell = cells.first {
            labelText = normalizeHtmlText(try? firstCell.text())
            if labelText.isEmpty { labelText = extractOptionTextFromAttrs(firstCell) }
        }
        if labelText.isEmpty { labelText = extractOptionTextFromAttrs(row) }
        if labelText.isEmpty {
            for selector in [".label", ".row-title", ".rowtitle", ".row", ".item-title", ".itemTitle", ".itemTitleSpan", ".stitle"] {
                if let node = try? row.select(selector).first() {
                    labelText = normalizeHtmlText(try? node.text())
                    if !labelText.isEmpty { break }
                }
            }
        }
        if labelText.isEmpty {
            if let children = try? row.select("label, span, div, p").array() {
                for child in children.prefix(10) {
                    labelText = extractOptionTextFromAttrs(child)
                    if !labelText.isEmpty { break }
                    labelText = normalizeHtmlText(try? child.text())
                    if !labelText.isEmpty { break }
                }
            }
        }
        return labelText
    }

    static func extractMatrixHeaderTexts(_ table: Element) -> [String] {
        var bestTexts: [String] = []
        var bestScore = 0
        guard let rows = try? table.select("tr").array() else { return [] }
        for row in rows {
            if hasDescendant(row, selector: "input, select, textarea") { continue }
            guard let cells = try? row.select("td, th").array() else { continue }
            if cells.count <= 1 { continue }
            let rawTexts = cells.map { normalizeHtmlText(try? $0.text()) }
            let nonEmpty = rawTexts.filter { !$0.isEmpty }
            let score = nonEmpty.count
            if score < 2 { continue }
            if score > bestScore {
                bestScore = score
                bestTexts = nonEmpty
            }
        }
        return bestTexts
    }

    static func postprocessMatrixOptionTexts(_ optionTexts: [String]) -> [String] {
        var cleaned: [String] = []
        var seen: Set<String> = []
        for rawText in optionTexts {
            let text = normalizeHtmlText(rawText)
            if text.isEmpty || seen.contains(text) { continue }
            seen.insert(text)
            cleaned.append(text)
        }
        return cleaned
    }

    // MARK: - 滑块

    static func extractSliderRange(_ questionDiv: Element, questionNumber: Int) -> (Double?, Double?, Double?) {
        var sliderInput = try? questionDiv.select("input#q\(questionNumber)").first()
        if sliderInput == nil { sliderInput = try? questionDiv.select("input[type=range]").first() }
        if sliderInput == nil { sliderInput = try? questionDiv.select("input.ui-slider-input").first() }
        guard let sliderInput else { return (nil, nil, nil) }
        return (
            Double(normalizeAttr(sliderInput.attrText("min"))),
            Double(normalizeAttr(sliderInput.attrText("max"))),
            Double(normalizeAttr(sliderInput.attrText("step")))
        )
    }

    static func looksLikeSliderMatrix(_ questionDiv: Element) -> Bool {
        guard let sliderInputs = try? questionDiv.select("input.ui-slider-input[rowid]").array(),
              sliderInputs.count >= 2 else { return false }
        guard let sliderTracks = try? questionDiv.select(".rangeslider, .range-slider, .wjx-slider").array() else {
            return false
        }
        return sliderTracks.count >= sliderInputs.count
    }

    // MARK: - 文本输入计数与标签

    static func inputLooksLikeLocation(_ inputElement: Element) -> Bool {
        let verifyValue = normalizeAttr(inputElement.attrText("verify"))
        let onclickValue = normalizeAttr(inputElement.attrText("onclick")).lowercased()
        if verifyValue.isEmpty && !onclickValue.contains("opencitybox") { return false }
        if locationVerifyMarkers.contains(where: { verifyValue.contains($0) }) { return true }
        return onclickValue.contains("opencitybox")
    }

    static func textInputCandidates(_ questionDiv: Element) -> [Element] {
        (try? questionDiv.select("input, textarea, span, div").array()) ?? []
    }

    static func countTextInputs(_ questionDiv: Element) -> Int {
        var count = 0
        for candidate in textInputCandidates(questionDiv) {
            let tagName = candidate.tagName().lowercased()
            let inputType = normalizeAttr(candidate.attrText("type")).lowercased()
            let styleText = normalizeAttr(candidate.attrText("style")).lowercased()
            let classText = (candidate.classValue()).lowercased()
            let isTextcont = classText.contains("textcont") || classText.contains("textedit")

            if inputType == "hidden" || styleText.contains("display:none") || styleText.contains("visibility:hidden") {
                continue
            }
            if tagName == "input" && inputLooksLikeLocation(candidate) { continue }
            if tagName == "textarea" || (tagName == "input" && textInputAllowedTypes.contains(inputType)) {
                count += 1
                continue
            }
            let contenteditable = normalizeAttr(candidate.attrText("contenteditable")).lowercased() == "true"
            if (contenteditable || isTextcont) && ["span", "div"].contains(tagName) {
                count += 1
            }
        }
        return count
    }

    static func extractTextInputLabels(_ questionDiv: Element) -> [String] {
        var labels: [String] = []
        for candidate in textInputCandidates(questionDiv) {
            let tagName = candidate.tagName().lowercased()
            let inputType = normalizeAttr(candidate.attrText("type")).lowercased()
            let styleText = normalizeAttr(candidate.attrText("style")).lowercased()
            let classText = (candidate.classValue()).lowercased()
            let isTextcont = classText.contains("textcont") || classText.contains("textedit")

            if inputType == "hidden" || styleText.contains("display:none") || styleText.contains("visibility:hidden") {
                continue
            }
            if tagName == "input" && inputLooksLikeLocation(candidate) { continue }

            var isTextInput = false
            if tagName == "textarea" || (tagName == "input" && textInputAllowedTypes.contains(inputType)) {
                isTextInput = true
            } else {
                let contenteditable = normalizeAttr(candidate.attrText("contenteditable")).lowercased() == "true"
                if (contenteditable || isTextcont) && ["span", "div"].contains(tagName) {
                    isTextInput = true
                }
            }
            if isTextInput {
                var label = ""
                for key in ["placeholder", "aria-label", "data-label"] {
                    label = normalizeAttr(candidate.attrText(key))
                    if !label.isEmpty { break }
                }
                if label.isEmpty {
                    label = previousSiblingText(candidate)
                }
                if label.isEmpty {
                    label = labelBeforeNode(candidate)
                }
                if label.isEmpty && isTextcont, let parent = candidate.parent() {
                    label = labelBeforeNode(parent)
                }
                labels.append(label.isEmpty ? "填空\(labels.count + 1)" : label)
            }
        }
        return labels
    }

    /// 对标 find_previous_sibling(string=True)：最近的、有文本的前驱兄弟节点文本。
    static func previousSiblingText(_ element: Element) -> String {
        guard let parent = element.parent() else { return "" }
        let siblings = parent.getChildNodes()
        guard let index = siblings.firstIndex(where: { $0 === element as Node }) else { return "" }
        var cursor = index - 1
        while cursor >= 0 {
            let node = siblings[cursor]
            if let textNode = node as? TextNode {
                let text = normalizeHtmlText(textNode.text())
                if !text.isEmpty {
                    return text.trimmingCharacters(in: CharacterSet(charactersIn: "：:"))
                        .trimmingCharacters(in: .whitespaces)
                }
            }
            cursor -= 1
        }
        return ""
    }

    /// 对标 _label_before_node：收集前驱兄弟节点的文本，跳过 input，遇 label/span/br 停止。
    static func labelBeforeNode(_ element: Element) -> String {
        var parts: [String] = []
        guard let parent = element.parent() else { return "" }
        let siblings = parent.getChildNodes()
        guard let index = siblings.firstIndex(where: { $0 === element as Node }) else { return "" }
        var cursor = index - 1
        while cursor >= 0 {
            let node = siblings[cursor]
            if let elementNode = node as? Element {
                let name = elementNode.tagName().lowercased()
                if ["input", "textarea", "label", "span"].contains(name) {
                    if name == "input" {
                        cursor -= 1
                        continue
                    }
                    break
                }
                if name == "br" { break }
                let text = normalizeHtmlText(elementNode.textValue())
                if !text.isEmpty { parts.append(text) }
            } else if let textNode = node as? TextNode {
                let text = normalizeHtmlText(textNode.text())
                if !text.isEmpty { parts.append(text) }
            }
            cursor -= 1
        }
        let joined = parts.reversed().joined(separator: " ")
        return joined.trimmingCharacters(in: CharacterSet(charactersIn: "：:"))
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - 文本类判定

    static func shouldTreatAsTextLike(
        _ typeCode: String, optionCount: Int, textInputCount: Int,
        hasSliderMatrix: Bool, isLocation: Bool
    ) -> Bool {
        if isLocation { return false }
        if hasSliderMatrix { return false }
        if ["1", "2", "9"].contains(typeCode) { return textInputCount > 0 }
        if knownNonTextQuestionTypes.contains(typeCode) { return false }
        return optionCount <= 1 && textInputCount > 0
    }

    static func shouldMarkAsMultiText(
        _ typeCode: String, optionCount: Int, textInputCount: Int,
        isLocation: Bool, hasGapfill: Bool, hasSliderMatrix: Bool
    ) -> Bool {
        if isLocation { return false }
        if hasSliderMatrix { return false }
        if typeCode == "9" && hasGapfill { return true }
        if textInputCount < 2 { return false }
        if ["1", "2", "9"].contains(typeCode) { return true }
        if knownNonTextQuestionTypes.contains(typeCode) { return false }
        if optionCount == 0 { return true }
        return optionCount <= 1 && textInputCount >= 2
    }

    // MARK: - 强制选项（"请务必选择第X项"）

    static let forceSelectCleanRegex = try! NSRegularExpression(
        pattern: #"[\s`'""''【】\[\]\(\)（）<>《》,，、。；;:：!?！？]"#
    )

    static func normalizeForceSelectText(_ value: Any?) -> String {
        let text = normalizeMatchText(value)
        if text.isEmpty { return "" }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let cleaned = forceSelectCleanRegex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        return cleaned.lowercased()
    }

    static func extractForceSelectOptionLabel(_ optionText: String) -> String? {
        let text = normalizeMatchText(optionText)
        if text.isEmpty { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = forceSelectOptionLabelRegex.firstMatch(in: text, options: [], range: range),
              let r = Range(match.range(at: 1), in: text) else { return nil }
        let label = String(text[r]).trimmingCharacters(in: .whitespaces).uppercased()
        return label.isEmpty ? nil : label
    }

    static func collectForceSelectFragments(_ questionDiv: Element, titleText: String) -> [String] {
        var fragments: [String] = []
        let cleanedTitle = normalizeHtmlText(titleText)
        if !cleanedTitle.isEmpty { fragments.append(cleanedTitle) }
        for selector in [".qtypetip", ".topichtml", ".field-label"] {
            guard let element = try? questionDiv.select(selector).first() else { continue }
            let text = normalizeHtmlText(try? element.text())
            if !text.isEmpty { fragments.append(text) }
        }
        var unique: [String] = []
        var seen: Set<String> = []
        for fragment in fragments {
            let key = normalizeHtmlText(fragment)
            if key.isEmpty || seen.contains(key) { continue }
            seen.insert(key)
            unique.append(key)
        }
        return unique
    }

    static func extractForceSelectOption(
        _ questionDiv: Element, titleText: String, optionTexts: [String]
    ) -> (Int?, String?) {
        if optionTexts.isEmpty { return (nil, nil) }

        var normalizedOptions: [(index: Int, rawText: String, normalized: String)] = []
        for (index, optionText) in optionTexts.enumerated() {
            let normalized = normalizeForceSelectText(optionText)
            if normalized.isEmpty { continue }
            normalizedOptions.append((index, normalizeAttr(optionText), normalized))
        }
        if normalizedOptions.isEmpty { return (nil, nil) }

        let fragments = collectForceSelectFragments(questionDiv, titleText: titleText)
        for fragment in fragments {
            let fragmentRange = NSRange(fragment.startIndex..<fragment.endIndex, in: fragment)
            let commandMatches = forceSelectCommandRegex.matches(in: fragment, options: [], range: fragmentRange)
            for commandMatch in commandMatches {
                guard let commandEnd = Range(commandMatch.range, in: fragment).map({ fragment[$0].endIndex }) else { continue }
                let tailText = String(fragment[commandEnd...])
                if tailText.isEmpty { continue }

                let tailRange = NSRange(tailText.startIndex..<tailText.endIndex, in: tailText)
                let sentenceMatches = forceSelectSentenceSplitRegex.matches(in: tailText, options: [], range: tailRange)
                let firstSplit = sentenceMatches.first.flatMap { Range($0.range, in: tailText).map { tailText.distance(from: tailText.startIndex, to: $0.lowerBound) } }
                let rawSentence = firstSplit.map { String(tailText[tailText.startIndex..<tailText.index(tailText.startIndex, offsetBy: $0)]) } ?? tailText
                var sentence = rawSentence.trimmingCharacters(in: CharacterSet(charactersIn: " ：:，,、"))
                if sentence.isEmpty { continue }

                let normalizedSentence = normalizeMatchText(sentence)
                let compactSentence = normalizeForceSelectText(sentence)
                if compactSentence.isEmpty { continue }

                // 第X项 / X个 / X分
                let normalizedRange = NSRange(normalizedSentence.startIndex..<normalizedSentence.endIndex, in: normalizedSentence)
                if let indexMatch = forceSelectIndexTargetRegex.firstMatch(in: normalizedSentence, options: [], range: normalizedRange),
                   let r = Range(indexMatch.range(at: 1), in: normalizedSentence),
                   let targetNumber = Int(normalizedSentence[r]) {
                    let targetIndex = targetNumber - 1
                    if (0..<optionTexts.count).contains(targetIndex) {
                        let selected = normalizeAttr(optionTexts[targetIndex])
                        return (targetIndex, selected.isEmpty ? nil : selected)
                    }
                }

                // A 项 / A 选项
                let compactRange = NSRange(compactSentence.startIndex..<compactSentence.endIndex, in: compactSentence)
                if let labelMatch = forceSelectLabelTargetRegex.firstMatch(in: compactSentence, options: [], range: compactRange),
                   let r = Range(labelMatch.range(at: 1), in: compactSentence) {
                    let targetLabel = String(compactSentence[r]).trimmingCharacters(in: .whitespaces).uppercased()
                    if !targetLabel.isEmpty {
                        for option in normalizedOptions {
                            if extractForceSelectOptionLabel(option.rawText) == targetLabel {
                                return (option.index, option.rawText)
                            }
                        }
                    }
                }

                // 精确文本匹配（非纯数字）
                let exactCandidates = normalizedOptions
                    .filter { !$0.normalized.allSatisfy(\.isNumber) && $0.normalized == compactSentence }
                    .sorted { $0.normalized.count > $1.normalized.count }
                if let best = exactCandidates.first {
                    return (best.index, best.rawText)
                }
                _ = sentence
                sentence = ""
            }
        }
        return (nil, nil)
    }

    // MARK: - 跳题规则

    static func parseJumpTarget(_ rawValue: Any?) -> Int? {
        let textValue = normalizeMatchText(rawValue)
        if textValue.isEmpty { return nil }
        let range = NSRange(textValue.startIndex..<textValue.endIndex, in: textValue)
        guard let match = jumpTargetRegex.firstMatch(in: textValue, options: [], range: range),
              match.numberOfRanges >= 3 else { return nil }
        if let r = Range(match.range(at: 1), in: textValue), let value = Int(textValue[r]) { return value }
        if let r = Range(match.range(at: 2), in: textValue), let value = Int(textValue[r]) { return value }
        return nil
    }

    static func extractJumpRules(
        _ questionDiv: Element, optionTexts: [String]
    ) throws -> (hasJump: Bool, rules: [[String: Any]]) {
        let hasJumpAttr = normalizeAttr(questionDiv.attrText("hasjump")) == "1"
        var jumpRules: [[String: Any]] = []

        func jumpTargetTerminates(_ jumptoNum: Int, optionText: String?) -> Bool {
            if let optionText, terminateKeywords.contains(where: { optionText.contains($0) }) {
                return true
            }
            return jumptoNum == 1 || jumptoNum == -1
        }

        var selectableNodes: [Element] = []
        if let inputs = try? questionDiv.select("input").array() {
            for inputElement in inputs {
                let inputType = normalizeAttr(inputElement.attrText("type")).lowercased()
                if ["radio", "checkbox"].contains(inputType) {
                    selectableNodes.append(inputElement)
                }
            }
        }
        if selectableNodes.isEmpty {
            if let options = try? questionDiv.select("option").array() {
                for (optionIndex, optionElement) in options.enumerated() {
                    let optionText = normalizeHtmlText(try? optionElement.text())
                    let optionValue = optionElement.attrText("value")
                    if isSelectPlaceholderOption(index: optionIndex, value: optionValue, text: optionText) {
                        continue
                    }
                    selectableNodes.append(optionElement)
                }
            }
        }

        var optionIdx = 0
        for selectableNode in selectableNodes {
            var jumptoRaw = normalizeAttr(selectableNode.attrText("jumpto"))
            if jumptoRaw.isEmpty { jumptoRaw = normalizeAttr(selectableNode.attrText("data-jumpto")) }
            if jumptoRaw.isEmpty {
                optionIdx += 1
                continue
            }
            if let jumptoNum = parseJumpTarget(jumptoRaw), jumptoNum != 0 {
                let optionText = optionIdx < optionTexts.count ? optionTexts[optionIdx] : nil
                jumpRules.append([
                    "option_index": optionIdx,
                    "jumpto": jumptoNum,
                    "option_text": optionText ?? NSNull(),
                    "terminates_survey": jumpTargetTerminates(jumptoNum, optionText: optionText),
                ])
            }
            optionIdx += 1
        }

        if hasJumpAttr {
            var unconditionalTarget: Int? = nil
            for attrName in ["jumpto", "data-jumpto", "goto", "data-goto", "anyjump", "data-anyjump"] {
                unconditionalTarget = parseJumpTarget(questionDiv.attrText(attrName))
                if unconditionalTarget != nil { break }
            }
            if let target = unconditionalTarget {
                let exists = jumpRules.contains { rule in
                    JSONCoercion.asInt(rule["option_index"]) < 0 && JSONCoercion.asInt(rule["jumpto"]) == target
                }
                if !exists {
                    jumpRules.append([
                        "option_index": -1,
                        "jumpto": target,
                        "option_text": NSNull(),
                    ])
                }
            }
        }
        return (hasJumpAttr || !jumpRules.isEmpty, jumpRules)
    }

    // MARK: - 显示条件

    static func extractDisplayConditions(_ questionDiv: Element) throws -> (hasCondition: Bool, conditions: [[String: Any]]) {
        let relationRaw = normalizeAttr(questionDiv.attrText("relation"))
        if relationRaw.isEmpty { return (false, []) }

        var conditions: [[String: Any]] = []
        var seen: Set<String> = []
        let chunks = relationRaw.components(separatedBy: "|")
        for chunk in chunks {
            let text = normalizeMatchText(chunk)
            if text.isEmpty { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = relationChunkRegex.firstMatch(in: text, options: [], range: range),
                  match.numberOfRanges >= 3,
                  let sourceRange = Range(match.range(at: 1), in: text),
                  let optionsRange = Range(match.range(at: 2), in: text),
                  let sourceQuestionNum = Int(text[sourceRange]) else { continue }

            var optionIndices: [Int] = []
            var seenIndices: Set<Int> = []
            for rawOption in text[optionsRange].components(separatedBy: ",") {
                guard let optionNum = Int(normalizeMatchText(rawOption)) else { continue }
                if optionNum <= 0 { continue }
                let optionIndex = optionNum - 1
                if seenIndices.contains(optionIndex) { continue }
                seenIndices.insert(optionIndex)
                optionIndices.append(optionIndex)
            }
            if sourceQuestionNum <= 0 || optionIndices.isEmpty { continue }
            let dedupeKey = "\(sourceQuestionNum):\(optionIndices.map({ String($0) }).joined(separator: ","))"
            if seen.contains(dedupeKey) { continue }
            seen.insert(dedupeKey)
            conditions.append([
                "condition_question_num": sourceQuestionNum,
                "condition_mode": "selected",
                "condition_option_indices": optionIndices,
                "raw_relation": text,
            ])
        }
        return (!conditions.isEmpty, conditions)
    }

    static func attachDisplayConditionMetadata(_ questionsInfo: inout [[String: Any]]) {
        var byNum: [Int: Int] = [:]
        for (index, info) in questionsInfo.enumerated() {
            let questionNum = JSONCoercion.asInt(info["num"])
            if questionNum > 0 && byNum[questionNum] == nil {
                byNum[questionNum] = index
            }
        }

        for infoIndex in questionsInfo.indices {
            let displayConditions = QuestionMetaNormalizer.normalizeDictList(questionsInfo[infoIndex]["display_conditions"])
            guard !displayConditions.isEmpty else { continue }
            let targetQuestionNum = JSONCoercion.asInt(questionsInfo[infoIndex]["num"])
            for condition in displayConditions {
                let sourceQuestionNum = JSONCoercion.asInt(condition["condition_question_num"])
                let optionIndices = JSONCoercion.asIntList(condition["condition_option_indices"])
                if sourceQuestionNum <= 0 { continue }
                guard let sourceIndex = byNum[sourceQuestionNum] else { continue }

                var normalizedIndices: [Int] = []
                var seenIndices: Set<Int> = []
                for rawIndex in optionIndices {
                    if rawIndex < 0 || seenIndices.contains(rawIndex) { continue }
                    seenIndices.insert(rawIndex)
                    normalizedIndices.append(rawIndex)
                }
                if normalizedIndices.isEmpty { continue }

                var targets = QuestionMetaNormalizer.normalizeDictList(questionsInfo[sourceIndex]["controls_display_targets"])
                let duplicate = targets.contains { existing in
                    JSONCoercion.asInt(existing["target_question_num"]) == targetQuestionNum
                        && JSONCoercion.asIntList(existing["condition_option_indices"]) == normalizedIndices
                }
                if duplicate { continue }
                targets.append([
                    "target_question_num": targetQuestionNum,
                    "condition_option_indices": normalizedIndices,
                    "condition_mode": JSONCoercion.asTrimmedString(condition["condition_mode"]).isEmpty
                        ? "selected"
                        : JSONCoercion.asTrimmedString(condition["condition_mode"]),
                ])
                questionsInfo[sourceIndex]["controls_display_targets"] = targets
            }
        }

        for index in questionsInfo.indices {
            let targets = QuestionMetaNormalizer.normalizeDictList(questionsInfo[index]["controls_display_targets"])
            if !targets.isEmpty {
                let sorted = targets.sorted { lhs, rhs in
                    let lNum = JSONCoercion.asInt(lhs["target_question_num"])
                    let rNum = JSONCoercion.asInt(rhs["target_question_num"])
                    if lNum != rNum { return lNum < rNum }
                    return JSONCoercion.asIntList(lhs["condition_option_indices"]).lexicographicallyPrecedes(
                        JSONCoercion.asIntList(rhs["condition_option_indices"])
                    )
                }
                questionsInfo[index]["controls_display_targets"] = sorted
                questionsInfo[index]["has_dependent_display_logic"] = true
            } else {
                questionsInfo[index]["controls_display_targets"] = []
                questionsInfo[index]["has_dependent_display_logic"] = false
            }
        }
    }

    // MARK: - 多选题数量限制

    static let multiMinLimitAttributeNames = [
        "min", "minvalue", "minValue", "mincount", "minCount", "minchoice", "minChoice",
        "minselect", "minSelect", "selectmin", "selectMin", "minsel", "minSel",
        "minnum", "minNum", "minlimit", "minLimit", "data-min", "data-minvalue",
        "data-mincount", "data-minchoice", "data-minselect", "data-selectmin",
    ]
    static let multiMaxLimitAttributeNames = [
        "max", "maxvalue", "maxValue", "maxcount", "maxCount", "maxchoice", "maxChoice",
        "maxselect", "maxSelect", "selectmax", "selectMax", "maxsel", "maxSel",
        "maxnum", "maxNum", "maxlimit", "maxLimit", "data-max", "data-maxvalue",
        "data-maxcount", "data-maxchoice", "data-maxselect", "data-selectmax",
    ]

    static let chineseMultiLimitPatterns = [
        try! NSRegularExpression(pattern: #"(?:最多|至多|不超过|不超過)\s*(?:选|選|选择|選擇)?\s*(\d+)\s*[个項项]?"#),
        try! NSRegularExpression(pattern: #"(?:限选|限選)\s*(\d+)\s*[个項项条]?"#),
    ]
    static let chineseMultiRangePatterns = [
        try! NSRegularExpression(pattern: #"(?:请[选選择擇]?|可选|可選|需选|需選|选择|選擇|勾选|勾選)\s*(\d+)\s*(?:-|－|—|–|~|～|至|到)\s*(\d+)(?:\s*[个項项条])?"#),
        try! NSRegularExpression(pattern: #"至少\s*(\d+)\s*[个項项条]?(?:[^0-9]{0,6})(?:最多|至多|不超过|不超過)\s*(\d+)\s*[个項项条]?"#),
        try! NSRegularExpression(pattern: #"(?:限选|限選)\s*(\d+)\s*(?:-|－|—|–|~|～|至|到)\s*(\d+)(?:\s*[个項项条])?"#),
    ]
    static let chineseMultiExactPatterns = [
        try! NSRegularExpression(pattern: #"(?:请)?(?:选|選|选择|選擇|勾选|勾選)\s*(\d+)\s*[个項项条]"#),
        try! NSRegularExpression(pattern: #"(?:必须|需|需要)\s*(?:选|選|选择|選擇|勾选|勾選)\s*(\d+)\s*[个項项条]"#),
    ]
    static let chineseMultiMinPatterns = [
        try! NSRegularExpression(pattern: #"(?:至少|最少|不少于)\s*(?:选|選|选择|選擇)?\s*(\d+)\s*[个項项条]"#),
    ]
    static let selectionKeywordsCn = ["选", "選", "选择", "多选", "复选"]

    static func safePositiveInt(_ value: String?) -> Int? {
        guard let value, !value.isEmpty else { return nil }
        let text = normalizeMatchText(value)
        if text.isEmpty { return nil }
        if let direct = Int(text), direct > 0 { return direct }
        let digits = text.prefix { $0.isNumber }
        if let number = Int(digits), number > 0 { return number }
        return nil
    }

    static func extractMinMaxFromAttributes(_ element: Element) -> (Int?, Int?) {
        var minLimit: Int? = nil
        var maxLimit: Int? = nil
        for attr in multiMinLimitAttributeNames {
            if let candidate = safePositiveInt(normalizeAttr(element.attrText(attr))) {
                minLimit = candidate
                break
            }
        }
        for attr in multiMaxLimitAttributeNames {
            if let candidate = safePositiveInt(normalizeAttr(element.attrText(attr))) {
                maxLimit = candidate
                break
            }
        }
        return (minLimit, maxLimit)
    }

    static func extractMultiLimitRangeFromText(_ text: String?) -> (Int?, Int?) {
        guard let text else { return (nil, nil) }
        let normalized = normalizeMatchText(text)
        if normalized.isEmpty { return (nil, nil) }

        var minLimit: Int? = nil
        var maxLimit: Int? = nil
        let containsCnKeyword = selectionKeywordsCn.contains { normalized.contains($0) }
        let containsCnMinHint = ["至少", "最少", "不少于"].contains { normalized.contains($0) }
        let containsCnMaxHint = ["最多", "至多", "不超过", "不超過", "限选", "限選"].contains { normalized.contains($0) }

        func matchGroup(_ pattern: NSRegularExpression, group: Int) -> Int? {
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            guard let match = pattern.firstMatch(in: normalized, options: [], range: range),
                  let r = Range(match.range(at: group), in: normalized) else { return nil }
            return Int(normalized[r])
        }

        if containsCnKeyword {
            for pattern in chineseMultiRangePatterns {
                if let first = matchGroup(pattern, group: 1), let second = matchGroup(pattern, group: 2) {
                    minLimit = min(first, second)
                    maxLimit = max(first, second)
                    break
                }
            }
        }
        if minLimit == nil && maxLimit == nil && containsCnKeyword && !containsCnMinHint && !containsCnMaxHint {
            for pattern in chineseMultiExactPatterns {
                if let candidate = matchGroup(pattern, group: 1) {
                    minLimit = candidate
                    maxLimit = candidate
                    break
                }
            }
        }
        if minLimit == nil && containsCnKeyword {
            for pattern in chineseMultiMinPatterns {
                if let candidate = matchGroup(pattern, group: 1) {
                    minLimit = candidate
                    break
                }
            }
        }
        if maxLimit == nil && containsCnKeyword {
            for pattern in chineseMultiLimitPatterns {
                if let candidate = matchGroup(pattern, group: 1) {
                    maxLimit = candidate
                    break
                }
            }
        }
        if let min = minLimit, let max = maxLimit, min > max {
            return (max, min)
        }
        return (minLimit, maxLimit)
    }

    static func extractMultipleChoiceLimits(_ questionDiv: Element) -> (Int?, Int?) {
        var (minLimit, maxLimit) = extractMinMaxFromAttributes(questionDiv)
        if minLimit == nil || maxLimit == nil {
            for fragment in collectMultiLimitTextFragments(questionDiv) {
                let (candMin, candMax) = extractMultiLimitRangeFromText(fragment)
                if minLimit == nil { minLimit = candMin }
                if maxLimit == nil { maxLimit = candMax }
                if minLimit != nil && maxLimit != nil { break }
            }
        }
        if let min = minLimit, let max = maxLimit, min > max {
            return (max, min)
        }
        return (minLimit, maxLimit)
    }

    static func collectMultiLimitTextFragments(_ questionDiv: Element) -> [String] {
        var fragments: [String] = []
        let selectors = [
            ".qtypetip", ".topichtml", ".field-label", ".field-desc", ".question-desc",
            ".question-tip", ".qtip", ".qnotice", ".question-hint",
        ]
        for selector in selectors {
            guard let elements = try? questionDiv.select(selector).array() else { continue }
            for element in elements {
                let text = normalizeHtmlText(try? element.text())
                if !text.isEmpty { fragments.append(text) }
            }
        }
        var deduped: [String] = []
        var seen: Set<String> = []
        for fragment in fragments where !fragment.isEmpty && !seen.contains(fragment) {
            seen.insert(fragment)
            deduped.append(fragment)
        }
        return deduped
    }

    // MARK: - 元数据总入口

    static func extractQuestionMetadata(
        _ soup: Document, _ questionDiv: Element, questionNumber: Int, typeCode: String
    ) throws -> QuestionMetadata {
        var metadata = QuestionMetadata()

        if ["3", "4", "5", "11"].contains(typeCode) {
            let (texts, fillableIndices) = collectChoiceOptionTexts(questionDiv)
            metadata.optionTexts = texts
            metadata.optionCount = texts.count
            metadata.fillableIndices = fillableIndices
            if typeCode == "4" {
                let (minLimit, maxLimit) = extractMultipleChoiceLimits(questionDiv)
                metadata.multiMinLimit = minLimit
                metadata.multiMaxLimit = maxLimit
            }
        } else if typeCode == "7" {
            metadata.optionTexts = collectSelectOptionTexts(questionDiv, soup: soup, questionNumber: questionNumber)
            metadata.optionCount = metadata.optionTexts.count
            if metadata.optionCount > 0 && questionDivHasSharedTextInput(questionDiv) {
                metadata.fillableIndices = [metadata.optionCount - 1]
            }
        } else if typeCode == "6" {
            let (rows, optionTexts, rowTexts) = collectMatrixOptionTexts(soup, questionDiv, questionNumber: questionNumber)
            metadata.matrixRows = rows
            metadata.optionTexts = optionTexts
            metadata.rowTexts = rowTexts
            metadata.optionCount = optionTexts.count
        } else if looksLikeSliderMatrix(questionDiv) {
            // 滑块矩阵：v0.1 以输入范围生成列文本（对标 _collect_slider_matrix_metadata 简化路径）
            let (minValue, maxValue, stepValue) = extractSliderRange(questionDiv, questionNumber: questionNumber)
            metadata.optionTexts = buildSliderMatrixOptionTexts(minValue, maxValue, stepValue)
            metadata.optionCount = metadata.optionTexts.count
        } else if typeCode == "8" {
            metadata.optionCount = 1
        }
        return metadata
    }

    static func buildSliderMatrixOptionTexts(_ minValue: Double?, _ maxValue: Double?, _ stepValue: Double?) -> [String] {
        guard let minValue, let maxValue else { return [] }
        var step = stepValue ?? 1.0
        if step <= 0 { step = 1.0 }
        let low = Swift.min(minValue, maxValue)
        let high = Swift.max(minValue, maxValue)
        var values: [String] = []
        var current = low
        while current <= high + 1e-9 && values.count < 200 {
            if abs(current - current.rounded()) < 1e-6 {
                values.append(String(Int(current.rounded())))
            } else {
                var text = String(format: "%.6f", current)
                while text.hasSuffix("0") { text.removeLast() }
                if text.hasSuffix(".") { text.removeLast() }
                values.append(text)
            }
            current += step
        }
        return values
    }

    // MARK: - 媒体

    static func normalizeMediaSourceUrl(_ raw: Any?) -> String {
        let text = JSONCoercion.asTrimmedString(raw)
        if text.isEmpty { return "" }
        if text.hasPrefix("//") { return "https:\(text)" }
        return text
    }

    static func appendMediaItem(
        _ media: inout [[String: Any]], scope: String, index: Int?, sourceUrl: Any?, label: String
    ) {
        let normalizedUrl = normalizeMediaSourceUrl(sourceUrl)
        if normalizedUrl.isEmpty { return }
        let item: [String: Any] = [
            "kind": "image",
            "scope": scope,
            "index": index ?? NSNull(),
            "source_url": normalizedUrl,
            "label": normalizeAttr(label),
        ]
        let exists = media.contains { existing in
            JSONCoercion.asString(existing["source_url"]) == normalizedUrl
                && JSONCoercion.asInt(existing["index"], default: -1) == (index ?? -1)
                && JSONCoercion.asString(existing["scope"]) == scope
        }
        if !exists { media.append(item) }
    }

    static func imageSource(_ image: Element) -> String {
        for key in ["src", "data-src", "data-original"] {
            let value = normalizeAttr(image.attrText(key))
            if !value.isEmpty { return value }
        }
        return ""
    }

    static func collectQuestionMedia(_ questionDiv: Element, rowTexts: [String], optionTexts: [String]) -> [[String: Any]] {
        var media: [[String: Any]] = []

        for selector in [".topichtml", ".field-label"] {
            guard let nodes = try? questionDiv.select(selector).array() else { continue }
            for node in nodes {
                guard let images = try? node.select("img").array() else { continue }
                for image in images {
                    appendMediaItem(&media, scope: "title", index: nil, sourceUrl: imageSource(image), label: "题干图")
                }
            }
        }

        var optionNodes: [Element] = []
        for selector in [".ui-controlgroup > div", "ul > li"] {
            if let found = try? questionDiv.select(selector).array(), !found.isEmpty {
                optionNodes = found
                break
            }
        }
        for (optionIndex, node) in optionNodes.enumerated() {
            let optionLabel = optionIndex < optionTexts.count
                ? normalizeAttr(optionTexts[optionIndex])
                : "选项 \(optionIndex + 1)"
            guard let images = try? node.select("img").array() else { continue }
            for image in images {
                appendMediaItem(
                    &media, scope: "option", index: optionIndex,
                    sourceUrl: imageSource(image),
                    label: optionLabel.isEmpty ? "选项 \(optionIndex + 1)" : optionLabel
                )
            }
        }

        var rowNodes: [Element] = []
        for selector in ["tr[rowindex]", "tr.rowtitletr", "tr[id^='drv']"] {
            if let found = try? questionDiv.select(selector).array(), !found.isEmpty {
                rowNodes = found
                break
            }
        }
        for (rowIndex, node) in rowNodes.enumerated() {
            let rowLabel = rowIndex < rowTexts.count
                ? normalizeAttr(rowTexts[rowIndex])
                : "第 \(rowIndex + 1) 行"
            guard let images = try? node.select("img").array() else { continue }
            for image in images {
                appendMediaItem(
                    &media, scope: "row", index: rowIndex,
                    sourceUrl: imageSource(image),
                    label: rowLabel.isEmpty ? "第 \(rowIndex + 1) 行" : rowLabel
                )
            }
        }
        return media
    }
}
