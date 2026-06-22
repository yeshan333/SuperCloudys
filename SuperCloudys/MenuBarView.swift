import SwiftUI
import CoreServices
import UniformTypeIdentifiers

struct MenuBarView: View {
    @StateObject private var extensionStatus = ExtensionStatus()
    @EnvironmentObject private var dockMonitor: DockMonitor
    @EnvironmentObject private var loginItem: LoginItemManager
    @State private var customApps: [CustomApp] = CustomAppStore.load()
    @State private var monitoredExtensions: [String] = {
        let saved = UserDefaults.standard.stringArray(forKey: "SuperCloudys.monitoredExtensions")
        return saved ?? ["txt", "pdf", "png", "mp4", "zip", "html"]
    }()
    @State private var refreshTrigger = false

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

        // 默认打开应用展示
        Menu("文件默认打开应用") {
            let _ = refreshTrigger // force refresh
            ForEach(monitoredExtensions, id: \.self) { ext in
                if let appInfo = getDefaultAppInfo(for: ext) {
                    Button(action: { changeDefaultApp(for: ext) }) {
                        Label {
                            Text(".\(ext)  →  \(appInfo.appName)")
                        } icon: {
                            AppIconView(path: appInfo.appPath)
                        }
                    }
                } else {
                    Button(action: { changeDefaultApp(for: ext) }) {
                        Text(".\(ext)  →  未指定 (点击设置)")
                    }
                }
            }

            Divider()

            Button(action: addMonitoredExtension) {
                Label("添加后缀…", systemImage: "plus.circle")
            }

            if !monitoredExtensions.isEmpty {
                Menu("移除后缀…") {
                    ForEach(monitoredExtensions, id: \.self) { ext in
                        Button(action: { removeMonitoredExtension(ext) }) {
                            Text("移除 .\(ext)")
                        }
                    }
                }
            }
        }

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

    // MARK: - Default Open With Helpers

    private struct DefaultAppInfo {
        let appName: String
        let appPath: String
    }

    private func getDefaultAppInfo(for ext: String) -> DefaultAppInfo? {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent("temp_check_\(UUID().uuidString).\(ext)")

        fileManager.createFile(atPath: tempFileURL.path, contents: nil, attributes: nil)
        defer {
            try? fileManager.removeItem(at: tempFileURL)
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: tempFileURL) else {
            return nil
        }

        var appName = fileManager.displayName(atPath: appURL.path)
        if appName.hasSuffix(".app") {
            appName = String(appName.dropLast(4))
        }
        return DefaultAppInfo(appName: appName, appPath: appURL.path)
    }

    private func changeDefaultApp(for ext: String) {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let panel = NSOpenPanel()
            panel.title = "选择默认打开应用"
            panel.allowedContentTypes = [.application]
            panel.allowsMultipleSelection = false
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.level = .floating

            guard panel.runModal() == .OK, let url = panel.url else { return }
            let appPath = url.path

            guard let bundleID = Bundle(path: appPath)?.bundleIdentifier else {
                return
            }

            if let type = UTType(filenameExtension: ext) {
                let contentType = type.identifier
                let status = LSSetDefaultRoleHandlerForContentType(contentType as CFString, .all, bundleID as CFString)
                if status == noErr {
                    refreshTrigger.toggle()
                }
            }
        }
    }

    private func addMonitoredExtension() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let alert = NSAlert()
            alert.messageText = "添加特定后缀"
            alert.informativeText = "请输入要展示的后缀名 (例如: md, py):"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")

            let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            inputTextField.placeholderString = "md"
            alert.accessoryView = inputTextField

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let rawText = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            var ext = rawText
            if ext.hasPrefix(".") {
                ext = String(ext.dropFirst())
            }
            guard !ext.isEmpty else { return }

            if !monitoredExtensions.contains(ext) {
                monitoredExtensions.append(ext)
                UserDefaults.standard.set(monitoredExtensions, forKey: "SuperCloudys.monitoredExtensions")
                refreshTrigger.toggle()
            }
        }
    }

    private func removeMonitoredExtension(_ ext: String) {
        if let idx = monitoredExtensions.firstIndex(of: ext) {
            monitoredExtensions.remove(at: idx)
            UserDefaults.standard.set(monitoredExtensions, forKey: "SuperCloudys.monitoredExtensions")
            refreshTrigger.toggle()
        }
    }
}
