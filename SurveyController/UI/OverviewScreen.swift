// 对标 software/ui/pages/workbench/dashboard/（概览页）
// 问卷输入、自动解析、题目清单、运行控制与进度。

import SwiftUI

struct OverviewScreen: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                surveyEntryCard
                quickSettingsCard
                if model.parsePhase == .ready { questionListCard }
                runStatusCard
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - 问卷输入

    private var surveyEntryCard: some View {
        CardView(title: "问卷") {
            HStack(spacing: 10) {
                TextField("粘贴问卷星链接（如 https://www.wjx.cn/vm/xxxx.aspx）", text: $model.surveyUrl)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isRunning)
                Button {
                    Task { await model.parseSurvey() }
                } label: {
                    if model.parsePhase == .parsing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("自动配置问卷")
                    }
                }
                .controlSize(.large)
                .disabled(model.parsePhase == .parsing || model.isRunning || model.surveyUrl.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if model.parsePhase == .failed {
                Label(model.parseError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            if model.parsePhase == .ready {
                Label("\(providerName) · \(model.surveyTitle) · 共 \(model.runtimeConfig.questionsInfo.count) 题",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }

            HStack {
                Button("导入配置…") { importConfig() }
                Button("导出配置…") { exportConfig() }
                Spacer()
            }
            .controlSize(.small)
        }
    }

    private var providerName: String {
        switch model.surveyProvider {
        case .wjx: return "问卷星"
        case .qq: return "腾讯问卷"
        case .credamo: return "见数"
        }
    }

    // MARK: - 快捷设置

    private var quickSettingsCard: some View {
        CardView(title: "快捷设置") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                GridRow {
                    Text("目标份数")
                    Stepper(value: $model.runtimeConfig.target, in: 1...99999) {
                        Text("\(model.runtimeConfig.target) 份")
                            .monospacedDigit()
                    }
                    .frame(width: 200)
                    Text("并发数")
                    Stepper(value: $model.runtimeConfig.threads, in: 1...RunEngine.maxThreads) {
                        Text("\(model.runtimeConfig.threads) 线程")
                            .monospacedDigit()
                    }
                    .frame(width: 200)
                }
                GridRow {
                    Text("随机 IP")
                    Toggle("", isOn: $model.runtimeConfig.randomIpEnabled)
                        .labelsHidden()
                        .disabled(model.isRunning)
                    Text("随机 UA")
                    Toggle("", isOn: $model.runtimeConfig.randomUaEnabled)
                        .labelsHidden()
                        .disabled(model.isRunning)
                }
            }
            Text("完整参数（提交间隔、作答时长、代理地区、UA 比例等）见「运行参数」页")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 题目清单

    private var questionListCard: some View {
        CardView(title: "题目清单（\("默认均匀分布，可在配置文件中自定义权重")）") {
            Table(model.runtimeConfig.questionsInfo) {
                TableColumn("序号") { question in
                    Text("\(question.displayNum ?? question.num)").monospacedDigit()
                }
                .width(40)
                TableColumn("类型") { question in
                    Text(DefaultQuestionEntries.entryType(for: question))
                }
                .width(70)
                TableColumn("题目标题") { question in
                    Text(question.title)
                }
                TableColumn("选项数") { question in
                    Text(question.options > 0 ? "\(question.options)" : "—").monospacedDigit()
                }
                .width(50)
                TableColumn("必答") { question in
                    Image(systemName: question.required ? "asterisk" : "")
                        .foregroundStyle(.red)
                }
                .width(40)
            }
            .frame(minHeight: 180, maxHeight: 320)
        }
    }

    // MARK: - 运行状态

    private var runStatusCard: some View {
        CardView(title: "执行") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    ProgressView(value: Double(model.progress.successCount), total: Double(max(model.progress.target, 1)))
                        .frame(maxWidth: .infinity)
                    Text("\(model.progress.successCount)/\(model.progress.target)")
                        .monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                }

                HStack(spacing: 12) {
                    Label("成功 \(model.progress.successCount)", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                    Label("失败 \(model.progress.failCount)", systemImage: "xmark.circle")
                        .foregroundStyle(model.progress.failCount > 0 ? .red : .secondary)
                    Spacer()
                    if model.isRunning {
                        Button("停止") { model.stopRun() }
                            .controlSize(.large)
                    } else {
                        Button {
                            Task { await model.startRun() }
                        } label: {
                            Text("开始执行")
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canStart)
                    }
                }

                if !model.progress.slots.isEmpty && model.isRunning {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
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
                }

                if !model.canStart && !model.isRunning && model.parsePhase != .ready {
                    Text("提示：先输入问卷链接并点击「自动配置问卷」")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 配置导入导出

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = model.surveyTitle.isEmpty ? "wjx_config.json" : "\(model.surveyTitle).json"
        panel.directoryURL = AppModel.configDirectory
        if panel.runModal() == .OK, let url = panel.url {
            model.exportConfig(to: url)
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.directoryURL = AppModel.configDirectory
        if panel.runModal() == .OK, let url = panel.url {
            model.importConfig(from: url)
        }
    }
}

// MARK: - 通用卡片容器

struct CardView<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}
