// 对标 software/ui/shell/main_window.py
// 主窗口：NavigationSplitView 侧边导航（概览/运行参数/日志 + 设置/关于）。

import SwiftUI

enum AppPage: String, Hashable, Identifiable, CaseIterable {
    case overview = "概览"
    case runtime = "运行参数"
    case logs = "日志"
    case settings = "设置"
    case about = "关于"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .runtime: return "slider.horizontal.3"
        case .logs: return "doc.text"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

struct MainWindow: View {
    @State private var model = AppModel()
    @State private var selection: AppPage? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("工作台") {
                    ForEach([AppPage.overview, .runtime, .logs]) { page in
                        Label(page.rawValue, systemImage: page.systemImage)
                            .tag(page)
                    }
                }
                Section("更多") {
                    ForEach([AppPage.settings, .about]) { page in
                        Label(page.rawValue, systemImage: page.systemImage)
                            .tag(page)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch selection {
            case .overview: OverviewScreen(model: model)
            case .runtime: RuntimeScreen(model: model)
            case .logs: LogsScreen(model: model)
            case .settings: SettingsScreen(model: model)
            case .about: AboutScreen()
            case nil: OverviewScreen(model: model)
            }
        }
        .navigationTitle("SurveyController")
        .frame(minWidth: 940, minHeight: 620)
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
