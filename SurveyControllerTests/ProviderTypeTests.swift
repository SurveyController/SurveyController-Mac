// 对标 CI/unit_tests/providers/test_common.py
// 命名沿用官方测试用例的描述式句子风格。

import XCTest
@testable import SurveyController

final class ProviderTypeTests: XCTestCase {

    // test_normalize_survey_provider_returns_default_for_unknown_value
    func test_normalize_survey_provider_returns_default_for_unknown_value() {
        XCTAssertEqual(ProviderType.normalizeProvider("unknown", default: .qq), .qq)
        XCTAssertEqual(ProviderType.normalizeProvider("WJX "), .wjx)
        XCTAssertEqual(ProviderType.normalizeProvider(nil), .wjx)
    }

    // test_detect_survey_provider_distinguishes_three_platforms
    func test_detect_survey_provider_distinguishes_three_platforms() {
        XCTAssertEqual(ProviderType.detectProvider("https://www.credamo.com/answer.html#/s/demo"), .credamo)
        XCTAssertEqual(ProviderType.detectProvider("https://www.credamo.com/s/demo"), .credamo)
        XCTAssertEqual(ProviderType.detectProvider("https://wj.qq.com/s2/123/abc"), .qq)
        XCTAssertEqual(ProviderType.detectProvider("https://www.wjx.cn/vm/demo.aspx"), .wjx)
    }

    // test_wjx_helpers_accept_subdomains
    func test_wjx_helpers_accept_subdomains() {
        XCTAssertTrue(ProviderType.isWjxDomain("https://foo.wjx.top/demo"))
        XCTAssertTrue(ProviderType.isWjxSurveyUrl("https://sub.v.wjx.cn/m/demo.aspx"))
        XCTAssertTrue(ProviderType.isWjxSurveyUrl("https://www.wjx.top/vm/wx9ez4J.aspx"))
    }

    // test_qq_and_credamo_helpers_reject_non_matching_paths
    func test_qq_and_credamo_helpers_reject_non_matching_paths() {
        XCTAssertFalse(ProviderType.isQqSurveyUrl("https://wj.qq.com/not-a-survey"))
        XCTAssertFalse(ProviderType.isCredamoSurveyUrl("https://www.credamo.com/profile"))
        XCTAssertTrue(ProviderType.isCredamoSurveyUrl("https://www.credamo.com/s/demo"))
    }

    // test_is_supported_survey_url_returns_false_for_unknown_domain
    func test_is_supported_survey_url_returns_false_for_unknown_domain() {
        XCTAssertFalse(ProviderType.isSupportedSurveyUrl("https://example.com/form"))
    }

    // 对标 parse_url_host：无 scheme 自动补 https，netloc 去端口，path 去空白
    func test_parse_url_host_prepends_scheme_and_strips_port() {
        XCTAssertEqual(ProviderType.parseUrlHost("www.wjx.cn/vm/demo.aspx").host, "www.wjx.cn")
        XCTAssertEqual(ProviderType.parseUrlHost("https://v.wjx.cn:443/vm/demo.aspx").host, "v.wjx.cn")
        XCTAssertEqual(ProviderType.parseUrlHost("https://wj.qq.com/s2/123/abc?a=1#frag").path, "/s2/123/abc")
        XCTAssertEqual(ProviderType.parseUrlHost("").host, "")
    }

    // 对标 normalize_survey_parse_url：见数短链重写为 /answer.html#/s/xxx
    func test_normalize_survey_parse_url_rewrites_credamo_short_link() {
        XCTAssertEqual(
            ProviderType.normalizeSurveyParseUrl("https://www.credamo.com/s/abc123"),
            "https://www.credamo.com/answer.html#/s/abc123"
        )
        XCTAssertEqual(
            ProviderType.normalizeSurveyParseUrl("www.credamo.com/s/abc123"),
            "https://www.credamo.com/answer.html#/s/abc123"
        )
    }

    // 非 见数 链接只做 scheme 补全与小写化，不改路径
    func test_normalize_survey_parse_url_leaves_non_credamo_untouched() {
        XCTAssertEqual(
            ProviderType.normalizeSurveyParseUrl("WWW.WJX.CN/vm/demo.aspx"),
            "https://www.wjx.cn/vm/demo.aspx"
        )
        XCTAssertEqual(ProviderType.normalizeSurveyParseUrl("https://wj.qq.com/s2/123/abc?x=1"), "https://wj.qq.com/s2/123/abc?x=1")
    }

    // 对标 make_provider_question_key
    func test_make_provider_question_key_requires_page_and_question_id() {
        XCTAssertEqual(ProviderType.makeProviderQuestionKey(provider: "wjx", providerPageId: " 1 ", providerQuestionId: " q1 "), "wjx:1:q1")
        XCTAssertEqual(ProviderType.makeProviderQuestionKey(provider: nil, providerPageId: "1", providerQuestionId: "q1"), "wjx:1:q1")
        XCTAssertEqual(ProviderType.makeProviderQuestionKey(provider: "wjx", providerPageId: "", providerQuestionId: "q1"), "")
    }

    // 对标 supports_answer_datetime_window
    func test_supports_answer_datetime_window_only_for_credamo() {
        XCTAssertTrue(ProviderType.supportsAnswerDatetimeWindow("credamo"))
        XCTAssertFalse(ProviderType.supportsAnswerDatetimeWindow("wjx"))
        XCTAssertFalse(ProviderType.supportsAnswerDatetimeWindow(nil))
    }

    // 对标 AppVersion.compareSemVer（安卓端 AppVersion.kt 同款语义）
    func test_compare_semver_orders_versions() {
        XCTAssertEqual(AppVersion.compareSemVer("1.2.3", "1.2.3"), 0)
        XCTAssertLessThan(AppVersion.compareSemVer("0.1.0", "1.0.0"), 0)
        XCTAssertGreaterThan(AppVersion.compareSemVer("1.10.0", "1.9.9"), 0)
        XCTAssertLessThan(AppVersion.compareSemVer("2.0.0-rc1", "2.0.0"), 0)
    }
}
