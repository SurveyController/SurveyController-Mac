// 对标 software/ui/pages/workbench/runtime_panel/（运行参数页）
// 时间控制、随机IP（来源/地区/额度/兑换）、随机UA、失败停止。

import SwiftUI

struct RuntimeScreen: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                timeControlCard
                randomIPCard
                randomUACard
                behaviorCard
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .task {
            await model.syncQuotaFromServer(silent: true)
        }
    }

    // MARK: - 时间控制

    private var timeControlCard: some View {
        CardView(title: "时间控制") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                GridRow {
                    Text("提交间隔下限（秒）")
                    TextField("", value: $model.runtimeConfig.submitInterval.0, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .disabled(model.isRunning)
                    Text("提交间隔上限（秒）")
                    TextField("", value: $model.runtimeConfig.submitInterval.1, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .disabled(model.isRunning)
                }
                GridRow {
                    Text("作答时长下限（秒）")
                    TextField("", value: $model.runtimeConfig.answerDuration.0, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .disabled(model.isRunning)
                    Text("作答时长上限（秒）")
                    TextField("", value: $model.runtimeConfig.answerDuration.1, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .disabled(model.isRunning)
                }
            }
            Text("作答时长影响问卷后台记录的答题耗时（问卷星 ktimes / 作答时长参数），纯 HTTP 提交不会真实等待")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 随机IP

    private var randomIPCard: some View {
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
                    Button("领取试用") {
                        Task { await model.activateTrial() }
                    }
                    .disabled(model.quotaLoading || model.isRunning)
                    TextField("卡密", text: $model.redeemCardCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                    Button("兑换") {
                        Task { await model.redeemCard() }
                    }
                    .disabled(model.quotaLoading || model.isRunning)
                    Button("刷新额度") {
                        Task { await model.syncQuotaFromServer() }
                    }
                    .disabled(model.quotaLoading)
                }

                Text("启用随机 IP 后，每份提交前自动获取代理；触发智能验证的 IP 会自动冷却更换")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 随机UA

    private var randomUACard: some View {
        CardView(title: "随机 User-Agent") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("启用随机 UA", isOn: $model.runtimeConfig.randomUaEnabled)
                    .disabled(model.isRunning)

                if model.runtimeConfig.randomUaEnabled {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        GridRow {
                            uaRatioSlider(title: "微信端", key: "wechat")
                            uaRatioSlider(title: "手机浏览器", key: "mobile")
                            uaRatioSlider(title: "电脑网页端", key: "pc")
                        }
                    }
                    let total = model.runtimeConfig.randomUaRatios.values.reduce(0, +)
                    Text(total == 100
                         ? "比例合计 100%（微信 \(model.runtimeConfig.randomUaRatios["wechat"] ?? 0) / 手机 \(model.runtimeConfig.randomUaRatios["mobile"] ?? 0) / 电脑 \(model.runtimeConfig.randomUaRatios["pc"] ?? 0)）"
                         : "比例合计 \(total)%，保存时非 100% 将回落默认比例")
                        .font(.caption)
                        .foregroundStyle(total == 100 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                }
            }
        }
    }

    private func uaRatioSlider(title: String, key: String) -> some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(model.runtimeConfig.randomUaRatios[key] ?? 0) },
                    set: { model.runtimeConfig.randomUaRatios[key] = Int($0) }
                ),
                in: 0...100,
                step: 1
            )
            .disabled(model.isRunning)
            Text("\(model.runtimeConfig.randomUaRatios[key] ?? 0)%")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: - 行为

    private var behaviorCard: some View {
        CardView(title: "任务行为") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("连续失败 5 份自动停止", isOn: $model.runtimeConfig.failStopEnabled)
                    .disabled(model.isRunning)
                Text("建议先用 3~5 份验证配置无误后再放量。协议细节（提交参数、签名）已通过 golden-value 单元测试对齐桌面端。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
