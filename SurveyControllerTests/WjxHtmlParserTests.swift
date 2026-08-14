// 对标 CI/unit_tests/providers/test_wjx_html_parser.py

import XCTest
@testable import SurveyController

final class WjxHtmlParserTests: XCTestCase {

    // test_parse_survey_questions_from_html_returns_empty_when_container_missing
    func test_parse_returns_empty_when_container_missing() throws {
        let questions = try WjxHtmlParser.parseSurveyQuestions(fromHtml: "<html><body><div>无题目</div></body></html>")
        XCTAssertTrue(questions.isEmpty)
    }

    // test_parse_survey_questions_from_html_extracts_basic_question_metadata
    func test_parse_extracts_basic_question_metadata() throws {
        let html = """
        <html>
          <body>
            <div id="divQuestion">
              <fieldset>
                <div topic="1" id="div1" type="3">
                  <div class="topichtml">1. 本题检测，请选择 非常满意</div>
                  <div class="ui-controlgroup">
                    <div><span class="label">一般</span><img src="https://example.com/opt-a.png" /></div>
                    <div><span class="label">非常满意</span></div>
                  </div>
                </div>
                <div topic="2" id="div2" type="4" relation="1,2">
                  <div class="topichtml">2. 请选择你常用的功能 [至少选1项，最多选2项]<img src="https://example.com/title-q2.png" /></div>
                  <div class="ui-controlgroup">
                    <div><span class="label">功能A</span></div>
                    <div><span class="label">功能B</span></div>
                  </div>
                  <input type="checkbox" jumpto="5" />
                  <input type="checkbox" />
                </div>
              </fieldset>
            </div>
          </body>
        </html>
        """

        let questions = try WjxHtmlParser.parseSurveyQuestions(fromHtml: html)
        XCTAssertEqual(questions.count, 2)

        let first = questions[0]
        XCTAssertEqual(first.num, 1)
        XCTAssertEqual(first.displayNum, 1)
        XCTAssertEqual(first.title, "本题检测，请选择 非常满意")
        XCTAssertEqual(first.typeCode, "3")
        XCTAssertEqual(first.options, 2)
        XCTAssertEqual(first.optionTexts, ["一般", "非常满意"])
        XCTAssertEqual(first.forcedOptionIndex, 1)
        XCTAssertEqual(first.forcedOptionText, "非常满意")
        XCTAssertEqual(first.page, 1)
        XCTAssertEqual(first.logicParseStatus, logicParseStatusComplete)
        XCTAssertEqual(first.questionMedia.count, 1)
        XCTAssertEqual(first.questionMedia[0]["scope"] as? String, "option")
        XCTAssertEqual(first.questionMedia[0]["index"] as? Int, 0)
        XCTAssertEqual(first.questionMedia[0]["source_url"] as? String, "https://example.com/opt-a.png")
        XCTAssertEqual(first.questionMedia[0]["label"] as? String, "一般")

        let second = questions[1]
        XCTAssertEqual(second.num, 2)
        XCTAssertEqual(second.displayNum, 2)
        XCTAssertEqual(second.typeCode, "4")
        XCTAssertEqual(JSONCoercion.asInt(second.multiMinLimit), 1)
        XCTAssertEqual(JSONCoercion.asInt(second.multiMaxLimit), 2)
        XCTAssertTrue(second.hasJump)
        XCTAssertEqual(second.jumpRules.count, 1)
        XCTAssertEqual(JSONCoercion.asInt(second.jumpRules[0]["option_index"]), 0)
        XCTAssertEqual(JSONCoercion.asInt(second.jumpRules[0]["jumpto"]), 5)
        XCTAssertEqual(JSONCoercion.asString(second.jumpRules[0]["option_text"]), "功能A")
        XCTAssertEqual(JSONCoercion.asBool(second.jumpRules[0]["terminates_survey"]), false)
        XCTAssertTrue(second.hasDisplayCondition)
        XCTAssertEqual(JSONCoercion.asInt(second.displayConditions[0]["condition_question_num"]), 1)
        XCTAssertEqual(JSONCoercion.asIntList(second.displayConditions[0]["condition_option_indices"]), [1])
        XCTAssertEqual(second.logicParseStatus, logicParseStatusComplete)
        XCTAssertEqual(second.questionMedia.count, 1)
        XCTAssertEqual(second.questionMedia[0]["scope"] as? String, "title")
        XCTAssertEqual(second.questionMedia[0]["source_url"] as? String, "https://example.com/title-q2.png")
    }

    // test_parse_survey_questions_from_html_extracts_matrix_and_slider_metadata
    func test_parse_extracts_matrix_and_slider_metadata() throws {
        let html = """
        <html>
          <body>
            <div id="divQuestion">
              <fieldset>
                <div topic="3" id="div3" type="6">
                  <div class="topichtml">3. 请评价以下项目</div>
                  <table id="divRefTab3">
                    <tr id="drv3_1"><td></td><td>差</td><td>好</td></tr>
                    <tr rowindex="1"><td>外观</td><td><input name="q3_1_1" type="radio" /></td><td><input name="q3_1_2" type="radio" /></td></tr>
                    <tr rowindex="2"><td>功能</td><td><input name="q3_2_1" type="radio" /></td><td><input name="q3_2_2" type="radio" /></td></tr>
                  </table>
                </div>
                <div topic="4" id="div4" type="8">
                  <div class="topichtml">4. 请拖动滑块</div>
                  <input id="q4" type="range" min="1" max="5" step="0.5" />
                </div>
              </fieldset>
            </div>
          </body>
        </html>
        """

        let questions = try WjxHtmlParser.parseSurveyQuestions(fromHtml: html)

        let matrix = questions[0]
        XCTAssertEqual(matrix.num, 3)
        XCTAssertEqual(matrix.rows, 2)
        XCTAssertEqual(matrix.rowTexts, ["外观", "功能"])
        XCTAssertEqual(matrix.optionTexts, ["差", "好"])
        XCTAssertEqual(matrix.options, 2)

        let slider = questions[1]
        XCTAssertEqual(slider.num, 4)
        XCTAssertEqual(slider.typeCode, "8")
        XCTAssertEqual(slider.options, 1)
        XCTAssertEqual((slider.sliderMin as? Double) ?? 0, 1.0)
        XCTAssertEqual((slider.sliderMax as? Double) ?? 0, 5.0)
        XCTAssertEqual((slider.sliderStep as? Double) ?? 0, 0.5)
    }

    // test_parse_survey_questions_from_html_marks_description_and_multi_text_cases
    func test_parse_marks_description_and_multi_text_cases() throws {
        let html = """
        <html>
          <body>
            <div id="divQuestion">
              <fieldset>
                <div topic="5" id="div5" type="3">
                  <div class="topichtml">5. 请阅读以下说明</div>
                  <p>这里没有任何选项控件</p>
                </div>
                <div topic="6" id="div6" type="1" gapfill="1">
                  <div class="topichtml">6. 请填写你的信息</div>
                  姓名：<input type="text" />
                  电话：<input type="text" />
                </div>
                <div topic="7" id="div7" type="9" gapfill="1">
                  <div class="topichtml">
                    项目评价<input id="q7_1" style="display:none" type="text" />
                    <label class="textEdit"><span class="textCont" contenteditable="true"></span></label>
                    <div>请输入手机号<input id="q7_2" style="display:none" type="text" />
                    <label class="textEdit"><span class="textCont" contenteditable="true"></span></label></div>
                  </div>
                </div>
              </fieldset>
            </div>
          </body>
        </html>
        """

        let questions = try WjxHtmlParser.parseSurveyQuestions(fromHtml: html)

        let description = questions[0]
        XCTAssertTrue(description.isDescription)
        XCTAssertEqual(description.options, 0)

        let multiText = questions[1]
        XCTAssertEqual(multiText.textInputs, 2)
        XCTAssertEqual(multiText.textInputLabels, ["姓名", "电话"])
        XCTAssertTrue(multiText.isMultiText)
        XCTAssertTrue(multiText.isTextLike)
        XCTAssertEqual(questions[2].textInputLabels, ["项目评价", "请输入手机号"])
    }

    // test_parse_survey_questions_recalculates_display_num_when_previous_question_is_hidden
    func test_parse_recalculates_display_num_when_previous_question_is_hidden() throws {
        let html = """
        <html>
          <body>
            <div id="divQuestion">
              <fieldset>
                <div topic="20" id="div20" type="5" style="display:none;">
                  <div class="field-label">
                    <div class="topicnumber">20.</div>
                    <div class="topichtml">隐藏题</div>
                  </div>
                </div>
                <div topic="21" id="div21" type="4">
                  <div class="field-label">
                    <div class="topicnumber">21.</div>
                    <div class="topichtml">显示题一</div>
                  </div>
                </div>
                <div topic="23" id="div23" type="2">
                  <div class="field-label">
                    <div class="topicnumber">23.</div>
                    <div class="topichtml">显示题二</div>
                  </div>
                  <textarea id="q23" name="q23"></textarea>
                </div>
              </fieldset>
            </div>
          </body>
        </html>
        """

        let questions = try WjxHtmlParser.parseSurveyQuestions(fromHtml: html)
        XCTAssertEqual(questions[0].num, 20)
        XCTAssertEqual(questions[0].displayNum, 20)
        XCTAssertEqual(questions[1].num, 21)
        XCTAssertEqual(questions[1].displayNum, 1)
        XCTAssertEqual(questions[2].num, 23)
        XCTAssertEqual(questions[2].displayNum, 2)
    }

    // test_parse_survey_questions_treats_hidden_ancestor_question_as_hidden
    func test_parse_treats_hidden_ancestor_as_hidden() throws {
        let html = """
        <html>
          <body>
            <div id="divQuestion">
              <fieldset>
                <section style="display:none;">
                  <div topic="20" id="div20" type="5">
                    <div class="field-label">
                      <div class="topicnumber">20.</div>
                      <div class="topichtml">隐藏题</div>
                    </div>
                  </div>
                </section>
                <div topic="21" id="div21" type="4">
                  <div class="field-label">
                    <div class="topicnumber">21.</div>
                    <div class="topichtml">显示题一</div>
                  </div>
                  <div class="ui-controlgroup"><div><span class="label">A</span></div></div>
                </div>
              </fieldset>
            </div>
          </body>
        </html>
        """

        let questions = try WjxHtmlParser.parseSurveyQuestions(fromHtml: html)
        XCTAssertEqual(questions[0].displayNum, 20)
        XCTAssertEqual(questions[1].displayNum, 1)
    }

    // 对标 extract_survey_title_from_html
    func test_extract_survey_title() {
        let html = """
        <html><head><title>消费者满意度调研- 问卷星</title></head>
        <body><div id="divTitle"><h1>消费者满意度调研</h1></div></body></html>
        """
        XCTAssertEqual(WjxHtmlParser.extractSurveyTitle(fromHtml: html), "消费者满意度调研")
    }

    // 对标 _raise_wjx_page_state_errors 的暂停/停止状态
    func test_page_state_errors() {
        XCTAssertThrowsError(
            try WjxHtmlParser.raiseWjxPageStateErrors("<div>此问卷（12345678）已暂停，暂停期间无法填写。</div>")
        ) { error in
            XCTAssertTrue(error is SurveyPausedError)
        }
        XCTAssertThrowsError(
            try WjxHtmlParser.raiseWjxPageStateErrors("<div>问卷已停止收集，感谢参与</div>")
        ) { error in
            XCTAssertTrue(error is SurveyStoppedError)
        }
    }
}
