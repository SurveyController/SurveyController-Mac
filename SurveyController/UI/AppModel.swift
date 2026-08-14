// 对标 software/ui/controller/run_controller.py + run_state_store.py
// 中央视图模型：解析、配置、运行、日志、随机IP额度的唯一事实来源。

import AppKit
import Foundation
import IOKit.pwr_mgt
import Observation
import UserNotifications

public enum SurveyParsePhase: String {
    case idle
    case parsing
    case ready
    case failed
}

@MainActor
@Observable
public final class AppModel {

    // MARK: - 问卷状态

    public var surveyUrl: String = "" {
        didSet { runtimeConfig.url = surveyUrl }
    }
    public var parsePhase: SurveyParsePhase = .idle
    public var parseError: String = ""
    public var surveyTitle: String = ""
    public var surveyProvider: SurveyProvider = .wjx

    // MARK: - 配置

    public var runtimeConfig = RuntimeConfig()

    // MARK: - 向导状态（对标官方 5.0 向导式流程）

    public enum WizardStep: Int, CaseIterable, Identifiable {
        case survey = 1, answers, task, network, check, run
        public var id: Int { rawValue }

        public var title: String {
            switch self {
            case .survey: return "问卷"
            case .answers: return "答案"
            case .task: return "任务"
            case .network: return "网络"
            case .check: return "检查"
            case .run: return "运行"
            }
        }
    }

    public var wizardStep: WizardStep = .survey
    /// 最近一次切换方向（+1 前进 / -1 后退），驱动过渡动画方向
    public var wizardDirection: Int = 1
    /// 向导中已解锁到的最远步骤（可回退点击）
    public var maxReachedStep: WizardStep = .survey
    /// 答案编辑页当前选中的题目下标
    public var selectedQuestionIndex: Int = 0

    public func goToStep(_ step: WizardStep) {
        let direction = step.rawValue >= wizardStep.rawValue ? 1 : -1
        wizardStep = step
        wizardDirection = direction
        if step.rawValue > maxReachedStep.rawValue {
            maxReachedStep = step
        }
    }

    public func nextStep() {
        if let next = WizardStep(rawValue: wizardStep.rawValue + 1) {
            goToStep(next)
        }
    }

    public func previousStep() {
        if let previous = WizardStep(rawValue: wizardStep.rawValue - 1) {
            wizardStep = previous
        }
    }

    /// 当前步骤是否允许继续（向导的分步校验）。
    public var currentStepValid: Bool {
        switch wizardStep {
        case .survey:
            return parsePhase == .ready
        case .answers:
            return !runtimeConfig.questionEntries.isEmpty
        case .task:
            return runtimeConfig.target >= 1 && runtimeConfig.threads >= 1
        case .network:
            if runtimeConfig.randomIpEnabled && runtimeConfig.proxySource == proxySourceCustom {
                return !runtimeConfig.customProxyApi.trimmingCharacters(in: .whitespaces).isEmpty
            }
            return true
        case .check:
            return preflight.errors.isEmpty
        case .run:
            return true
        }
    }

    // MARK: - 运行状态

    public var isRunning: Bool = false
    public var progress: RunProgress = RunProgress()
    public var logs: [String] = []
    public var toastMessage: String = ""

    // MARK: - 检查更新（对标 about 页 check update）

    public enum UpdateState: Equatable {
        case idle
        case checking
        case latest
        case outdated(version: String, url: String)
        case failed(String)
    }

    public var updateState: UpdateState = .idle

    public func checkForUpdates() async {
        switch updateState {
        case .idle, .failed:
            break
        default:
            return
        }
        updateState = .checking
        do {
            let response = try await HTTPClient.shared.get(
                "https://api.github.com/repos/\(AppVersion.githubOwner)/\(AppVersion.githubRepo)/releases/latest",
                headers: ["Accept": "application/vnd.github+json"]
            )
            try response.raiseForStatus()
            guard let payload = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
                updateState = .failed("响应解析失败")
                return
            }
            let tagName = JSONCoercion.asTrimmedString(payload["tag_name"])
            let htmlUrl = JSONCoercion.asTrimmedString(payload["html_url"])
            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            if version.isEmpty {
                updateState = .failed("尚未发布任何版本")
                return
            }
            if AppVersion.compareSemVer(AppVersion.version, version) >= 0 {
                updateState = .latest
            } else {
                updateState = .outdated(version: version,
                                         url: htmlUrl.isEmpty ? "https://github.com/\(AppVersion.githubOwner)/\(AppVersion.githubRepo)/releases/latest" : htmlUrl)
            }
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }

    public func openReleasePage(_ url: String) {
        if let target = URL(string: url) {
            NSWorkspace.shared.open(target)
        }
    }

    /// 剪贴板中可用的问卷链接（无则 nil）。
    public var clipboardSurveyUrl: String? {
        guard let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              text.lowercased().hasPrefix("http"),
              ProviderType.isSupportedSurveyUrl(text) else { return nil }
        return text
    }

    /// 随机 IP 地区选择：当前选中的市码（nil/省码 = 全省）
    public var selectedCityCode: String?

    /// 填空题随机整数范围编辑暂存
    public var textIntMin: Int?
    public var textIntMax: Int?

    // MARK: - 随机IP额度

    public var quotaRemaining: Double = 0
    public var quotaTotal: Double = 0
    public var quotaKnown: Bool = false
    public var quotaLoading: Bool = false
    public var redeemCardCode: String = ""

    // MARK: - 引擎

    private var engine: RunEngine?
    private var engineTask: Task<Void, Never>?

    public init() {
        loadSavedConfigIfAvailable()
        refreshQuotaFromStore()
    }

    // MARK: - 解析

    public func parseSurvey() async {
        let url = surveyUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            parseError = "请先输入问卷链接"
            parsePhase = .failed
            return
        }
        guard ProviderType.isSupportedSurveyUrl(url) else {
            parseError = "仅支持问卷星 / 腾讯问卷 / 见数平台链接（当前 v0.1 仅实现问卷星提交链路）"
            parsePhase = .failed
            return
        }
        parsePhase = .parsing
        parseError = ""
        do {
            let provider = ProviderType.detectProvider(url)
            guard provider == .wjx else {
                parseError = "该平台链路将在后续版本支持，v0.1 暂只支持问卷星"
                parsePhase = .failed
                return
            }
            let result = try await WjxProvider.parseSurvey(url: url)
            surveyProvider = provider
            surveyTitle = result.title
            runtimeConfig.surveyProvider = provider
            runtimeConfig.surveyTitle = result.title
            runtimeConfig.questionsInfo = result.questions
            runtimeConfig.questionEntries = DefaultQuestionEntries.build(from: result.questions)
            let (sanitized, stats) = sanitizeAnswerRules(runtimeConfig.answerRules, questionsInfo: result.questions)
            runtimeConfig.answerRules = sanitized
            if stats["unsupported"] ?? 0 > 0 {
                appendLog("已剔除 \(stats["unsupported"] ?? 0) 条不适用的条件规则")
            }
            parsePhase = .ready
            selectedQuestionIndex = 0
            appendLog("解析成功：\(result.title)（\(result.questions.count) 题）")
            goToStep(.answers)
        } catch {
            parseError = error.localizedDescription
            parsePhase = .failed
            appendLog("解析失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 运行前检查（对标 ConfigPreflight 的门禁思路）

    public struct PreflightReport {
        public var errors: [String] = []
        public var warnings: [String] = []
        public var summary: [String] = []
    }

    public var preflight: PreflightReport {
        var report = PreflightReport()
        let questions = runtimeConfig.questionsInfo
        let entries = runtimeConfig.questionEntries

        if parsePhase != .ready {
            report.errors.append("问卷尚未解析，请回到第 1 步完成解析")
        }
        if questions.isEmpty {
            report.errors.append("题目清单为空")
        }
        if entries.isEmpty {
            report.errors.append("没有可用的作答配置")
        }

        let unsupported = questions.filter { $0.unsupported }
        if !unsupported.isEmpty {
            report.errors.append("第 \(unsupported.map { String($0.num) }.joined(separator: "、")) 题暂不支持：\(unsupported.first?.unsupportedReason ?? "")")
        }

        let logicReason = HttpLogicPlanner.fallbackReason(questions)
        if !logicReason.isEmpty {
            report.errors.append(logicReason + "，纯 HTTP 提交可能失败")
        }

        let unconfigured = questions.filter { question in
            !entries.contains { $0.questionNum == question.num }
        }
        if !unconfigured.isEmpty {
            report.errors.append("第 \(unconfigured.map { String($0.num) }.joined(separator: "、")) 题缺少作答配置")
        }

        report.summary.append("问卷：\(surveyTitle.isEmpty ? "—" : surveyTitle)（\(questions.count) 题，\(providerLabel)）")
        report.summary.append("目标：\(runtimeConfig.target) 份，并发 \(runtimeConfig.threads)，间隔 \(runtimeConfig.submitInterval.0)~\(runtimeConfig.submitInterval.1) 秒")
        report.summary.append("作答时长：\(runtimeConfig.answerDuration.0)~\(runtimeConfig.answerDuration.1) 秒（影响问卷后台记录的耗时）")
        report.summary.append(runtimeConfig.randomIpEnabled
            ? "随机 IP：启用（来源 \(runtimeConfig.proxySource)\(runtimeConfig.proxySource == proxySourceCustom ? "" : "，剩余额度 \(quotaRemaining)"))）"
            : "随机 IP：未启用（本机直连提交）")
        report.summary.append(runtimeConfig.randomUaEnabled
            ? "随机 UA：启用（微信 \(runtimeConfig.randomUaRatios["wechat"] ?? 0)% / 手机 \(runtimeConfig.randomUaRatios["mobile"] ?? 0)% / 电脑 \(runtimeConfig.randomUaRatios["pc"] ?? 0)%）"
            : "随机 UA：未启用（默认电脑网页端 UA）")

        if runtimeConfig.randomIpEnabled && quotaKnown && quotaRemaining < Double(runtimeConfig.target) {
            report.warnings.append("随机 IP 剩余额度 \(quotaRemaining) 低于目标份数 \(runtimeConfig.target)，中途可能因额度不足停止")
        }
        if !runtimeConfig.randomIpEnabled && runtimeConfig.target > 3 {
            report.warnings.append("直连提交较多份数容易触发问卷星智能验证，建议启用随机 IP")
        }
        if runtimeConfig.answerDuration.0 < 30 {
            report.warnings.append("作答时长过短（<30 秒）容易被判定为无效答卷")
        }
        report.warnings.append("AI 填空尚未接入：填空题将使用固定/随机文本")
        return report
    }

    public var providerLabel: String {
        switch surveyProvider {
        case .wjx: return "问卷星"
        case .qq: return "腾讯问卷"
        case .credamo: return "见数"
        }
    }

    // MARK: - 运行控制

    public var canStart: Bool {
        parsePhase == .ready && !isRunning && !runtimeConfig.questionEntries.isEmpty
    }

    public func startRun() async {
        guard canStart else { return }
        isRunning = true
        logs.removeAll()
        goToStep(.run)

        let snapshot = ConfigCodec.buildRuntimeConfigSnapshot(runtimeConfig)
        let execution = ExecutionConfigBuilder.build(from: snapshot)

        var pool: ProxyPool? = nil
        if execution.randomProxyIpEnabled {
            switch execution.proxySource {
            case proxySourceCustom:
                pool = ProxyPool(provider: CustomProxyProvider(apiUrl: execution.customProxyApi))
            default:
                pool = ProxyPool(provider: OfficialProxyProvider())
            }
            await pool?.setAreaCode(execution.proxyAreaCode)
        }

        beginSleepAssertion()

        let engine = RunEngine()
        self.engine = engine
        engineTask = Task { [weak self] in
            guard let self else { return }
            for await event in engine.progressStream {
                await self.handleEngineEvent(event)
            }
        }
        appendLog(runtimeConfig.randomIpEnabled ? "随机IP已启用（来源：\(runtimeConfig.proxySource)）" : "本次直连提交")
        engine.start(config: execution, proxyPool: pool)
    }

    public func stopRun() {
        engine?.requestStop()
    }

    public func pauseRun() {
        engine?.requestPause()
    }

    public func resumeRun() {
        engine?.resume()
    }

    @MainActor
    private func handleEngineEvent(_ event: RunEngineEvent) {
        switch event {
        case .progress(let progress):
            self.progress = progress
        case .log(let line):
            appendLog(line)
        case .finished(let progress):
            self.progress = progress
            self.isRunning = false
            endSleepAssertion()
            archiveLogs(summary: progress)
            if progress.phase == .finished {
                showToast("任务完成：成功 \(progress.successCount) 份")
                postSystemNotification(title: "任务完成",
                                       body: "成功 \(progress.successCount) 份，失败 \(progress.failCount) 份")
            } else if progress.phase == .failed {
                showToast("任务停止：\(progress.stopReason)")
                postSystemNotification(title: "任务停止", body: progress.stopReason)
            } else {
                showToast("任务已停止")
                postSystemNotification(title: "任务已停止",
                                       body: "成功 \(progress.successCount) 份，失败 \(progress.failCount) 份")
            }
            refreshQuotaFromStore()
        }
    }

    public func appendLog(_ message: String) {
        logs.append(message)
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }

    public func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if toastMessage == message { toastMessage = "" }
        }
    }

    // MARK: - 随机IP

    public func activateTrial() async {
        quotaLoading = true
        defer { quotaLoading = false }
        do {
            _ = try await BackendClient.shared.activateTrial()
            await syncQuotaFromServer(silent: true)
            showToast("随机IP试用领取成功")
        } catch {
            showToast("试用领取失败：\(error.localizedDescription)")
        }
    }

    public func syncQuotaFromServer(silent: Bool = false) async {
        quotaLoading = true
        defer { quotaLoading = false }
        guard BackendClient.shared.store.hasAuthenticatedSession else { return }
        do {
            _ = try await BackendClient.shared.syncQuotaFromServer()
            refreshQuotaFromStore()
        } catch {
            if !silent {
                showToast("额度同步失败：\(error.localizedDescription)")
            }
        }
    }

    public func refreshQuotaFromStore() {
        let snapshot = RandomIPSessionStore.shared.quotaSnapshot()
        quotaRemaining = snapshot.remaining
        quotaTotal = snapshot.total
        quotaKnown = snapshot.known
    }

    public func redeemCard() async {
        let code = redeemCardCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            showToast("请输入卡密")
            return
        }
        quotaLoading = true
        defer { quotaLoading = false }
        do {
            let result = try await BackendClient.shared.redeemCard(cardCode: code)
            if result.redeemed {
                showToast("兑换成功，剩余额度 \(result.remaining)")
                redeemCardCode = ""
                refreshQuotaFromStore()
            } else {
                showToast("兑换失败：\(result.detail.isEmpty ? "卡密无效" : result.detail)")
            }
        } catch {
            showToast("兑换失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 防休眠（对标 system/power_management.py）

    private var sleepAssertion: IOPMAssertionID = 0
    private var sleepAssertionActive = false

    private func beginSleepAssertion() {
        guard !sleepAssertionActive else { return }
        var assertionId: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "SurveyController 提交任务运行中" as CFString,
            &assertionId
        )
        if result == kIOReturnSuccess {
            sleepAssertion = assertionId
            sleepAssertionActive = true
            appendLog("已阻止系统休眠（任务运行期间）")
        }
    }

    private func endSleepAssertion() {
        guard sleepAssertionActive else { return }
        IOPMAssertionRelease(sleepAssertion)
        sleepAssertionActive = false
    }

    // MARK: - 系统通知（对标 task_result_system_notification）

    private func postSystemNotification(title: String, body: String) {
        guard shouldNotifyTaskResult else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "task-result-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    /// 通知开关（设置页可改）
    public var shouldNotifyTaskResult: Bool {
        get { UserDefaults.standard.object(forKey: "surveycontroller.notify-task-result") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "surveycontroller.notify-task-result") }
    }

    // MARK: - 日志落盘（对标 RunLogArchiver，按次存档、保留最近 10 份）

    static var logsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("SurveyController/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func archiveLogs(summary: RunProgress) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "run-\(formatter.string(from: Date())).log"
        let content = """
        # SurveyController 运行日志
        # 结果：\(summary.phase.rawValue) 成功 \(summary.successCount) 失败 \(summary.failCount)
        # \(summary.stopReason.isEmpty ? "" : "停止原因：" + summary.stopReason)
        \(logs.joined(separator: "\n"))
        """
        let url = Self.logsDirectory.appendingPathComponent(name)
        try? content.data(using: .utf8)?.write(to: url)
        appendLog("日志已存档：\(name)")
        trimOldLogs(keeping: 10)
    }

    private func trimOldLogs(keeping count: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: Self.logsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let logs = files.filter { $0.pathExtension == "log" }
            .compactMap { url -> (URL, Date)? in
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                    return nil
                }
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }
        for (url, _) in logs.dropFirst(count) {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - 配置持久化（对标 io/config/store.py）

    static var configDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("SurveyController/Configs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static var lastConfigPath: URL? {
        get { UserDefaults.standard.url(forKey: "surveycontroller.last-config") }
        set { UserDefaults.standard.set(newValue, forKey: "surveycontroller.last-config") }
    }

    func loadSavedConfigIfAvailable() {
        guard let path = Self.lastConfigPath,
              let data = try? Data(contentsOf: path),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }
        do {
            let config = try ConfigCodec.deserializeRuntimeConfig(payload)
            runtimeConfig = config
            surveyUrl = config.url
            surveyTitle = config.surveyTitle
            surveyProvider = config.surveyProvider
            parsePhase = config.questionsInfo.isEmpty ? .idle : .ready
            appendLog("已载入上次配置：\(path.lastPathComponent)")
        } catch {
            appendLog("上次配置载入失败：\(error.localizedDescription)")
        }
    }

    public func exportConfig(to url: URL) {
        do {
            let payload = ConfigCodec.serializeRuntimeConfig(runtimeConfig)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            Self.lastConfigPath = url
            appendLog("配置已保存：\(url.lastPathComponent)")
        } catch {
            showToast("保存失败：\(error.localizedDescription)")
        }
    }

    public func importConfig(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            guard let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw ConfigCodecError(configCorruptedMessage)
            }
            let config = try ConfigCodec.deserializeRuntimeConfig(payload)
            runtimeConfig = config
            surveyUrl = config.url
            surveyTitle = config.surveyTitle
            surveyProvider = config.surveyProvider
            parsePhase = config.questionsInfo.isEmpty ? .idle : .ready
            Self.lastConfigPath = url
            appendLog("配置已导入：\(url.lastPathComponent)")
        } catch {
            showToast("导入失败：\(error.localizedDescription)")
        }
    }
}
