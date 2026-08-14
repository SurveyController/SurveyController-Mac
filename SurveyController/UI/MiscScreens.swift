// 对标 software/ui/pages/log_panel/ + settings/ + more/about
// 日志页、设置页、关于页。

import SwiftUI

struct LogsScreen: View {
    let model: AppModel
    @State private var autoScroll = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("运行日志")
                    .font(.headline)
                Text("\(model.logs.count) 行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("自动滚动", isOn: $autoScroll)
                    .controlSize(.small)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.logs.joined(separator: "\n"), forType: .string)
                    model.showToast("日志已复制到剪贴板")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                Button("清空") { model.logs.removeAll() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.logs.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle()
                                    .fill(lineColor(line))
                                    .frame(width: 6, height: 6)
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 1)
                            .id(index)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: model.logs.count) { _, newValue in
                    if autoScroll && newValue > 0 { proxy.scrollTo(newValue - 1, anchor: .bottom) }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func lineColor(_ line: String) -> Color {
        if line.contains("失败") || line.contains("错误") { return .red }
        if line.contains("成功") { return .green }
        if line.contains("警告") || line.contains("风控") { return .orange }
        return .accentColor
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
