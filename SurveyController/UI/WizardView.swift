// 对标官方 5.0 向导式主流程：问卷 → 答案 → 任务 → 网络 → 检查 → 运行。

import SwiftUI

struct WizardView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            WizardStepBar(
                steps: AppModel.WizardStep.allCases,
                current: Binding(
                    get: { model.wizardStep },
                    set: { model.goToStep($0) }
                ),
                maxReached: model.maxReachedStep
            ) { step in
                if !model.isRunning {
                    model.goToStep(step)
                }
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 24)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            navBar
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.wizardStep {
        case .survey: SurveyStepView(model: model)
        case .answers: AnswerConfigEditor(model: model)
        case .task: TaskStepView(model: model)
        case .network: NetworkStepView(model: model)
        case .check: CheckStepView(model: model)
        case .run: RunStepView(model: model)
        }
    }

    private var navBar: some View {
        HStack {
            Button("上一步") { model.previousStep() }
                .disabled(model.wizardStep == .survey || model.isRunning)
            Spacer()
            Text(stepHint)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.wizardStep == .run {
                if model.isRunning {
                    Button("停止任务") { model.stopRun() }
                        .controlSize(.large)
                } else {
                    Button {
                        Task { await model.startRun() }
                    } label: {
                        Label("开始执行", systemImage: "play.fill")
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canStart || !model.preflight.errors.isEmpty)
                }
            } else {
                Button(model.wizardStep == .check ? "进入运行" : "下一步") {
                    if model.wizardStep == .survey, model.parsePhase != .ready {
                        Task { await model.parseSurvey() }
                    } else {
                        model.nextStep()
                    }
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(model.wizardStep == .survey && (model.isRunning || model.surveyUrl.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var stepHint: String {
        switch model.wizardStep {
        case .survey: return "粘贴问卷链接或导入已有配置，解析成功自动进入下一步"
        case .answers: return "调整各题的答案分布，不改则使用默认均匀随机"
        case .task: return "建议先用 3~5 份验证配置，无误后再放量"
        case .network: return "直连提交多份容易触发智能验证，建议启用随机 IP"
        case .check: return model.preflight.errors.isEmpty ? "检查通过，可以开始运行" : "存在需要先解决的问题"
        case .run: return "运行中可随时停止；触发智能验证的 IP 会自动冷却更换"
        }
    }
}

// MARK: - 第 1 步：问卷

struct SurveyStepView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("导入已有配置…") { importConfig() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(.quinary)
                        .frame(width: 92, height: 92)
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 2)
                        .frame(width: 92, height: 92)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 38))
                        .foregroundStyle(.tint)
                }
                Text("添加要填写的问卷")
                    .font(.title2.bold())
                Text("粘贴问卷星链接，解析成功后自动进入答案配置")
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .foregroundStyle(.tertiary)
                    TextField("https://www.wjx.cn/vm/xxxx.aspx", text: $model.surveyUrl)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 430)
                        .disabled(model.isRunning)
                        .onSubmit { Task { await model.parseSurvey() } }
                    if let clipboardUrl = model.clipboardSurveyUrl, clipboardUrl != model.surveyUrl {
                        Button {
                            model.surveyUrl = clipboardUrl
                        } label: {
                            Label("粘贴", systemImage: "doc.on.clipboard")
                        }
                    }
                    if model.parsePhase == .parsing {
                        ProgressView().controlSize(.small)
                    }
                }

                if model.parsePhase == .failed {
                    Label(model.parseError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(maxWidth: 520)
                }
                if model.parsePhase == .ready {
                    HStack(spacing: 12) {
                        Label("已解析：\(model.surveyTitle)（\(model.runtimeConfig.questionsInfo.count) 题）",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if let url = URL(string: model.surveyUrl), url.scheme != nil {
                            Link(destination: url) {
                                Label("查看问卷", systemImage: "safari")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            Spacer()
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.directoryURL = AppModel.configDirectory
        if panel.runModal() == .OK, let url = panel.url {
            model.importConfig(from: url)
            if model.parsePhase == .ready {
                model.goToStep(.answers)
            }
        }
    }
}

// MARK: - 第 3 步：任务

struct TaskStepView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CardView(title: "任务规模") {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                        GridRow {
                            Text("目标份数")
                            Stepper(value: $model.runtimeConfig.target, in: 1...99999) {
                                Text("\(model.runtimeConfig.target) 份").monospacedDigit()
                            }
                            .frame(width: 220)
                            Text("并发数")
                            Stepper(value: $model.runtimeConfig.threads, in: 1...RunEngine.maxThreads) {
                                Text("\(model.runtimeConfig.threads) 线程").monospacedDigit()
                            }
                            .frame(width: 220)
                        }
                    }
                }

                CardView(title: "提交间隔") {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                        GridRow {
                            Text("间隔下限（秒）")
                            TextField("", value: $model.runtimeConfig.submitInterval.0, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder).frame(width: 110)
                            Text("间隔上限（秒）")
                            TextField("", value: $model.runtimeConfig.submitInterval.1, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder).frame(width: 110)
                        }
                    }
                    Text("同一并发的两次提交之间随机等待该区间内的时长")
                        .font(.caption).foregroundStyle(.secondary)
                }

                CardView(title: "作答时长") {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                        GridRow {
                            Text("时长下限（秒）")
                            TextField("", value: $model.runtimeConfig.answerDuration.0, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder).frame(width: 110)
                            Text("时长上限（秒）")
                            TextField("", value: $model.runtimeConfig.answerDuration.1, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder).frame(width: 110)
                        }
                    }
                    Text("高斯分布采样，写入问卷后台的作答耗时；纯 HTTP 提交不会真实等待")
                        .font(.caption).foregroundStyle(.secondary)
                }

                CardView(title: "任务行为") {
                    Toggle("连续失败 5 份自动停止", isOn: $model.runtimeConfig.failStopEnabled)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }
}

// MARK: - 第 4 步：网络

struct NetworkStepView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CardView(title: "随机 IP") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Toggle("启用随机 IP（地区代理）", isOn: $model.runtimeConfig.randomIpEnabled)
                                .disabled(model.isRunning)
                            Spacer()
                            if model.quotaLoading {
                                ProgressView().controlSize(.small)
                            } else if model.quotaKnown {
                                Text("剩余额度 \(model.quotaRemaining, format: .number)")
                                    .monospacedDigit()
                                    .foregroundStyle(model.quotaRemaining > 0 ? .green : .red)
                            }
                        }

                        Picker("代理来源", selection: $model.runtimeConfig.proxySource) {
                            Text("官方默认源").tag(proxySourceDefault)
                            Text("限时福利源").tag(proxySourceBenefit)
                            Text("自定义 API").tag(proxySourceCustom)
                        }
                        .pickerStyle(.radioGroup)
                        .disabled(model.isRunning)

                        if model.runtimeConfig.proxySource == proxySourceCustom {
                            TextField("自定义代理 API 地址（返回代理 IP 列表的接口）", text: $model.runtimeConfig.customProxyApi)
                                .textFieldStyle(.roundedBorder)
                                .disabled(model.isRunning)
                        }

                        HStack(spacing: 10) {
                            Button("领取试用") { Task { await model.activateTrial() } }
                                .disabled(model.quotaLoading || model.isRunning)
                            TextField("卡密", text: $model.redeemCardCode)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 200)
                            Button("兑换") { Task { await model.redeemCard() } }
                                .disabled(model.quotaLoading || model.isRunning)
                            Button("刷新额度") { Task { await model.syncQuotaFromServer() } }
                                .disabled(model.quotaLoading)
                        }
                    }
                }

                CardView(title: "随机 User-Agent") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("启用随机 UA", isOn: $model.runtimeConfig.randomUaEnabled)
                            .disabled(model.isRunning)
                        if model.runtimeConfig.randomUaEnabled {
                            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                                GridRow {
                                    uaRatio("微信端", "wechat")
                                    uaRatio("手机浏览器", "mobile")
                                    uaRatio("电脑网页端", "pc")
                                }
                            }
                            let total = model.runtimeConfig.randomUaRatios.values.reduce(0, +)
                            Text(total == 100
                                 ? "比例合计 100%"
                                 : "比例合计 \(total)%，运行时非 100% 将回落默认比例")
                                .font(.caption)
                                .foregroundStyle(total == 100 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .task { await model.syncQuotaFromServer(silent: true) }
    }

    private func uaRatio(_ title: String, _ key: String) -> some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(model.runtimeConfig.randomUaRatios[key] ?? 0) },
                    set: { model.runtimeConfig.randomUaRatios[key] = Int($0) }
                ),
                in: 0...100, step: 1
            )
            .disabled(model.isRunning)
            Text("\(model.runtimeConfig.randomUaRatios[key] ?? 0)%")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}

// MARK: - 第 5 步：检查

struct CheckStepView: View {
    let model: AppModel

    var body: some View {
        let report = model.preflight
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CardView(title: "配置摘要") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(report.summary.enumerated()), id: \.offset) { _, line in
                            Label(line, systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !report.errors.isEmpty {
                    CardView(title: "必须解决") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(report.errors.enumerated()), id: \.offset) { _, line in
                                Label(line, systemImage: "xmark.octagon.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                CardView(title: "提示") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(report.warnings.enumerated()), id: \.offset) { _, line in
                            Label(line, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }
}

// MARK: - 第 6 步：运行

struct RunStepView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ProgressView(value: Double(model.progress.successCount), total: Double(max(model.progress.target, 1)))
                    .frame(maxWidth: .infinity)
                Text("\(model.progress.successCount)/\(model.progress.target)")
                    .monospacedDigit()
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            HStack(spacing: 14) {
                Label("成功 \(model.progress.successCount)", systemImage: "checkmark.circle").foregroundStyle(.green)
                Label("失败 \(model.progress.failCount)", systemImage: "xmark.circle")
                    .foregroundStyle(model.progress.failCount > 0 ? .red : .secondary)
                ForEach(model.progress.failureReasons.sorted(by: { $0.value > $1.value }).prefix(3), id: \.key) { reason, count in
                    Text("\(reason)×\(count)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            if !model.progress.slots.isEmpty && model.isRunning {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                    ForEach(model.progress.slots) { slot in
                        VStack(spacing: 2) {
                            Text(slot.status).font(.caption)
                            Text("\(slot.success)✓ \(slot.fail)✗")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal, 20)
            }

            Divider().padding(.top, 10)
            LogsScreen(model: model)
        }
    }
}
