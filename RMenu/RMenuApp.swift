import SwiftUI

@main
struct RMenuApp: App {
    @StateObject private var dockMonitor = DockMonitor()
    @StateObject private var loginItem = LoginItemManager()

    init() {
        // 后台预热 LaunchServices 图标缓存,降低 Finder 扩展冷启动开销
        IconPrewarmer.prewarmInBackground()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(dockMonitor)
                .environmentObject(loginItem)
        } label: {
            Label(AppConstants.appName, systemImage: "folder.badge.gearshape")
        }
    }
}
