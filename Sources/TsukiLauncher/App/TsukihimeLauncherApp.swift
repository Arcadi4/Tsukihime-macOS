import SwiftUI

@main
struct TsukihimeLauncherApp: App {
    var body: some Scene {
        Window("TSUKIHIME Launcher", id: "main") {
            MainLauncherWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 680)
    }
}
