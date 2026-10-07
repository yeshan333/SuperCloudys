import SwiftUI
import UniformTypeIdentifiers

struct AppInputSourceMenu: View {
    @ObservedObject private var controller = AppInputSourceController.shared
    @ObservedObject private var appIcons = AppIconCache.shared

    var body: some View {
        Menu("应用默认输入法") {
            Toggle("启用自动切换", isOn: Binding(
                get: { controller.isEnabled },
                set: { controller.setEnabled($0) }
            ))
            Toggle("显示输入法提示", isOn: Binding(
                get: { controller.showsIndicator },
                set: { controller.setShowsIndicator($0) }
            ))
            Text("进入应用时切换；未配置的应用保持当前输入法")

            if let error = controller.lastError {
                Text(error).foregroundStyle(.red)
            }

            Divider()

            if controller.rules.isEmpty {
                Text("暂无应用配置")
            }
            ForEach(controller.rules) { rule in
                Menu {
                    if !controller.sources.contains(where: { $0.id == rule.inputSource }) {
                        Text("已配置的输入法不可用：\(rule.inputSourceName)")
                    }
                    ForEach(controller.sources) { source in
                        Toggle(isOn: Binding(
                            get: { rule.inputSource == source.id },
                            set: { selected in
                                guard selected else { return }
                                controller.setRule(
                                    bundleID: rule.bundleID, appName: rule.appName,
                                    appPath: rule.appPath, source: source
                                )
                            }
                        )) {
                            Label {
                                Text(source.name)
                            } icon: {
                                Image(nsImage: InputSourceMenuIcons.shared.icon(for: source))
                            }
                            .labelStyle(.titleAndIcon)
                        }
                    }
                    Divider()
                    Button("移除配置") { controller.removeRule(bundleID: rule.bundleID) }
                } label: {
                    Label {
                        Text("\(rule.appName) → \(sourceName(for: rule))")
                    } icon: {
                        Image(nsImage: InputSourceMenuIcons.applicationIcon(
                            appIcons.icon(forPath: rule.appPath),
                            sourceIcon: InputSourceMenuIcons.shared.icon(for: KeyboardInputSource(
                                id: rule.inputSource, name: rule.inputSourceName
                            ))
                        ))
                    }
                    .labelStyle(.titleAndIcon)
                }
            }

            Divider()
            Button("添加应用…") { addApplication() }
                .disabled(controller.sources.isEmpty)
            if controller.sources.isEmpty {
                Text("请先在系统设置中添加输入法")
            }
            Button("刷新输入法列表") { controller.refreshSources() }
        }
        .onAppear { controller.refreshSources() }
    }

    private func sourceName(for rule: AppInputSourceRule) -> String {
        controller.sources.first(where: { $0.id == rule.inputSource })?.name
            ?? "\(rule.inputSourceName)（不可用）"
    }

    private func addApplication() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let panel = NSOpenPanel()
            panel.title = "选择要配置默认输入法的应用"
            panel.allowedContentTypes = [.application]
            panel.allowsMultipleSelection = false
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.level = .floating
            guard panel.runModal() == .OK, let url = panel.url else { return }
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
                let alert = NSAlert()
                alert.messageText = "无法读取所选应用的 Bundle ID。"
                alert.runModal()
                return
            }

            controller.refreshSources()
            let sources = controller.sources
            guard !sources.isEmpty else { return }
            let appName = FileManager.default.displayName(atPath: url.path)
            let alert = NSAlert()
            alert.messageText = "设置 \(appName) 的默认输入法"
            alert.informativeText = "启用自动切换后，每次进入该应用都会使用所选输入法。"
            alert.addButton(withTitle: "保存")
            alert.addButton(withTitle: "取消")
            let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
            picker.addItems(withTitles: sources.map(\.name))
            for (item, source) in zip(picker.itemArray, sources) {
                item.image = InputSourceMenuIcons.shared.icon(for: source)
            }
            if let rule = controller.rules.first(where: { $0.bundleID == bundleID }),
               let index = sources.firstIndex(where: { $0.id == rule.inputSource }) {
                picker.selectItem(at: index)
            }
            alert.accessoryView = picker
            guard alert.runModal() == .alertFirstButtonReturn,
                  sources.indices.contains(picker.indexOfSelectedItem) else { return }
            controller.setRule(
                bundleID: bundleID, appName: appName, appPath: url.path,
                source: sources[picker.indexOfSelectedItem]
            )
        }
    }
}
