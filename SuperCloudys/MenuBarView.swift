import SwiftUI
import CoreServices
import UniformTypeIdentifiers

struct MenuBarView: View {
    @StateObject private var extensionStatus = ExtensionStatus()
    @EnvironmentObject private var dockMonitor: DockMonitor
    @EnvironmentObject private var loginItem: LoginItemManager
    @ObservedObject private var clipboard = ClipboardHistoryController.shared
    @ObservedObject private var clipboardHotkey = ClipboardHotkeyManager.shared
    @State private var customApps: [CustomApp] = CustomAppStore.load()
    @State private var monitoredExtensions: [String] = {
        let saved = UserDefaults.standard.stringArray(forKey: "SuperCloudys.monitoredExtensions")
        var seen = Set<String>()
        return (saved ?? ["txt", "pdf", "png", "mp4", "zip", "html"]).compactMap {
            let value = $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
            return !value.isEmpty && seen.insert(value).inserted ? value : nil
        }
    }()
    @State private var defaultApps: [String: DefaultAppInfo] = [:]
    @State private var defaultAppsRefreshGeneration = 0
    @State private var defaultAppsLoading = false
    @State private var accessibilityTrusted = AccessibilityActivator.isTrusted

    var body: some View {
        // Header
        Text("\(AppConstants.appName) v\(Self.appVersion)")
            .font(.headline)
            .onAppear { refreshState() }

        Divider()

        // 扩展状态
        if extensionStatus.isEnabled {
            Label("Finder 扩展已启用", systemImage: "checkmark.circle.fill")
        } else {
            Label("Finder 扩展未启用", systemImage: "xmark.circle")
        }
        if let error = extensionStatus.lastError {
            Text(error).foregroundStyle(.red)
        }

        Divider()

        DockAppsSection(monitor: dockMonitor)

        Divider()

        Section("剪贴板历史") {
            Button("打开剪贴板历史") {
                ClipboardPanelController.shared.show()
            }
            .keyboardShortcut("h", modifiers: [.control])

            Toggle("暂停记录", isOn: Binding(
                get: { clipboard.isMonitoringPaused },
                set: { clipboard.setMonitoringPaused($0) }
            ))

            if let error = clipboardHotkey.registrationError {
                Text(error).foregroundStyle(.red)
                Button("重试 Ctrl+H") {
                    clipboardHotkey.unregister()
                    clipboardHotkey.register()
                }
            }

            if let error = clipboard.storageError {
                Text(error).foregroundStyle(.red)
            }

            Menu("保留期限：\(retentionLabel)") {
                ForEach([(0, "永久"), (1, "1 天"), (7, "7 天"), (30, "30 天"), (90, "90 天")], id: \.0) { days, label in
                    Button {
                        clipboard.setRetentionDays(days)
                    } label: {
                        if clipboard.retentionDays == days {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            }

            Menu("最多记录：\(clipboard.maxEntries) 条") {
                ForEach([100, 500, 1000], id: \.self) { count in
                    Button {
                        clipboard.setMaxEntries(count)
                    } label: {
                        if clipboard.maxEntries == count {
                            Label("\(count) 条", systemImage: "checkmark")
                        } else {
                            Text("\(count) 条")
                        }
                    }
                }
            }

            Menu("排除应用") {
                if clipboard.excludedApps.isEmpty {
                    Text("暂无排除应用")
                } else {
                    ForEach(clipboard.excludedApps, id: \.self) { bundleID in
                        Button("移除 \(excludedAppName(bundleID))") {
                            clipboard.removeExcludedApp(bundleID: bundleID)
                        }
                    }
                    Divider()
                }
                Button("添加应用…") { addExcludedApp() }
            }
            Text("来源应用按复制时的前台应用推断")
                .foregroundStyle(.secondary)
        }

        Divider()

        // 默认打开应用展示
        Menu("文件默认打开应用") {
            ForEach(monitoredExtensions, id: \.self) { ext in
                if let appInfo = defaultApps[ext] {
                    Button(action: { changeDefaultApp(for: ext) }) {
                        Label {
                            Text(".\(ext)  →  \(appInfo.appName)")
                        } icon: {
                            AppIconView(path: appInfo.appPath)
                        }
                    }
                } else if defaultAppsLoading {
                    Text(".\(ext)  →  正在读取…")
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

        if let message = loginItem.statusMessage {
            Text(message).foregroundStyle(loginItem.lastError == nil ? Color.secondary : Color.red)
        }

        if accessibilityTrusted {
            Label("辅助功能权限已授予", systemImage: "checkmark.circle.fill")
        } else {
            Button("授予辅助功能权限…") {
                _ = AccessibilityActivator.requestTrust()
                AccessibilityActivator.openSystemSettings()
            }
        }

        Divider()

        Button("打开系统设置…") {
            extensionStatus.openSystemSettings()
        }
        Button("刷新状态") {
            refreshState(forceDockRegister: true)
        }

        Divider()

        Button("退出 \(AppConstants.appName)") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // MARK: - Helpers

    private static let appVersion = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "dev"

    private var retentionLabel: String {
        clipboard.retentionDays == 0 ? "永久" : "\(clipboard.retentionDays) 天"
    }

    private func excludedAppName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?
            .deletingPathExtension().lastPathComponent ?? bundleID
    }

    private func refreshState(forceDockRegister: Bool = false) {
        extensionStatus.checkStatus()
        customApps = CustomAppStore.load()
        dockMonitor.refresh(forceRegister: forceDockRegister)
        loginItem.refresh()
        accessibilityTrusted = AccessibilityActivator.isTrusted
        refreshDefaultApps()
    }

    private func refreshDefaultApps() {
        defaultAppsRefreshGeneration += 1
        let generation = defaultAppsRefreshGeneration
        defaultAppsLoading = true
        let extensions = monitoredExtensions
        DispatchQueue.global(qos: .userInitiated).async {
            let values = extensions.reduce(into: [String: DefaultAppInfo]()) { result, ext in
                if let info = Self.defaultAppInfo(for: ext) { result[ext] = info }
            }
            DispatchQueue.main.async {
                guard generation == defaultAppsRefreshGeneration else { return }
                defaultApps = values
                defaultAppsLoading = false
            }
        }
    }

    nonisolated private static func defaultAppInfo(for ext: String) -> DefaultAppInfo? {
        guard let type = UTType(filenameExtension: ext),
              let handler = LSCopyDefaultRoleHandlerForContentType(
                  type.identifier as CFString, .all
              )?.takeRetainedValue() as String?,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: handler) else {
            return nil
        }
        return DefaultAppInfo(
            appName: appURL.deletingPathExtension().lastPathComponent,
            appPath: appURL.path
        )
    }

    private func chooseApplication(title: String, completion: @escaping (URL) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let panel = NSOpenPanel()
            panel.title = title
            panel.allowedContentTypes = [.application]
            panel.allowsMultipleSelection = false
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.level = .floating
            guard panel.runModal() == .OK, let url = panel.url else { return }
            completion(url)
        }
    }

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "操作失败"
        alert.informativeText = message
        alert.runModal()
    }


    // MARK: - Actions

    private func addCustomApp() {
        chooseApplication(title: "选择应用") { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard CustomAppStore.add(CustomApp(
                name: name,
                appPath: url.path,
                bundleID: Bundle(url: url)?.bundleIdentifier
            )) else {
                showError("无法保存自定义应用，请检查应用支持目录权限。")
                return
            }
            customApps = CustomAppStore.load()
        }
    }

    private func removeCustomApp(_ app: CustomApp) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "移除 \(app.name)？"
        alert.informativeText = "它将不再出现在 Finder 右键菜单中。"
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard CustomAppStore.remove(app) else {
            showError("无法保存更改，请检查应用支持目录权限。")
            return
        }
        customApps = CustomAppStore.load()
    }

    private func addExcludedApp() {
        chooseApplication(title: "选择不记录剪贴板的应用") { url in
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
                showError("无法读取所选应用的 Bundle ID。")
                return
            }
            clipboard.addExcludedApp(bundleID: bundleID)
        }
    }

    // MARK: - Default Open With Helpers

    private struct DefaultAppInfo: Sendable {
        let appName: String
        let appPath: String
    }

    private func changeDefaultApp(for ext: String) {
        chooseApplication(title: "选择默认打开应用") { url in
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
                showError("无法读取所选应用的 Bundle ID。")
                return
            }
            guard let type = UTType(filenameExtension: ext) else {
                showError("无法识别 .\(ext) 文件类型。")
                return
            }
            let status = LSSetDefaultRoleHandlerForContentType(
                type.identifier as CFString, .all, bundleID as CFString
            )
            guard status == noErr else {
                showError(NSError(domain: NSOSStatusErrorDomain, code: Int(status)).localizedDescription)
                return
            }
            let actual = LSCopyDefaultRoleHandlerForContentType(
                type.identifier as CFString, .all
            )?.takeRetainedValue() as String?
            guard actual == bundleID else {
                showError("系统未保存新的默认打开应用。")
                return
            }
            refreshDefaultApps()
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
            var ext = inputTextField.stringValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            while ext.hasPrefix(".") { ext.removeFirst() }
            guard ext.range(
                of: #"^[a-z0-9][a-z0-9+_-]{0,31}$"#,
                options: .regularExpression
            ) != nil else {
                showError("请输入有效后缀，例如 md、py 或 heic。")
                return
            }

            if !monitoredExtensions.contains(ext) {
                monitoredExtensions.append(ext)
                UserDefaults.standard.set(monitoredExtensions, forKey: "SuperCloudys.monitoredExtensions")
                refreshDefaultApps()
            }
        }
    }

    private func removeMonitoredExtension(_ ext: String) {
        if let idx = monitoredExtensions.firstIndex(of: ext) {
            monitoredExtensions.remove(at: idx)
            UserDefaults.standard.set(monitoredExtensions, forKey: "SuperCloudys.monitoredExtensions")
            defaultAppsRefreshGeneration += 1
            defaultAppsLoading = false
            defaultApps.removeValue(forKey: ext)
        }
    }
}
