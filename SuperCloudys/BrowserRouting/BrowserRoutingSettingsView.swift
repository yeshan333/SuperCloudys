import SwiftUI

@MainActor
final class BrowserRoutingSettingsWindow {
    static let shared = BrowserRoutingSettingsWindow()
    private var window: NSWindow?

    func show() {
        BrowserRoutingController.shared.refreshBrowsers()
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "浏览器分流"
            window.contentView = NSHostingView(rootView: BrowserRoutingSettingsView())
            window.minSize = NSSize(width: 700, height: 520)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct BrowserRoutingSettingsView: View {
    @ObservedObject private var controller = BrowserRoutingController.shared
    @State private var editingRule: BrowserRoutingRule?
    @State private var testURL = "https://gitlab.lingxigames-inc.com/"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("浏览器分流").font(.title2.bold())
                    Text("按顺序匹配，第一条命中规则决定浏览器。设置自动保存。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("启用规则", isOn: Binding(
                    get: { controller.configuration.isEnabled }, set: { controller.setEnabled($0) }
                ))
                .toggleStyle(.switch)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(
                            controller.isDefaultBrowser ? "系统链接分流已启用" : "系统链接分流未启用",
                            systemImage: controller.isDefaultBrowser ? "checkmark.circle.fill" : "globe"
                        )
                        Spacer()
                        Button(controller.isSettingDefault ? "正在启用…" : "启用系统链接分流") {
                            Task { await controller.makeDefaultBrowser() }
                        }
                        .disabled(controller.isDefaultBrowser || controller.isSettingDefault)
                    }
                    Text("启用会请求 macOS 将网页链接先交给 SuperCloudys 分流，再由下方选择的浏览器打开。暂停规则后使用兜底浏览器。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        BrowserPicker(title: "兜底浏览器", selection: Binding(
                            get: { controller.configuration.fallbackBrowserBundleID },
                            set: { controller.setFallbackBrowser($0) }
                        ), browsers: controller.browsers)
                        Button("刷新浏览器") { controller.refreshBrowsers() }
                    }
                }
                .padding(6)
            }

            if let error = controller.lastError {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }

            HStack {
                Text("匹配规则").font(.headline)
                Spacer()
                Button("添加规则", systemImage: "plus") {
                    editingRule = BrowserRoutingRule(browserBundleID: controller.configuration.fallbackBrowserBundleID)
                }
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    if controller.configuration.rules.isEmpty {
                        Text("暂无规则，所有链接使用兜底浏览器。")
                            .foregroundStyle(.secondary).padding(24)
                    }
                    ForEach(Array(controller.configuration.rules.enumerated()), id: \.element.id) { index, rule in
                        ruleRow(rule, index: index)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            GroupBox("测试链接（仅预览，不打开浏览器）") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("https://example.com/path", text: $testURL)
                        .textFieldStyle(.roundedBorder)
                    Text(URL(string: testURL).map { controller.preview($0) } ?? "请输入有效 URL。")
                        .font(.callout).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
        }
        .padding(20)
        .sheet(item: $editingRule) { rule in
            BrowserRuleEditor(rule: rule, browsers: controller.browsers) { controller.saveRule($0) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshBrowsers()
        }
    }

    private func ruleRow(_ rule: BrowserRoutingRule, index: Int) -> some View {
        HStack(spacing: 10) {
            Toggle("启用规则 \(index + 1)", isOn: Binding(
                get: { rule.isEnabled },
                set: { enabled in
                    var updated = rule
                    updated.isEnabled = enabled
                    controller.saveRule(updated)
                }
            ))
            .labelsHidden()
            VStack(alignment: .leading, spacing: 4) {
                Text("\(index + 1). \(rule.kind.title)：\(rule.pattern)")
                    .lineLimit(2).help(rule.pattern)
                Text(ruleDescription(rule)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { controller.moveRule(rule.id, offset: -1) } label: { Image(systemName: "arrow.up") }
                .help("提高优先级").disabled(index == 0)
            Button { controller.moveRule(rule.id, offset: 1) } label: { Image(systemName: "arrow.down") }
                .help("降低优先级").disabled(index == controller.configuration.rules.count - 1)
            Button("编辑") { editingRule = rule }
            Button(role: .destructive) { controller.removeRule(rule.id) } label: { Image(systemName: "trash") }
                .help("删除规则")
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func ruleDescription(_ rule: BrowserRoutingRule) -> String {
        let browser = controller.browsers.first { $0.id == rule.browserBundleID }?.name
            ?? "\(rule.browserBundleID)（不可用，将使用兜底）"
        let scope = rule.kind == .pathPrefix && !rule.domain.isEmpty ? "域名：\(rule.domain) · " : ""
        return "\(scope)→ \(browser)"
    }
}

private struct BrowserPicker: View {
    let title: String
    @Binding var selection: String
    let browsers: [InstalledBrowser]

    private var browserOptions: [InstalledBrowser] {
        browsers.filter { $0.id != BrowserRoutingController.ownBundleID }
    }

    var body: some View {
        Picker(title, selection: Binding(
            get: { selection == BrowserRoutingController.ownBundleID ? "" : selection },
            set: { selection = $0 }
        )) {
            if selection.isEmpty || selection == BrowserRoutingController.ownBundleID {
                Text("请选择浏览器").tag("").disabled(true)
            } else if !browserOptions.contains(where: { $0.id == selection }) {
                Text("\(selection)（不可用）").tag(selection)
            }
            ForEach(browserOptions) { browser in
                Text(browser.name).tag(browser.id)
            }
        }
    }
}

private struct BrowserRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: BrowserRoutingRule
    let browsers: [InstalledBrowser]
    let save: (BrowserRoutingRule) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("编辑浏览器规则").font(.title2.bold())
            Form {
                Picker("匹配方式", selection: $rule.kind) {
                    ForEach(BrowserRuleKind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                TextField("匹配内容", text: $rule.pattern, prompt: Text(placeholder))
                if rule.kind == .pathPrefix {
                    TextField("限定域名（选填）", text: $rule.domain, prompt: Text("留空匹配所有域名"))
                }
                if rule.kind != .regularExpression {
                    Toggle("包含子域名", isOn: $rule.includesSubdomains)
                }
                BrowserPicker(title: "目标浏览器", selection: $rule.browserBundleID, browsers: browsers)
                Toggle("启用此规则", isOn: $rule.isEnabled)
            }
            Text(explanation).font(.caption).foregroundStyle(.secondary)
            if let error = rule.validationError {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { if save(rule) { dismiss() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(rule.validationError != nil)
            }
        }
        .padding(24).frame(width: 520)
    }

    private var placeholder: String {
        switch rule.kind {
        case .domain: return "example.com"
        case .pathPrefix: return "/projects/"
        case .regularExpression: return #"^https://example\.com/projects/"#
        }
    }

    private var explanation: String {
        switch rule.kind {
        case .domain: return "域名不区分大小写，匹配该网站的所有路径；包含子域名时也匹配其下级域名。"
        case .pathPrefix: return "路径前缀区分大小写，使用 URL 编码后的路径，不包含查询参数和 # 片段。例如 /docs 也匹配 /docs-old；如需目录边界请填写 /docs/。"
        case .regularExpression: return "对完整 URL（含协议、查询参数和片段）查找匹配，默认区分大小写。用 ^ 和 $ 限定完整范围，(?i) 忽略大小写。复杂表达式超时将视为不匹配。"
        }
    }
}
