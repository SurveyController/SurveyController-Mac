// 对标 software/ui/pages/more/about.py + donate —— 品牌图标化重设计。

import SwiftUI

struct AboutScreen: View {
    @State private var model = AppModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                disclaimer
                linksSection
                licenseSection
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .task {
            if case .idle = model.updateState {
                await model.checkForUpdates()
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(colors: [.accentColor.opacity(0.8), .accentColor],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: .accentColor.opacity(0.35), radius: 8, y: 3)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("SurveyController for Mac")
                        .font(.title2.bold())
                    versionBadge
                }
                Text("一站式问卷自动化处理程序 macOS 端 · 对齐官方 v\(AppVersion.alignedOfficialVersion)")
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button {
                        Task { await model.checkForUpdates() }
                    } label: {
                        switch model.updateState {
                        case .checking:
                            ProgressView().controlSize(.small)
                        case .latest:
                            Label("已是最新", systemImage: "checkmark.seal.fill")
                        case .outdated(let version, _):
                            Label("新版本 v\(version)", systemImage: "arrow.down.circle.fill")
                        case .failed:
                            Label("重试检查", systemImage: "arrow.clockwise")
                        case .idle:
                            Label("检查更新", systemImage: "sparkles")
                        }
                    }
                    .controlSize(.small)
                    .disabled(model.updateState == .checking)

                    if case .outdated(_, let url) = model.updateState {
                        Button("前往下载") { model.openReleasePage(url) }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            Spacer()
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }

    @ViewBuilder
    private var versionBadge: some View {
        let text: (String, Color)? = {
            switch model.updateState {
            case .latest: return ("最新", .green)
            case .outdated: return ("可更新", .orange)
            default: return ("v\(AppVersion.version)", .secondary)
            }
        }()
        if let (label, color) = text {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.14), in: Capsule())
                .foregroundStyle(color)
        }
    }

    // MARK: - 免责声明

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            Text("本项目仅供 HTTP 接口自动化学习与测试使用。请确保拥有目标测试问卷的授权，严禁污染他人问卷数据！")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 链接

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("链接").font(.headline)
            VStack(spacing: 8) {
                LinkRow(title: "GitHub 仓库", subtitle: "源码 · Issue · Release") {
                    GitHubIcon(size: 22)
                } action: {
                    NSWorkspace.shared.open(URL(string: "https://github.com/SurveyController/SurveyController-Mac")!)
                }
                LinkRow(title: "官方教程文档", subtitle: "surveydoc.hungrym0.com") {
                    DocsIcon(size: 22)
                } action: {
                    NSWorkspace.shared.open(URL(string: "https://surveydoc.hungrym0.com/")!)
                }
                LinkRow(title: "问题反馈", subtitle: "GitHub Issues 或应用内反馈表单") {
                    FeedbackIcon(size: 22)
                } action: {
                    NSWorkspace.shared.open(URL(string: AppVersion.issueFeedbackUrl)!)
                }
                LinkRow(title: "Windows 版", subtitle: "官方桌面端（原版）") {
                    WindowsIcon(size: 22)
                } action: {
                    NSWorkspace.shared.open(URL(string: "https://github.com/SurveyController/SurveyController")!)
                }
                LinkRow(title: "Android 版", subtitle: "shiaho777/SurveyController-Android") {
                    AndroidIcon(size: 22)
                } action: {
                    NSWorkspace.shared.open(URL(string: "https://github.com/shiaho777/SurveyController-Android")!)
                }
            }
        }
    }

    // MARK: - 许可

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("开源许可").font(.headline)
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GPL-3.0").font(.body.weight(.semibold))
                    Text("分发程序或修改版本时，必须按 GPL-3.0 要求提供相应源代码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("查看协议") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/SurveyController/SurveyController-Mac/blob/main/LICENSE")!)
                }
                .controlSize(.small)
            }
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        }
    }
}

#Preview {
    AboutScreen()
}
