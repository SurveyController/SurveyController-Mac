// 对标 software/ui/pages/community.py + dialogs/contact.py（简化：文本反馈，无附件轮询）
// 社区页：QQ 群 / 联系开发者 / 参与贡献 / 开源许可。

import SwiftUI

struct CommunityScreen: View {
    private let columns = [GridItem(.adaptive(minimum: 420), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("社区")
                    .font(.system(size: 26, weight: .bold))

                LazyVGrid(columns: columns, spacing: 16) {
                    qqCard
                    contactCard
                    contributeCard
                    licenseCard
                }

                Text("欢迎加入社区，一起让这个项目变得更好")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(28)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - QQ 群

    private var qqCard: some View {
        CommunityCard(title: "QQ 群交流", icon: { SFIcon(systemImage: "bubble.left.and.bubble.right.fill") }, content: {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("扫码加入 QQ 交流群，实时获取最新版本、反馈问题、交流使用经验、订阅最新的服务情况")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("群号 346131215")
                        .font(.callout)
                        .monospacedDigit()
                    Spacer()
                    Button("拷贝群号") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("346131215", forType: .string)
                    }
                    .controlSize(.regular)
                }
                Spacer()
                if let qrImage = Self.qrImage {
                    Image(nsImage: qrImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 144, height: 144)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary)
                        .frame(width: 144, height: 144)
                        .overlay(Text("二维码").font(.caption).foregroundStyle(.secondary))
                }
            }
            Button("打开二维码") { Self.openQrImage() }
        })
    }

    static var qrImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "community_qr", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    static func openQrImage() {
        guard let url = Bundle.main.url(forResource: "community_qr", withExtension: "png") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 联系开发者

    private var contactCard: some View {
        CommunityCard(title: "联系开发者", icon: { FeedbackIcon(size: 22) }, content: {
            Text("在 GitHub 报告问题或提出建议")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: AppVersion.issueFeedbackUrl) {
                Link("打开问题反馈", destination: url)
            }
        })
    }

    // MARK: - 参与贡献

    private var contributeCard: some View {
        CommunityCard(title: "参与贡献", icon: { GitHubIcon(size: 22) }, content: {
            Text("我们接受开发、设计、测试、提供创新性想法、反馈报错等任何贡献形式\n相信我们能够一起把项目做得更好。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/SurveyController/SurveyController-Mac")!)
                } label: {
                    Label("Mac 版", systemImage: "desktopcomputer")
                }
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/SurveyController/SurveyController")!)
                } label: {
                    Label("Windows 版", systemImage: "macwindow.on.rectangle")
                }
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/shiaho777/SurveyController-Android")!)
                } label: {
                    Label("Android 版", systemImage: "candybarphone")
                }
            }
        })
    }

    // MARK: - 开源许可

    private var licenseCard: some View {
        CommunityCard(title: "开源许可", icon: { DocsIcon(size: 22) }, content: {
            Text("GPL-3.0")
                .font(.system(size: 17, weight: .semibold))
            Text("分发程序或修改版本时，必须按 GPL-3.0 要求提供相应源代码，确保接收者获得使用、研究、修改和再分发的自由")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("查看协议") {
                NSWorkspace.shared.open(URL(string: "https://github.com/SurveyController/SurveyController-Mac/blob/main/LICENSE")!)
            }
        })
    }
}

// MARK: - 卡片容器

struct CommunityCard<Icon: View, Content: View>: View {
    let title: String
    let icon: Icon
    let content: Content

    init(
        title: String,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                icon
                    .frame(width: 26, height: 26)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            content
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quinary))
    }
}

struct SFIcon: View {
    let systemImage: String
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18))
            .foregroundStyle(.tint)
    }
}
