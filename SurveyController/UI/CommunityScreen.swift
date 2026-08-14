// 对标 software/ui/pages/community.py + dialogs/contact.py（简化：文本反馈，无附件轮询）
// 社区页：QQ 群 / 联系开发者 / 参与贡献 / 开源许可。

import SwiftUI

struct CommunityScreen: View {
    @State private var showContactSheet = false

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
        .sheet(isPresented: $showContactSheet) {
            ContactSheet()
        }
    }

    // MARK: - QQ 群

    private var qqCard: some View {
        CommunityCard(title: "QQ 群交流", systemImage: "bubble.left.and.bubble.right.fill") {
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
        }
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
        CommunityCard(title: "联系开发者", systemImage: "paperplane.fill") {
            Text("遇到问题？有建议？不想加 QQ 群？\n可以直接在此处与我们沟通，我们会尽快回复。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("发送消息") { showContactSheet = true }
        }
    }

    // MARK: - 参与贡献

    private var contributeCard: some View {
        CommunityCard(title: "参与贡献", systemImage: "wrench.and.screwdriver") {
            Text("我们接受开发、设计、测试、提供创新性想法、反馈报错等任何贡献形式\n相信我们能够一起把项目做得更好。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Mac 仓库") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/SurveyController/SurveyController-Mac")!)
                }
                Button("官方主仓库") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/SurveyController/SurveyController")!)
                }
            }
        }
    }

    // MARK: - 开源许可

    private var licenseCard: some View {
        CommunityCard(title: "开源许可", systemImage: "checkmark.seal.fill") {
            Text("GPL-3.0")
                .font(.system(size: 17, weight: .semibold))
            Text("分发程序或修改版本时，必须按 GPL-3.0 要求提供相应源代码，确保接收者获得使用、研究、修改和再分发的自由")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("查看协议") {
                NSWorkspace.shared.open(URL(string: "https://github.com/SurveyController/SurveyController-Mac/blob/main/LICENSE")!)
            }
        }
    }
}

// MARK: - 卡片容器

struct CommunityCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: 22, height: 22)
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
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

// MARK: - 反馈表单（对标 ContactDialog 简化版）

struct ContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var messageType = "问题反馈"
    @State private var messageText = ""
    @State private var sending = false
    @State private var resultText = ""

    private let messageTypes = ["问题反馈", "功能建议", "其他"]
    private let contactApiUrl = "https://bot.hungrym0.com"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("联系开发者").font(.title3.bold())

            Picker("类型", selection: $messageType) {
                ForEach(messageTypes, id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            TextEditor(text: $messageText)
                .font(.body)
                .frame(minHeight: 140)
                .border(Color(nsColor: .separatorColor))

            if !resultText.isEmpty {
                Text(resultText)
                    .font(.callout)
                    .foregroundStyle(resultText.hasPrefix("发送失败") ? .red : .green)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button {
                    Task { await send() }
                } label: {
                    if sending {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("发送")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sending || messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    func send() async {
        sending = true
        defer { sending = false }

        let session = RandomIPSessionStore.shared.readSession()
        var fields: [String: String] = [
            "message": "【macOS v\(AppVersion.version)】\(messageText.trimmingCharacters(in: .whitespacesAndNewlines))",
            "messageType": messageType,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        if session.userId > 0 {
            fields["userId"] = String(session.userId)
        }
        do {
            let response = try await HTTPClient.shared.postMultipart(contactApiUrl, fields: fields, headers: [
                "Accept": "application/json",
            ])
            if response.isSuccess {
                resultText = "发送成功，感谢反馈！"
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                dismiss()
            } else {
                resultText = "发送失败：HTTP \(response.statusCode)"
            }
        } catch {
            resultText = "发送失败：\(error.localizedDescription)"
        }
    }
}
