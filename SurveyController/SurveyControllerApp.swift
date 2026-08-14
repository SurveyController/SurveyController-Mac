// 对标 SurveyController.py + software/app/main.py（macOS SwiftUI 入口）

import SwiftUI

@main
struct SurveyControllerApp: App {
    var body: some Scene {
        WindowGroup {
            MainWindow()
        }
        .windowResizability(.contentMinSize)
    }
}
