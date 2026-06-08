import SwiftUI

struct MenuBarView: View {
    @StateObject private var extensionStatus = ExtensionStatus()
    @EnvironmentObject private var dockMonitor: DockMonitor
    @EnvironmentObject private var loginItem: LoginItemManager
    @State private var customApps: [CustomApp] = CustomAppStore.load()

    var body: some View {
        // Header
        Text("\(AppConstants.appName) v2.0.0")
            .font(.headline)

        Divider()

        // 扩展状态
        if extensionStatus.isEnabled {
            Label("Finder 扩展已启用", systemImage: "checkmark.circle.fill")
        } else {
            Label("Finder 扩展未启用", systemImage: "xmark.circle")
        }

        Divider()

        DockAppsSection(monitor: dockMonitor)

        Divider()

        // 自定义打开方式
        Section("自定义打开方式") {
            ForEach(customApps) { app in
                Button(action: { removeCustomApp(app) }) {
                    Label {
                        Text("\(app.name)  (点击移除)")
                    } icon: {
                        AppIconView(path: app.appPath)
                    }
                }
            }

            Button(action: addCustomApp) {
                Label("添加应用…", systemImage: "plus.circle")
            }
        }

        Divider()

        Toggle("开机自启", isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
        ))

        Divider()

        Button("打开系统设置…") {
            extensionStatus.openSystemSettings()
        }
        Button("刷新状态") {
            extensionStatus.checkStatus()
            customApps = CustomAppStore.load()
            dockMonitor.refresh(forceRegister: true)
            loginItem.refresh()
        }

        Divider()

        Button("退出 \(AppConstants.appName)") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // MARK: - Helpers



    // MARK: - Actions

    private func addCustomApp() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let panel = NSOpenPanel()
            panel.title = "选择应用"
            panel.allowedContentTypes = [.application]
            panel.allowsMultipleSelection = false
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.level = .floating

            guard panel.runModal() == .OK, let url = panel.url else { return }
            let name = url.deletingPathExtension().lastPathComponent
            CustomAppStore.add(CustomApp(name: name, appPath: url.path))
            customApps = CustomAppStore.load()
        }
    }

    private func removeCustomApp(_ app: CustomApp) {
        CustomAppStore.remove(app)
        customApps = CustomAppStore.load()
    }
}
