import SwiftUI

struct LogsScreen: View {
    let model: AppModel
    var embedded = false

    @State private var autoScroll = true
    @State private var search = ""

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = model.logs.enumerated().filter { query.isEmpty || $0.element.localizedCaseInsensitiveContains(query) }

        VStack(alignment: .leading, spacing: 11) {
            if !embedded {
                StudioHeading(title: "运行日志", subtitle: "查看任务记录，搜索并复制所需内容。", icon: "text.alignleft")
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    if embedded { Text("运行日志").font(.headline) }
                    Text("\(lines.count) 行").font(.caption.monospacedDigit()).foregroundStyle(StudioStyle.muted)
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(StudioStyle.muted)
                        TextField("搜索日志", text: $search).textFieldStyle(.plain)
                    }
                    .padding(8)
                    .frame(maxWidth: 170)
                    .background(StudioStyle.canvas, in: RoundedRectangle(cornerRadius: 9))
                    Toggle("自动滚动", isOn: $autoScroll).controlSize(.small)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.logs.joined(separator: "\n"), forType: .string)
                        model.showToast("日志已复制到剪贴板")
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .disabled(model.logs.isEmpty)
                    Button("清空") { model.logs.removeAll() }.disabled(model.logs.isEmpty)
                }
                .controlSize(.small)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                Rectangle().fill(StudioStyle.border).frame(height: 1)

                if lines.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "暂无日志" : "没有匹配的日志",
                        systemImage: query.isEmpty ? "text.alignleft" : "magnifyingglass"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(lines, id: \.offset) { index, line in
                                    HStack(alignment: .center, spacing: 10) {
                                        Circle().fill(lineColor(line)).frame(width: 6, height: 6).accessibilityHidden(true)
                                        Text(line)
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 6)
                                    .background(index.isMultiple(of: 2) ? StudioStyle.canvas.opacity(0.6) : .clear)
                                    .id(index)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onChange(of: model.logs.count) {
                            if autoScroll, let last = lines.last?.offset {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .studioPanel(radius: 15)
        }
        .padding(embedded ? 0 : 26)
    }

    private func lineColor(_ line: String) -> Color {
        if line.contains("失败") || line.contains("错误") { return StudioStyle.danger }
        if line.contains("成功") { return StudioStyle.accent }
        if line.contains("警告") || line.contains("风控") { return StudioStyle.warning }
        return StudioStyle.muted
    }
}

struct SettingsScreen: View {
    @Bindable var model: AppModel
    @State private var archivedLogs: [URL] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                StudioHeading(title: "设置", subtitle: "管理通知、自定义 AI 和本机文件。", icon: "slider.horizontal.3")
                CardView(title: "通知") {
                    Toggle("任务完成后发送系统通知", isOn: Binding(
                        get: { model.shouldNotifyTaskResult },
                        set: { model.shouldNotifyTaskResult = $0 }
                    ))
                }

                CardView(title: "自定义 AI") {
                    Grid(alignment: .leading, horizontalSpacing: 15, verticalSpacing: 10) {
                        GridRow {
                            Text("服务地址")
                            TextField("API Base URL", text: $model.aiSettings.baseURL)
                        }
                        GridRow {
                            Text("API 密钥")
                            SecureField("API Key", text: $model.aiSettings.apiKey)
                        }
                        GridRow {
                            Text("模型")
                            TextField("模型名称", text: $model.aiSettings.model)
                        }
                        GridRow {
                            Text("接口协议")
                            Picker("接口协议", selection: $model.aiSettings.protocolName) {
                                Text("自动").tag("auto")
                                Text("Chat Completions").tag("chat_completions")
                                Text("Responses").tag("responses")
                            }
                            .labelsHidden()
                        }
                        GridRow {
                            Text("系统提示词")
                            TextField("可选", text: $model.aiSettings.systemPrompt)
                        }
                    }
                    HStack {
                        Text("密钥存入 macOS 钥匙串。").font(.caption).foregroundStyle(StudioStyle.muted)
                        Spacer()
                        Button("保存 AI 设置", action: model.saveAISettings).buttonStyle(.borderedProminent)
                    }
                }

                CardView(title: "配置文件") {
                    HStack {
                        Text(AppModel.configDirectory.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(StudioStyle.muted)
                            .textSelection(.enabled)
                        Spacer()
                        Button("在 Finder 中打开") { NSWorkspace.shared.open(AppModel.configDirectory) }
                    }
                }

                CardView(title: "运行日志存档") {
                    HStack {
                        Text("每次运行自动存档，保留最近 10 份")
                            .font(.caption).foregroundStyle(StudioStyle.muted)
                        Spacer()
                        Button("打开日志目录") { NSWorkspace.shared.open(AppModel.logsDirectory) }
                    }
                    ForEach(archivedLogs, id: \.self) { url in
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label(url.lastPathComponent, systemImage: "doc.text")
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: 930, alignment: .leading)
        }
        .onAppear { archivedLogs = Self.loadLogs() }
    }

    static func loadLogs() -> [URL] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: AppModel.logsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}
