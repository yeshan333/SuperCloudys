import SwiftUI
import AppKit

struct DockAppsSection: View {
    @ObservedObject var monitor: DockMonitor

    var body: some View {
        Section("Dock 快捷键") {
            Toggle("启用 Cmd+1~0 快捷键", isOn: $monitor.shortcutsEnabled)

            if monitor.apps.isEmpty {
                Text("未检测到 Dock 应用").foregroundStyle(.secondary)
            } else {
                ForEach(monitor.apps.prefix(DockApp.maxShortcutApps)) { app in
                    Button(action: { activate(app) }) {
                        Label {
                            Text(rowTitle(for: app))
                        } icon: {
                            appIcon(path: app.appPath)
                        }
                    }
                }
            }

            Button("刷新 Dock") {
                monitor.refresh(forceRegister: true)
            }
        }
    }

    // MARK: - Helpers

    private func rowTitle(for app: DockApp) -> String {
        if let label = app.shortcutLabel {
            return "⌘\(label)  \(app.name)"
        }
        return app.name
    }

    private func appIcon(path: String) -> Image {
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            let nsImage = NSWorkspace.shared.icon(forFile: path)
            nsImage.size = NSSize(width: 16, height: 16)
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "app")
    }

    private func activate(_ app: DockApp) {
        DockAppLauncher.toggle(bundleID: app.bundleID, appPath: app.appPath)
    }
}
