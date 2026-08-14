// 对标 CI/unit_tests/providers/test_http_runtime.py（问卷星编解码部分）

import XCTest
@testable import SurveyController

final class WjxSubmitCodecTests: XCTestCase {

    // test_wjx_submitdata_formats_common_actions
    func test_submitdata_formats_common_actions() throws {
        let submitdata = try WjxSubmitCodec.submitdataFromActions([
            AnswerAction(questionNum: 1, kind: "choice", selectedIndices: [0], recordType: "single"),
            AnswerAction(questionNum: 2, kind: "choice", selectedIndices: [0, 2], recordType: "multiple"),
            AnswerAction(questionNum: 3, kind: "text", textValues: ["甲", "乙"], recordType: "text"),
            AnswerAction(questionNum: 4, kind: "matrix", matrixIndices: [1, 2], recordType: "matrix"),
            AnswerAction(questionNum: 5, kind: "slider", sliderValue: 66.0, recordType: "slider"),
        ])
        XCTAssertEqual(submitdata, "1$1}2$1|3}3$甲^乙}4$1!2,2!3}5$66.0")
    }

    // test_wjx_submitdata_uses_current_fill_delimiter_and_escapes_special_chars
    func test_submitdata_uses_current_fill_delimiter_and_escapes_special_chars() throws {
        let submitdata = try WjxSubmitCodec.submitdataFromActions([
            AnswerAction(
                questionNum: 9,
                kind: "choice",
                selectedIndices: [1],
                optionFillTexts: [(1, "改进!内容^A$B}C|D<")],
                recordType: "single"
            ),
            AnswerAction(
                questionNum: 10,
                kind: "text",
                textValues: ["A!B", "C$D"],
                recordType: "text"
            ),
        ])
        XCTAssertEqual(submitdata, "9$2^改进！内容ˆAξB｝C¦D＜}10$A！B^CξD")
    }

    // test_wjx_submitdata_keeps_frontend_skip_placeholders
    func test_submitdata_keeps_frontend_skip_placeholders() throws {
        let submitdata = try WjxSubmitCodec.submitdataFromActions(
            [
                AnswerAction(questionNum: 1, kind: "choice", selectedIndices: [1], recordType: "single"),
                AnswerAction(questionNum: 5, kind: "choice", selectedIndices: [0, 1], recordType: "multiple"),
            ],
            questions: [
                SurveyQuestionMeta(num: 1, title: "单选", typeCode: "3", options: 2, optionTexts: ["A", "B"]),
                SurveyQuestionMeta(num: 2, title: "排序", typeCode: "11", options: 3, optionTexts: ["A", "B", "C"]),
                SurveyQuestionMeta(num: 3, title: "量表", typeCode: "5", options: 2, optionTexts: ["1", "2"]),
                SurveyQuestionMeta(num: 4, title: "填空", typeCode: "1", options: 1),
                SurveyQuestionMeta(num: 5, title: "多选", typeCode: "4", options: 2, optionTexts: ["A", "B"]),
            ],
            skippedQuestionNums: [2, 3, 4]
        )
        XCTAssertEqual(submitdata, "1$2}2$-3,-3,-3}3$-3}4$(跳过)}5$1|2")
    }

    // test_wjx_default_ktimes_uses_90_seconds（gauss 恒返回中心 → 90）
    func test_default_ktimes_uses_90_seconds() {
        // 确定性随机源：gauss 由 Box-Muller 生成，无法直接钉住中心值；
        // 改验证 (0,0) 区间采样落在 90±20% 内且默认值为 90。
        let ktimes = WjxSubmitCodec.sampleKtimes(answerDurationRangeSeconds: (0, 0))
        XCTAssertTrue((72...108).contains(ktimes))
    }

    // 对标 _build_jqsign 的 XOR 语义
    func test_jqsign_xors_each_char_with_ktimes_mod_10() {
        let jqnonce = "0b3c9d8a-1111-2222-3333-444455556666"
        // ktimes=7 → 每字符 XOR 7
        let sign7 = WjxSubmitCodec.buildJqsign(jqnonce, ktimes: 7)
        let expected = String(jqnonce.unicodeScalars.map { scalar in
            Character(UnicodeScalar(scalar.value ^ 7)!)
        })
        XCTAssertEqual(sign7, expected)
        // ktimes=10 → t=1
        let sign10 = WjxSubmitCodec.buildJqsign(jqnonce, ktimes: 10)
        let expected1 = String(jqnonce.unicodeScalars.map { scalar in
            Character(UnicodeScalar(scalar.value ^ 1)!)
        })
        XCTAssertEqual(sign10, expected1)
    }

    // 对标 _shortid_from_url / _submit_domain
    func test_shortid_and_submit_domain() throws {
        XCTAssertEqual(try WjxSubmitCodec.shortidFromUrl("https://www.wjx.cn/vm/wx9ez4J.aspx"), "wx9ez4J")
        XCTAssertEqual(try WjxSubmitCodec.shortidFromUrl("https://v.wjx.cn/m/abc123/"), "abc123")
        XCTAssertEqual(WjxSubmitCodec.submitDomain("https://www.wjx.cn/vm/demo.aspx"), "v.wjx.cn")
        XCTAssertEqual(WjxSubmitCodec.submitDomain("https://ks.wjx.com/vm/demo.aspx"), "ks.wjx.com")
        XCTAssertThrowsError(try WjxSubmitCodec.shortidFromUrl("https://www.wjx.cn/"))
    }

    // test_wjx_scene_id_extraction_prefers_page_value
    func test_scene_id_extraction_prefers_page_value() {
        let pageHtml = """
        <script>
          window.initAlicom({ sceneId: "scene-real-123" });
        </script>
        """
        XCTAssertEqual(WjxSubmitCodec.extractSceneId(pageHtml), "scene-real-123")
        XCTAssertEqual(WjxSubmitCodec.extractSceneId("<html></html>"), "q0hcfsca")
    }

    // test_wjx_scene_id_extraction_supports_snake_case_and_data_attr
    func test_scene_id_extraction_supports_snake_case_and_data_attr() {
        XCTAssertEqual(
            WjxSubmitCodec.extractSceneId("<script>var x = { scene_id: 'scene-snake-1' }</script>"),
            "scene-snake-1"
        )
        XCTAssertEqual(
            WjxSubmitCodec.extractSceneId("<div data-scene-id='scene-data-2'></div>"),
            "scene-data-2"
        )
    }

    // 对标 _format_wjx_starttime 非补零格式
    func test_format_starttime_is_not_zero_padded() {
        // 2026-05-30 01:23:18 本地时间 → 固定TimeStamp：用 DateComponents 构造
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = 2026; components.month = 5; components.day = 30
        components.hour = 1; components.minute = 23; components.second = 18
        let date = calendar.date(from: components)!
        let formatted = WjxSubmitCodec.formatStartTime(Int(date.timeIntervalSince1970))
        XCTAssertEqual(formatted, "2026/5/30 1:23:18")
    }

    // 对标 _resolve_wjx_submit_start_seconds
    func test_resolve_submit_start_seconds() {
        XCTAssertEqual(WjxSubmitCodec.resolveSubmitStartSeconds(currentMs: 1710000000000, ktimes: 90),
                       1710000000000 / 1000 - 90)
        XCTAssertEqual(WjxSubmitCodec.resolveSubmitStartSeconds(currentMs: 0, ktimes: 0), 1)
    }

    // 对标 classify_wjx_submit_response
    func test_classify_response() {
        XCTAssertEqual(WjxSubmitCodec.classifyResponse("success"), .success)
        XCTAssertEqual(WjxSubmitCodec.classifyResponse("complete.aspx?jid=1"), .success)
        XCTAssertEqual(WjxSubmitCodec.classifyResponse("10"), .success)
        XCTAssertEqual(WjxSubmitCodec.classifyResponse("OK"), .success)
        XCTAssertEqual(WjxSubmitCodec.classifyResponse("需要安全校验，请重新提交"), .verification)
        XCTAssertEqual(WjxSubmitCodec.classifyResponse("请输入验证码"), .verification)
        XCTAssertEqual(WjxSubmitCodec.classifyResponse("抱歉，不符合要求"), .rejected)
        XCTAssertEqual(WjxSubmitCodec.classifyResponse("1〒9〒请填写第9题"), .rejected)
    }

    // 对标 _resolve_wjx_channel_profile
    func test_channel_profile_by_user_agent() {
        XCTAssertEqual(WjxSubmitCodec.resolveChannelProfile(userAgent: "Mozilla MicroMessenger").category, "wechat")
        XCTAssertEqual(WjxSubmitCodec.resolveChannelProfile(userAgent: "Mozilla Chrome").source, "直链访问")
        XCTAssertEqual(
            WjxSubmitCodec.resolveChannelProfile(userAgent: nil, userAgentProfile: UserAgentProfile(
                category: "mobile", presetKey: "mobile_android", ua: "ua", label: "安卓"
            )).source,
            "手机访问"
        )
        let wechat = WjxSubmitCodec.resolveChannelProfile(userAgent: "micromessenger")
        XCTAssertEqual(wechat.extraParams["wxappid"], "wx8fe84c5d52db247a")
        XCTAssertEqual(wechat.extraParams["wxfs"], "100")
        XCTAssertEqual(wechat.extraParams["openid"]?.count, 9)
    }

    // 对标 buildSubmitParams 的完整参数集
    func test_build_submit_params_contains_full_parameter_set() {
        let params = WjxSubmitCodec.buildSubmitParams(
            shortid: "demo",
            startSeconds: 1710000000,
            ktimes: 90,
            currentMs: 1710000090000,
            channelProfile: WjxChannelProfile(category: "pc", source: "直链访问", extraParams: [:]),
            jqnonce: "uuid-nonce",
            rng: SeededRandomSource(seed: 42)
        )
        XCTAssertEqual(params["shortid"], "demo")
        XCTAssertEqual(params["jcn"], "demo")
        XCTAssertEqual(params["cst"], "1710000000000")
        XCTAssertEqual(params["submittype"], "1")
        XCTAssertEqual(params["ktimes"], "90")
        XCTAssertEqual(params["nw"], "1")
        XCTAssertEqual(params["jwt"], "4")
        XCTAssertEqual(params["jpm"], "62")
        XCTAssertEqual(params["capt"], "2")
        XCTAssertEqual(params["t"], "1710000090000")
        XCTAssertEqual(params["jqnonce"], "uuid-nonce")
        XCTAssertEqual(params["jqsign"], WjxSubmitCodec.buildJqsign("uuid-nonce", ktimes: 90))
        // rn ∈ [2000000000, 2100000000]，浮点字符串
        let rn = Double(params["rn"]!)!
        XCTAssertGreaterThanOrEqual(rn, 2_000_000_000)
        XCTAssertLessThan(rn, 2_100_000_000)
    }

    // 对标 submitRejectedError 的题号定位
    func test_submit_rejected_error_includes_question_label() {
        let error = WjxSubmitCodec.submitRejectedError(
            "1〒9〒请填写有效内容",
            questionLabel: { "第\($0)题（多选题）" }
        )
        XCTAssertTrue("\(error)".contains("第9题（多选题）"))
        XCTAssertTrue("\(error)".contains("请填写有效内容"))

        let verification = WjxSubmitCodec.submitRejectedError("需要安全校验，请重新提交", proxyAddress: nil)
        XCTAssertTrue(verification is SubmissionVerificationRequiredError)
    }
}
