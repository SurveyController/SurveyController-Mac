// 对标 surveycore tests/test_wjx_multilevel.py

import XCTest
@testable import SurveyController

final class WjxMultilevelTests: XCTestCase {

    private let levelData = """
    华南地区
    华北地区|---华南地区
    湖南省
    广东省
    ---华北地区
    河北省
    山东省|---湖南省
    长沙市
    株洲市
    ---广东省
    广州市
    深圳市
    ---河北省
    石家庄市
    保定区
    ---山东省
    济南市
    青岛市|---长沙市
    天心区
    岳麓区
    ---株洲市
    荷塘区
    芦淞区
    ---广州市
    天河区
    白云区
    ---深圳市
    罗湖区
    龙华区
    ---石家庄市
    长安区
    新华区
    ---保定区
    竞秀区
    莲池区
    ---济南市
    历下区
    章丘区
    ---青岛市
    黄岛区
    崂山区〒大区|省份|城市|区县
    """

    private func menuHtml() -> String {
        let escaped = levelData
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<input id=\"hfLevelData\" value=\"\(escaped)\">"
    }

    private func pageHtml() -> String {
        var questions = ""
        for num in 1...10 {
            questions += "<div topic=\"\(num)\" type=\"1\"><input id=\"q\(num)\" type=\"text\"></div>"
        }
        return """
        <html><head><title>多级下拉样本 - 问卷星</title></head><body>
        <div id="divQuestion"><fieldset>
        \(questions)
        <div topic="11" id="div11" type="9" gapfill="1" relation="0" style="display:none;">
          <div class="field-label"><div class="topicnumber">11.</div><div class="topichtml">题目</div></div>
        </div>
        <div topic="12" id="div12" type="1" req="1">
          <div class="field-label"><div class="topicnumber">11.</div><div class="topichtml">请选择：</div></div>
          <input type="text" id="q12" verify="多级下拉" readonly="readonly"
            onclick="openCityBox(this,5,event,12);">
        </div>
        </fieldset></div>
        <script>function DecodeId(input) { return input ^ 2130030173; }
        var activityId = DecodeId(1797297031);</script>
        </body></html>
        """
    }

    func test_multilevel_paths_follow_parents_and_use_wjx_separator() throws {
        let options = try WjxMultilevel.parseOptions(fromHtml: menuHtml())
        XCTAssertEqual(options.optionTexts.count, 16)
        XCTAssertEqual(options.optionTexts.first, "华南地区‐湖南省‐长沙市‐天心区")
        XCTAssertEqual(options.optionTexts.last, "华北地区‐山东省‐青岛市‐崂山区")
        XCTAssertFalse(options.optionTexts.contains("华南地区‐河北省‐长沙市‐天心区"))
        XCTAssertEqual(options.submitValues, options.optionTexts)
        XCTAssertEqual(options.levelLabels, ["大区", "省份", "城市", "区县"])
    }

    func test_multilevel_preserves_submission_markers_and_decodes_cid_data() throws {
        let data = "总部╰1╯┌|---总部╰1╯┌\n研发部〒公司|部门"
        let escaped = data
            .replacingOccurrences(of: "\"", with: "&quot;")
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? data
        let html = "<input id=\"hfLevelData\" value=\"\(escaped)\">"
        let options = try WjxMultilevel.parseOptions(fromHtml: html, encoded: true)
        XCTAssertEqual(options.optionTexts, ["总部‐研发部"])
        XCTAssertEqual(options.submitValues, ["总部┌‐研发部"])
    }

    func test_multilevel_stops_at_hidden_child_levels() throws {
        let data = "甲\n乙|---甲\n无下级々\n---乙\n分部|---无下级々\n占位々\n---分部\n研发部"
        let escaped = data.replacingOccurrences(of: "\"", with: "&quot;")
        let options = try WjxMultilevel.parseOptions(fromHtml: "<input id=\"hfLevelData\" value=\"\(escaped)\">")
        XCTAssertEqual(options.submitValues, ["甲", "乙‐分部‐研发部"])
    }

    func test_parser_detects_multilevel_and_skips_hidden_empty_gapfill() throws {
        let questions = try WjxHtmlParser.parseSurveyQuestions(fromHtml: pageHtml())
        XCTAssertEqual(questions.count, 11)
        XCTAssertFalse(questions.contains { $0.num == 11 })
        let question = try XCTUnwrap(questions.last)
        XCTAssertEqual(question.num, 12)
        XCTAssertEqual(question.displayNum, 11)
        XCTAssertEqual(question.typeCode, "7")
        XCTAssertEqual(question.providerType, "multilevel_dropdown")
        XCTAssertEqual(question.textInputs, 0)
        XCTAssertFalse(question.isTextLike)
        let raw = try XCTUnwrap(question.providerPageRaw as? [String: Any])
        XCTAssertEqual(raw["cid"] as? String, "")
    }

    func test_multilevel_answer_action_submits_path_instead_of_index() throws {
        let options = try WjxMultilevel.parseOptions(fromHtml: menuHtml())
        let question = SurveyQuestionMeta(
            num: 12,
            title: "多级下拉",
            typeCode: "7",
            options: options.optionTexts.count,
            optionTexts: options.optionTexts,
            providerType: WjxMultilevel.providerType,
            providerPageRaw: [
                "submit_values": options.submitValues,
                "level_labels": options.levelLabels,
            ]
        )
        let action = AnswerAction(
            questionNum: 12, kind: "choice", inputType: "radio",
            selectedIndices: [15], selectedTexts: [options.optionTexts[15]], recordType: "dropdown"
        )
        let mapped = try WjxMultilevel.applyAnswer(action, question: question)
        XCTAssertEqual(mapped.kind, "text")
        XCTAssertEqual(mapped.textValues, ["华北地区‐山东省‐青岛市‐崂山区"])
        XCTAssertEqual(
            try WjxSubmitCodec.submitdataFromActions([mapped], questions: [question]),
            "12$华北地区‐山东省‐青岛市‐崂山区"
        )
    }

    func test_config_round_trip_preserves_provider_page_raw() throws {
        let options = try WjxMultilevel.parseOptions(fromHtml: menuHtml())
        let question = SurveyQuestionMeta(
            num: 12,
            title: "多级下拉",
            typeCode: "7",
            options: options.optionTexts.count,
            optionTexts: options.optionTexts,
            providerType: WjxMultilevel.providerType,
            providerPageRaw: [
                "cid": "abc",
                "submit_values": options.submitValues,
                "level_labels": options.levelLabels,
            ]
        )
        var config = RuntimeConfig()
        config.questionsInfo = [question]

        let payload = ConfigCodec.serializeRuntimeConfig(config)
        let restored = try ConfigCodec.deserializeRuntimeConfig(payload)
        let restoredQuestion = try XCTUnwrap(restored.questionsInfo.first)
        XCTAssertEqual(restoredQuestion.providerType, "multilevel_dropdown")
        let raw = try XCTUnwrap(restoredQuestion.providerPageRaw as? [String: Any])
        XCTAssertEqual(raw["cid"] as? String, "abc")
        XCTAssertEqual((raw["submit_values"] as? [String])?.count, 16)
    }
}
