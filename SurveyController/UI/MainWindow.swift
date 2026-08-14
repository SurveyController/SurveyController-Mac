// 对标官方 5.0 主窗口：左侧 任务/日志/设置/更多，任务页为 6 步向导。

import SwiftUI

enum AppPage: String, Hashable, Identifiable, CaseIterable {
    case task = "任务"
    case settings = "设置"
    case community = "社区"
    case logs = "日志"
    case about = "更多"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .task: return "house"
        case .settings: return "gearshape"
        case .community: return "bubble.left.and.bubble.right"
        case .logs: return "doc.text"
        case .about: return "ellipsis.circle"
        }
    }
}

struct MainWindow: View {
    @State private var model = AppModel()
    @State private var selection: AppPage? = .task

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label(AppPage.task.rawValue, systemImage: AppPage.task.systemImage)
                        .tag(AppPage.task)
                }
                Section("更多") {
                    ForEach([AppPage.settings, .community, .logs, .about]) { page in
                        Label(page.rawValue, systemImage: page.systemImage)
                            .tag(page)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selection {
            case .task: WizardView(model: model)
            case .settings: SettingsScreen(model: model)
            case .community: CommunityScreen()
            case .logs: LogsScreen(model: model)
            case .about: AboutScreen()
            case nil: WizardView(model: model)
            }
        }
        .navigationTitle("SurveyController \(AppVersion.version)")
        .frame(minWidth: 960, minHeight: 640)
        .overlay(alignment: .bottom) {
            if !model.toastMessage.isEmpty {
                toastView
            }
        }
    }

    private var toastView: some View {
        Text(model.toastMessage)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 6)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

#Preview {
    MainWindow()
}
