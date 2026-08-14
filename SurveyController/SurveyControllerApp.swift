// 对标 SurveyController.py + software/app/main.py（macOS SwiftUI 入口）

import SwiftUI

@main
struct SurveyControllerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
    }
}

/// 占位主界面：v0.1 阶段 5 会替换为完整工作台导航。
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("SurveyController for Mac")
                .font(.title2.bold())
            Text("v\(AppVersion.version)（对齐官方 v\(AppVersion.alignedOfficialVersion)）")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 640, minHeight: 420)
        .padding()
    }
}
