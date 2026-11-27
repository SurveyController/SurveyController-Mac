// 对标官方 5.0 向导式主流程：问卷 → 答案 → 任务 → 网络 → 检查 → 运行。

import SwiftUI
import UniformTypeIdentifiers

struct WizardView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                if model.wizardStep != .survey {
                    StudioHeading(title: model.wizardStep.workspaceTitle, subtitle: model.surveyTitle.isEmpty ? nil : model.surveyTitle)
                }
                WizardStepBar(current: model.wizardStep, maxReached: model.maxReachedStep,
                              running: model.isRunning, onSelect: model.goToStep)
            }
            .padding(.horizontal, 26)
            .padding(.top, 19)
            .padding(.bottom, 12)

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.wizardStep != .survey {
                Rectangle().fill(StudioStyle.border).frame(height: 1)
                navBar
                    .background(StudioStyle.toolbar)
            }
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
            if model.wizardStep != .survey {
                Button {
                    model.previousStep()
                } label: {
                    Label("上一步", systemImage: "chevron.left")
                }
                .disabled(model.isRunning)
            }
            Spacer()
            if model.wizardStep == .check {
                let passed = model.preflight.errors.isEmpty
                Label(passed ? "配置检查通过" : "有待修复的配置",
                      systemImage: passed ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(passed ? StudioStyle.success : StudioStyle.danger)
            }
            Spacer()
            if model.wizardStep == .run {
                if model.isRunning {
                    if model.progress.phase == .paused {
                        Button {
                            model.resumeRun()
                        } label: {
                            Label("继续", systemImage: "play.fill")
                        }
                        .controlSize(.large)
                    } else {
                        Button {
                            model.pauseRun()
                        } label: {
                            Label("暂停", systemImage: "pause.fill")
                        }
                        .controlSize(.large)
                    }
                    Button("停止任务", role: .destructive) { model.stopRun() }
                        .controlSize(.large)
                        .tint(StudioStyle.danger)
                } else {
                    Button {
                        Task { await model.startRun() }
                    } label: {
                        Label("开始执行", systemImage: "play.fill")
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(StudioStyle.primaryButton)
                    .disabled(!model.canStart || !model.preflight.errors.isEmpty)
                }
            } else if model.wizardStep != .survey {
                Button {
                    model.nextStep()
                } label: {
                    Label(model.wizardStep == .check ? "进入运行" : "下一步", systemImage: "chevron.right")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(StudioStyle.primaryButton)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

}

private extension AppModel.WizardStep {
    var workspaceTitle: String {
        switch self {
        case .survey: "问卷工作台"
        case .answers: "题目编辑器"
        case .task: "运行参数"
        case .network: "连接设置"
        case .check: "配置检查"
        case .run: "运行控制台"
        }
    }
}

// MARK: - 第 1 步：问卷

struct SurveyStepView: View {
    @Bindable var model: AppModel
    @FocusState private var linkFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                hero
                if model.parsePhase == .failed {
                    Label(model.parseError, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(StudioStyle.danger)
                        .padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .studioPanel(radius: 13)
                }
                if model.parsePhase == .ready {
                    currentSurvey
                }
                HStack(spacing: 13) {
                    sourceButton("从二维码图片导入", detail: "读取图片里的问卷链接", icon: "qrcode", action: importQRImage)
                    sourceButton("导入配置", detail: "恢复已保存的 JSON 配置", icon: "tray.and.arrow.down", action: importConfig)
                }
                .disabled(model.isRunning)
            }
            .padding(.horizontal, 26)
            .padding(.top, 8)
            .padding(.bottom, 26)
            .frame(maxWidth: 1040)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("问卷工作台")
                        .font(.system(size: 36, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("输入问卷链接，解析题目后即可编辑和离线试跑。")
                        .font(.subheadline)
                        .foregroundStyle(StudioStyle.mutedOnPanel)
                }
                Spacer()
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 31, weight: .medium))
                    .foregroundStyle(StudioStyle.accent)
                    .frame(width: 59, height: 59)
                    .background(StudioStyle.accentFill, in: RoundedRectangle(cornerRadius: 19))
                    .accessibilityHidden(true)
            }
            HStack(spacing: 9) {
                HStack(spacing: 10) {
                    Image(systemName: "link").foregroundStyle(StudioStyle.muted)
                    TextField("粘贴问卷链接", text: $model.surveyUrl)
                        .textFieldStyle(.plain)
                        .focused($linkFocused)
                        .onSubmit(openSurvey)
                        .foregroundStyle(StudioStyle.ink)
                        .disabled(model.isRunning)
                    if let link = model.clipboardSurveyUrl, link != model.surveyUrl {
                        Button {
                            model.surveyUrl = link
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(StudioStyle.accent)
                        .help("粘贴剪贴板中的问卷链接")
                        .accessibilityLabel("粘贴问卷链接")
                    }
                }
                .padding(.horizontal, 13)
                .frame(height: 43)
                .studioField(focused: linkFocused, radius: 12)
                Button(action: openSurvey) {
                    HStack(spacing: 8) {
                        if model.parsePhase == .parsing {
                            ProgressView().controlSize(.small)
                        }
                        Text(model.parsePhase == .parsing ? "正在解析" : "解析问卷")
                        if model.parsePhase != .parsing { Image(systemName: "arrow.right") }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(canParse ? StudioStyle.onPrimaryButton : StudioStyle.muted)
                    .padding(.horizontal, 13)
                    .frame(height: 43)
                    .background(canParse ? StudioStyle.primaryButton : StudioStyle.raised, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!canParse)
            }
            Label("问卷星 · 腾讯问卷 · Credamo 见数", systemImage: "link")
                .font(.caption.weight(.medium))
                .foregroundStyle(StudioStyle.mutedOnPanel)
        }
        .foregroundStyle(StudioStyle.ink)
        .padding(27)
        .studioPanel(radius: 21)
    }

    private var canParse: Bool {
        !model.isRunning && model.parsePhase != .parsing
            && !model.surveyUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentSurvey: some View {
        HStack(spacing: 13) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(StudioStyle.success)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.surveyTitle.isEmpty ? "已解析问卷" : model.surveyTitle)
                    .font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("\(model.runtimeConfig.questionsInfo.count) 题 · \(model.providerLabel)")
                    .font(.caption).foregroundStyle(StudioStyle.mutedOnPanel)
            }
            Spacer()
            if let url = URL(string: model.surveyUrl), url.scheme != nil {
                Link("查看问卷", destination: url)
            }
            Button("继续编辑") { model.goToStep(.answers) }
                .buttonStyle(.borderedProminent)
                .tint(StudioStyle.primaryButton)
        }
        .padding(16)
        .studioPanel()
    }

    private func sourceButton(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(StudioStyle.accent)
                    .frame(width: 42, height: 42)
                    .background(StudioStyle.accentFill, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(StudioStyle.mutedOnPanel)
                }
                Spacer(minLength: 3)
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(StudioStyle.accent)
            }
            .foregroundStyle(StudioStyle.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .studioPanel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openSurvey() {
        guard canParse else { return }
        Task { await model.parseSurvey() }
    }

    private func importQRImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            model.surveyUrl = try SurveyQRDecoder.surveyURL(from: url)
            Task { await model.parseSurvey() }
        } catch {
            model.showToast(error.localizedDescription)
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

                if model.surveyProvider == .wjx {
                    reverseFillCard
                }
                if model.surveyProvider == .credamo {
                    CardView(title: "作答日期") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("开始时间", text: $model.runtimeConfig.answerDatetimeWindow.0)
                            TextField("结束时间", text: $model.runtimeConfig.answerDatetimeWindow.1)
                            Text("YYYY-MM-DD HH:MM:SS，两个字段均可留空")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                CardView(title: "信度计划") {
                    Toggle("启用信度计划", isOn: $model.runtimeConfig.reliabilityModeEnabled)
                    HStack {
                        Text("目标 α")
                        TextField("目标 α", value: $model.runtimeConfig.psychoTargetAlpha, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                }

                CardView(title: "任务行为") {
                    Toggle("连续失败 5 份自动停止", isOn: $model.runtimeConfig.failStopEnabled)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 8)
            .frame(maxWidth: 940, alignment: .leading)
        }
    }
    private var reverseFillCard: some View {
        CardView(title: "Excel 反填") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("启用 Excel 反填", isOn: $model.runtimeConfig.reverseFillEnabled)
                Picker("导出格式", selection: $model.runtimeConfig.reverseFillFormat) {
                    Text("自动识别").tag(reverseFillFormatAuto)
                    Text("选项序号").tag(reverseFillFormatWjxSequence)
                    Text("分值").tag(reverseFillFormatWjxScore)
                    Text("选项文本").tag(reverseFillFormatWjxText)
                }
                Stepper("起始行：\(model.runtimeConfig.reverseFillStartRow)", value: $model.runtimeConfig.reverseFillStartRow, in: 1...9999)
                Stepper("反填并发：\(model.runtimeConfig.reverseFillThreads)", value: $model.runtimeConfig.reverseFillThreads, in: 1...RunEngine.maxThreads)
                Button("选择 Excel 文件…") { chooseReverseFillFile() }
                if let spec = model.reverseFillSpec {
                    Text("\(spec.samples.count) 个可用样本，共 \(spec.totalRows) 行")
                    if !spec.unmatched.isEmpty {
                        Text("未匹配的题号：\(spec.unmatched.map(String.init).joined(separator: "、"))")
                            .foregroundStyle(.secondary)
                    }
                    if !spec.invalidRows.isEmpty {
                        Text("无法使用的行：\(spec.invalidRows.prefix(20).map(String.init).joined(separator: "、"))")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(spec.samples.prefix(5), id: \.row) { sample in
                        Text("第 \(sample.row) 行 · \(sample.answers.count) 道题")
                            .font(.caption)
                    }
                }
            }
        }
       .onChange(of: model.runtimeConfig.reverseFillFormat) { Task { await model.reloadReverseFill() } }
        .onChange(of: model.runtimeConfig.reverseFillStartRow) { Task { await model.reloadReverseFill() } }
    }

    private func chooseReverseFillFile() {
        let panel = NSOpenPanel()
        if let type = UTType(filenameExtension: "xlsx") { panel.allowedContentTypes = [type] }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.loadReverseFill(from: url) }
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
                                    .foregroundStyle(model.quotaRemaining > 0 ? StudioStyle.success : StudioStyle.dangerOnPanel)
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

                        if model.runtimeConfig.proxySource != proxySourceCustom {
                            areaPicker
                        }

                        HStack(spacing: 10) {
                            Button("激活 / 领取") { Task { await model.activateTrial() } }
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
                            RatioSliders(
                                labels: ["微信端", "手机浏览器", "电脑网页端"],
                                values: RatioSliderMath.normalizeTo100([
                                    model.runtimeConfig.randomUaRatios["wechat"] ?? 0,
                                    model.runtimeConfig.randomUaRatios["mobile"] ?? 0,
                                    model.runtimeConfig.randomUaRatios["pc"] ?? 0,
                                ]),
                                onChange: { values in
                                    model.runtimeConfig.randomUaRatios["wechat"] = values.count > 0 ? values[0] : 0
                                    model.runtimeConfig.randomUaRatios["mobile"] = values.count > 1 ? values[1] : 0
                                    model.runtimeConfig.randomUaRatios["pc"] = values.count > 2 ? values[2] : 0
                                }
                            )
                            Text("微信 \(model.runtimeConfig.randomUaRatios["wechat"] ?? 0)% · 手机 \(model.runtimeConfig.randomUaRatios["mobile"] ?? 0)% · 电脑 \(model.runtimeConfig.randomUaRatios["pc"] ?? 0)%（总和恒 100%）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 8)
            .frame(maxWidth: 940, alignment: .leading)
        }
        .task { await model.syncQuotaFromServer(silent: true) }
    }

    @State private var selectedProvinceName: String = "不限"

    /// 地区选择：不限 / 省 / 全省任一市（对标 random_ip_card 的省市联动）。
    private var areaPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("省份", selection: $selectedProvinceName) {
                    Text("不限制").tag("不限")
                    ForEach(AreaService.provinces()) { province in
                        Text(province.name).tag(province.name)
                    }
                }
                .frame(width: 180)
                .disabled(model.isRunning)

                if let province = AreaService.findProvince(byName: selectedProvinceName) {
                    Picker("城市", selection: Binding(
                        get: { model.selectedCityCode },
                        set: { model.selectedCityCode = $0 }
                    )) {
                        Text("全省").tag(province.code)
                        ForEach(province.cities) { city in
                            Text(city.name).tag(city.code)
                        }
                    }
                    .frame(width: 180)
                    .disabled(model.isRunning)
                }
            }
            Text("当前：\(AreaService.describe(areaCode: effectiveAreaCode))\(effectiveAreaCode.isEmpty ? "" : "（\(effectiveAreaCode)）")；指定地区将自动使用优质 IP 池")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: selectedProvinceName) { _, newValue in
            // 切省时城市回落到全省
            if let province = AreaService.findProvince(byName: newValue) {
                model.selectedCityCode = province.code
                model.runtimeConfig.proxyAreaCode = province.code
            } else {
                model.selectedCityCode = nil
                model.runtimeConfig.proxyAreaCode = nil
            }
        }
        .onAppear {
            if let code = model.runtimeConfig.proxyAreaCode, !code.isEmpty {
                // 从配置恢复省份选择
                for province in AreaService.provinces() {
                    if province.code == code {
                        selectedProvinceName = province.name
                        model.selectedCityCode = code
                        return
                    }
                    if let city = province.cities.first(where: { $0.code == code }) {
                        selectedProvinceName = province.name
                        model.selectedCityCode = code
                        return
                    }
                }
            }
        }
    }

    private var effectiveAreaCode: String {
        if selectedProvinceName == "不限" { return "" }
        return AreaService.normalizeAreaCode(model.selectedCityCode ?? model.runtimeConfig.proxyAreaCode)
    }

}

// MARK: - 第 5 步：检查

struct CheckStepView: View {
    let model: AppModel
    @State private var showingRehearsal = false

    var body: some View {
        let report = model.preflight
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 13) {
                    Image(systemName: "checklist")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(StudioStyle.accent)
                        .frame(width: 48, height: 48)
                        .background(StudioStyle.accentFill, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("离线试跑").font(.headline)
                        Text("在本机预览最多 20 份答案和选项分布。")
                            .font(.subheadline).foregroundStyle(StudioStyle.mutedOnPanel)
                    }
                    Spacer()
                    Button {
                        showingRehearsal = true
                    } label: {
                        Label("离线试跑", systemImage: "play.circle")
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 9)
                            .padding(.horizontal, 12)
                            .foregroundStyle(model.canStart ? StudioStyle.onPrimaryButton : StudioStyle.muted)
                            .background(model.canStart ? StudioStyle.primaryButton : StudioStyle.raised, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canStart)
                }
                .foregroundStyle(StudioStyle.ink)
                .padding(17)
                .studioPanel(radius: 17)

                CardView(title: "配置摘要") {
                    VStack(alignment: .leading, spacing: 10) {
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
                                if let number = report.questionTargets[line] {
                                    Button {
                                        model.editQuestion(number)
                                    } label: {
                                        Label(line, systemImage: "arrow.right.circle")
                                    }
                                    .buttonStyle(.link)
                                } else {
                                    Label(line, systemImage: "xmark.octagon.fill")
                                        .foregroundStyle(StudioStyle.dangerOnPanel)
                                }
                            }
                        }
                    }
                }

                if !report.warnings.isEmpty {
                    CardView(title: "建议检查") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(report.warnings.enumerated()), id: \.offset) { _, line in
                                Label(line, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(StudioStyle.warning)
                            }
                        }
                    }
                }
                Button {
                    exportConfig()
                } label: {
                    Label("导出配置", systemImage: "square.and.arrow.up")
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 8)
            .frame(maxWidth: 940, alignment: .leading)
        }
        .sheet(isPresented: $showingRehearsal) {
            OfflineRehearsalView(model: model)
        }
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = model.surveyTitle.isEmpty ? "wjx_config.json" : "\(model.surveyTitle).json"
        panel.directoryURL = AppModel.configDirectory
        if panel.runModal() == .OK, let url = panel.url {
            model.exportConfig(to: url)
        }
    }
}

// MARK: - 第 6 步：运行

struct RunStepView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label(phaseTitle, systemImage: "waveform.path")
                        .font(.headline)
                    Spacer()
                    Text("\(model.progress.successCount) / \(model.progress.target)")
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText())
                }
                .foregroundStyle(StudioStyle.ink)
                GeometryReader { geometry in
                    let fraction = Double(model.progress.successCount) / Double(max(1, model.progress.target))
                    ZStack(alignment: .leading) {
                        Capsule().fill(StudioStyle.raised)
                        Capsule().fill(fraction >= 1 ? StudioStyle.success : StudioStyle.accent)
                            .frame(width: max(0, min(1, fraction)) * geometry.size.width)
                    }
                }
                .frame(height: 7)
                .accessibilityLabel("完成进度")
                .accessibilityValue("\(model.progress.successCount) 份，共 \(model.progress.target) 份")
            }
            .padding(17)
            .studioPanel(radius: 18)

            HStack(spacing: 9) {
                StudioMetric(title: "成功", value: String(model.progress.successCount), icon: "checkmark.circle",
                             color: StudioStyle.success)
                StudioMetric(title: "失败", value: String(model.progress.failCount), icon: "xmark.circle",
                             color: model.progress.failCount > 0 ? StudioStyle.dangerOnPanel : StudioStyle.ink)
                StudioMetric(title: "剩余", value: String(max(0, model.progress.target - model.progress.successCount)),
                             icon: "hourglass", color: StudioStyle.ink)
            }

            if !model.progress.failureReasons.isEmpty {
                HStack(spacing: 7) {
                    ForEach(model.progress.failureReasons.sorted(by: { $0.value > $1.value }).prefix(3), id: \.key) { reason, count in
                        Text("\(reason) × \(count)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(StudioStyle.danger.opacity(0.12), in: Capsule())
                            .foregroundStyle(StudioStyle.danger)
                    }
                }
            }

            if !model.progress.slots.isEmpty && model.isRunning {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(model.progress.slots) { slot in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(slot.status).font(.caption.weight(.semibold))
                                Text("\(slot.success) 成功 · \(slot.fail) 失败")
                                    .font(.caption2.monospacedDigit()).foregroundStyle(StudioStyle.mutedOnPanel)
                            }
                            .padding(8)
                            .studioPanel(radius: 9)
                        }
                    }
                }
            }

            LogsScreen(model: model, embedded: true)
                .frame(minHeight: 120)
        }
        .padding(.horizontal, 26)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    private var phaseTitle: String {
        if model.progress.phase == .paused { return "已暂停" }
        if model.isRunning { return "任务运行中" }
        if model.progress.target > 0 && model.progress.successCount >= model.progress.target { return "已达成目标" }
        return "任务进度"
    }
}
