// 实测链路（对标 CI/live_tests/ 的门控做法）：
// 默认跳过；设 LIVE_SURVEY_URL 启用「解析+本地生成」，再设 LIVE_SURVEY_SUBMIT=1 追加一次真实提交。
// 用法：
//   LIVE_SURVEY_URL='https://v.wjx.cn/vm/xxx.aspx' \
//   LIVE_SURVEY_SUBMIT=1 \
//   xcodebuild test -only-testing:SurveyControllerTests/LiveSurveyE2ETests

import XCTest
@testable import SurveyController

final class LiveSurveyE2ETests: XCTestCase {

    var liveURL: String {
        ProcessInfo.processInfo.environment["LIVE_SURVEY_URL"] ?? ""
    }

    var allowSubmit: Bool {
        ProcessInfo.processInfo.environment["LIVE_SURVEY_SUBMIT"] == "1"
    }

    /// 全链路：解析 → 默认配置 → 生成 → submitdata →（可选）提交 1 份。
    func test_parse_generate_and_optionally_submit() async throws {
        guard !liveURL.isEmpty else {
            throw XCTSkip("未设置 LIVE_SURVEY_URL，跳过实测")
        }

        // 1. 解析
        let parseResult = try await WjxProvider.parseSurvey(url: liveURL)
        XCTAssertFalse(parseResult.questions.isEmpty, "解析出的题目为空")
        print("✅ 解析成功：\(parseResult.title)，共 \(parseResult.questions.count) 题")
        for question in parseResult.questions {
            let type = DefaultQuestionEntries.entryType(for: question)
            print("   第\(question.displayNum ?? question.num)题 [\(type)] \(question.title)（\(question.options) 选项\(question.required ? "，必答" : "")）")
        }

        // 2. 默认配置 → 运行时配置
        var runtimeConfig = RuntimeConfig()
        runtimeConfig.url = liveURL
        runtimeConfig.surveyProvider = .wjx
        runtimeConfig.surveyTitle = parseResult.title
        runtimeConfig.questionsInfo = parseResult.questions
        runtimeConfig.questionEntries = DefaultQuestionEntries.build(from: parseResult.questions)
        runtimeConfig.target = 1
        runtimeConfig.answerDuration = (60, 120)

        let execution = ExecutionConfigBuilder.build(from: runtimeConfig)
        XCTAssertEqual(execution.questionConfigIndexMap.count, parseResult.questions.count, "配置索引未覆盖全部题目")

        // 3. 生成答案 + submitdata（本地）
        var state = ExecutionState(config: execution)
        let rng = SeededRandomSource(seed: Int(Date().timeIntervalSince1970))
        let plan = try HttpLogicPlanner.buildPlan(execution.questionsOrdered) { question in
            try WjxAnswerBuilder.buildAnswerAction(question, state: &state, rng: rng)
        }
        XCTAssertFalse(plan.actions.isEmpty, "未生成任何答案动作")
        let submitdata = try WjxSubmitCodec.submitdataFromActions(
            plan.actions, questions: execution.questionsOrdered,
            skippedQuestionNums: plan.skippedQuestionNums
        )
        print("✅ 生成 submitdata（\(plan.actions.count) 题作答，跳过 \(plan.skippedQuestionNums.count) 题）：")
        print("   \(submitdata)")

        // 4. 关键参数构造（不提交）
        let currentMs = Int(Date().timeIntervalSince1970 * 1000)
        let ktimes = WjxSubmitCodec.sampleKtimes(answerDurationRangeSeconds: (60, 120), rng: rng)
        let startSeconds = WjxSubmitCodec.resolveSubmitStartSeconds(currentMs: currentMs, ktimes: ktimes)
        let params = WjxSubmitCodec.buildSubmitParams(
            shortid: try WjxSubmitCodec.shortidFromUrl(liveURL),
            startSeconds: startSeconds, ktimes: ktimes, currentMs: currentMs,
            channelProfile: WjxSubmitCodec.resolveChannelProfile(userAgent: nil),
            jqnonce: UUID().uuidString.lowercased(), rng: rng
        )
        print("✅ 提交参数：starttime=\(params["starttime"] ?? "") ktimes=\(params["ktimes"] ?? "") t=\(params["t"] ?? "")")

        // 5. 真实提交（默认关闭）
        guard allowSubmit else {
            print("⏸ 未设置 LIVE_SURVEY_SUBMIT=1，已生成答案但未提交")
            return
        }
        var context = WjxProvider.SubmitContext(state: ExecutionState(config: execution), rng: rng)
        context.userAgent = nil
        let ok = try await WjxProvider.submit(execution, context: context)
        XCTAssertTrue(ok)
        print("✅ 提交成功（服务端已接受）")
    }
}
