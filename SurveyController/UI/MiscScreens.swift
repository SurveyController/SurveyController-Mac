// 对标 software/ui/pages/log_panel/ + settings/ + more/about
// 日志页、设置页、关于页。

import SwiftUI

struct LogsScreen: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("运行日志")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Spacer()
                Button("清空") { model.logs.removeAll() }
                    .padding(.trailing, 16)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.logs.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 1)
                                .id(index)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: model.logs.count) { _, newValue in
                    if newValue > 0 { proxy.scrollTo(newValue - 1, anchor: .bottom) }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

struct SettingsScreen: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CardView(title: "配置文件") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("配置目录：\(AppModel.configDirectory.path)")
                            .font(.caption)
                            .textSelection(.enabled)
                        Button("在 Finder 中打开") {
                            NSWorkspace.shared.open(AppModel.configDirectory)
                        }
                    }
                }
                CardView(title: "行为") {
                    Text("关闭窗口前会自动记住最近一次配置，下次启动自动载入。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct AboutScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CardView(title: "SurveyController for Mac") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("v\(AppVersion.version)（对齐官方 v\(AppVersion.alignedOfficialVersion)）")
                            .font(.title3.bold())
                        Text("一站式问卷自动化处理程序 macOS 端，适配问卷星、腾讯问卷、Credamo见数平台。")
                            .foregroundStyle(.secondary)
                        Divider()
                        Label {
                            Text("本项目仅供 HTTP 接口自动化学习与测试使用，请确保拥有目标测试问卷的授权，严禁污染他人问卷数据！")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(.orange)
                        .font(.callout)
                    }
                }

                CardView(title: "链接") {
                    VStack(alignment: .leading, spacing: 8) {
                        Link("GitHub 仓库", destination: URL(string: "https://github.com/SurveyController/SurveyController-Mac")!)
                        Link("官方教程文档", destination: URL(string: "https://surveydoc.hungrym0.com/")!)
                        Link("问题反馈", destination: URL(string: AppVersion.issueFeedbackUrl)!)
                        Link("Windows 版 / 安卓版", destination: URL(string: "https://github.com/SurveyController/SurveyController")!)
                    }
                }

                CardView(title: "开源许可") {
                    Text("GPL-3.0。基于 SurveyController（Windows 桌面端）移植，感谢原项目团队的开源贡献。")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
