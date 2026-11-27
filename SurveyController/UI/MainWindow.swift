// 对标官方 5.0 主窗口：左侧 任务/日志/设置/更多，任务页为 6 步向导。

import SwiftUI

enum AppPage: String, Hashable, Identifiable, CaseIterable {
    case task = "工作台"
    case settings = "设置"
    case community = "社区"
    case logs = "日志"
    case about = "关于"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .task: return "square.grid.2x2"
        case .settings: return "gearshape"
        case .community: return "bubble.left.and.bubble.right"
        case .logs: return "doc.text"
        case .about: return "info.circle"
        }
    }
}

struct MainWindow: View {
    @State private var model = AppModel()
    @State private var selection: AppPage = .task
    @State private var hoveredPage: AppPage?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(StudioStyle.border).frame(width: 1)
            Group {
                switch selection {
                case .task: WizardView(model: model)
                case .settings: SettingsScreen(model: model)
                case .community: CommunityScreen()
                case .logs: LogsScreen(model: model)
                case .about: AboutScreen(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StudioStyle.canvas)
        }
        .foregroundStyle(StudioStyle.ink, StudioStyle.muted)
        .tint(StudioStyle.accent)
        .toolbarBackground(StudioStyle.toolbar, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .navigationTitle("SurveyController")
        .frame(minWidth: 970, minHeight: 650)
        .overlay(alignment: .bottom) {
            if !model.toastMessage.isEmpty {
                toastView
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                StudioMark()
                VStack(alignment: .leading, spacing: 2) {
                    Text("SurveyController").font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.92)
                        .foregroundStyle(StudioStyle.ink)
                    Text("macOS").font(.caption).foregroundStyle(StudioStyle.muted)
                }
            }
            .padding(.horizontal, 6)

            VStack(alignment: .leading, spacing: 5) {
                navigationItem(.task)
                navigationItem(.logs)
                navigationItem(.settings)
                navigationItem(.community)
                navigationItem(.about)
            }

            Spacer()

            if model.isRunning {
                Button {
                    selection = .task
                } label: {
                    Label(model.progress.phase == .paused ? "任务已暂停" : "任务运行中", systemImage: "waveform.path")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(StudioStyle.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(11)
                        .background(StudioStyle.accentFill, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
            Text("版本 \(AppVersion.version)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(StudioStyle.muted)
                .padding(.horizontal, 8)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 14)
        .frame(width: 206)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(StudioStyle.toolbar)
    }

    private func navigationItem(_ page: AppPage) -> some View {
        let selected = page == selection
        let hovered = page == hoveredPage
        return Button {
            selection = page
        } label: {
            HStack(spacing: 9) {
                Image(systemName: page.systemImage).frame(width: 21)
                Text(page.rawValue)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? StudioStyle.accent : hovered ? StudioStyle.ink : StudioStyle.muted)
            .padding(.horizontal, 10)
            .frame(height: 39)
            .background(selected ? StudioStyle.accentFill : hovered ? StudioStyle.hover : .clear, in: RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { active in
            if active {
                hoveredPage = page
            } else if hoveredPage == page {
                hoveredPage = nil
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var toastView: some View {
        HStack(spacing: 8) {
            Image(systemName: toastIcon)
                .foregroundStyle(toastColor)
            Text(model.toastMessage)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(StudioStyle.popup, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(StudioStyle.border))
        .shadow(radius: 6)
        .padding(.bottom, 18)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var toastIcon: String {
        if model.toastMessage.contains("成功") || model.toastMessage.contains("完成") { return "checkmark.circle.fill" }
        if model.toastMessage.contains("失败") || model.toastMessage.contains("错误") { return "xmark.circle.fill" }
        return "info.circle.fill"
    }

    private var toastColor: Color {
        if model.toastMessage.contains("成功") || model.toastMessage.contains("完成") { return StudioStyle.success }
        if model.toastMessage.contains("失败") || model.toastMessage.contains("错误") { return StudioStyle.danger }
        return StudioStyle.accent
    }
}

#Preview {
    MainWindow()
}
