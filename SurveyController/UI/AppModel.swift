// 对标 software/ui/controller/run_controller.py + run_state_store.py
// 中央视图模型：解析、配置、运行、日志、随机IP额度的唯一事实来源。

import Foundation
import Observation

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

    // MARK: - 运行状态

    public var isRunning: Bool = false
    public var progress: RunProgress = RunProgress()
    public var logs: [String] = []
    public var toastMessage: String = ""

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
            appendLog("解析成功：\(result.title)（\(result.questions.count) 题）")
        } catch {
            parseError = error.localizedDescription
            parsePhase = .failed
            appendLog("解析失败：\(error.localizedDescription)")
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
        }

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
            if progress.phase == .finished {
                showToast("任务完成：成功 \(progress.successCount) 份")
            } else if progress.phase == .failed {
                showToast("任务停止：\(progress.stopReason)")
            } else {
                showToast("任务已停止")
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
