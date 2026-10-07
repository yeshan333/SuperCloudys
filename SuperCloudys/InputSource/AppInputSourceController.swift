import AppKit
import Carbon
import Combine

@MainActor
final class AppInputSourceController: ObservableObject {
    static let shared = AppInputSourceController(indicator: InputSourceIndicatorController.shared)

    @Published private(set) var isEnabled: Bool
    @Published private(set) var showsIndicator: Bool
    @Published private(set) var rules: [AppInputSourceRule]
    @Published private(set) var sources: [KeyboardInputSource] = []
    @Published private(set) var lastError: String?

    private let settings: InputSourceSettings
    private let service: any InputSourceService
    private let indicator: (any InputSourceIndicatorPresenting)?
    private let frontmostBundleID: () -> String?
    private var activationObserver: NSObjectProtocol?
    private var sourcesObserver: NSObjectProtocol?
    private var selectedSourceObserver: NSObjectProtocol?
    private var pendingSwitch: Task<Void, Never>?
    private var pendingIndicator: Task<Void, Never>?
    private var isMonitoring = false

    init(
        settings: InputSourceSettings = InputSourceSettings(),
        service: (any InputSourceService)? = nil,
        indicator: (any InputSourceIndicatorPresenting)? = nil,
        frontmostBundleID: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    ) {
        self.settings = settings
        self.service = service ?? SystemInputSourceService()
        self.indicator = indicator
        self.frontmostBundleID = frontmostBundleID
        self.isEnabled = settings.isEnabled
        self.showsIndicator = settings.showsIndicator
        self.rules = settings.rules
        refreshSources()
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            MainActor.assumeIsolated { self?.scheduleSwitch(for: bundleID) }
        }
        sourcesObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSources() }
        }
        selectedSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.inputSourceDidChange() }
        }
        scheduleSwitch(for: frontmostBundleID())
    }

    func stopMonitoring() {
        isMonitoring = false
        pendingSwitch?.cancel()
        pendingSwitch = nil
        pendingIndicator?.cancel()
        pendingIndicator = nil
        indicator?.hide()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let sourcesObserver {
            DistributedNotificationCenter.default().removeObserver(sourcesObserver)
        }
        if let selectedSourceObserver {
            DistributedNotificationCenter.default().removeObserver(selectedSourceObserver)
        }
        activationObserver = nil
        sourcesObserver = nil
        selectedSourceObserver = nil
    }

    func setEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        isEnabled = enabled
        lastError = nil
        scheduleSwitch(for: frontmostBundleID())
    }

    func setShowsIndicator(_ enabled: Bool) {
        settings.showsIndicator = enabled
        showsIndicator = enabled
        if !enabled {
            pendingIndicator?.cancel()
            pendingIndicator = nil
            indicator?.hide()
        }
    }

    func setRule(bundleID: String, appName: String, appPath: String, source: KeyboardInputSource) {
        let rule = AppInputSourceRule(
            bundleID: bundleID, appName: appName, appPath: appPath,
            inputSource: source.id, inputSourceName: source.name
        )
        rules.removeAll { $0.bundleID == bundleID }
        rules.append(rule)
        rules.sort { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
        settings.rules = rules
        lastError = nil
        if frontmostBundleID() == bundleID {
            scheduleSwitch(for: bundleID)
        }
    }

    func removeRule(bundleID: String) {
        rules.removeAll { $0.bundleID == bundleID }
        settings.rules = rules
        lastError = nil
    }

    func refreshSources() {
        sources = service.availableSources()
    }

    /// 等待前台切换完成；快速切换应用时取消上一条待执行操作。
    func scheduleSwitch(for bundleID: String?) {
        pendingSwitch?.cancel()
        pendingSwitch = nil
        pendingIndicator?.cancel()
        pendingIndicator = nil
        indicator?.hide()
        guard isEnabled || showsIndicator, let bundleID else { return }
        pendingSwitch = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.frontmostBundleID() == bundleID else {
                self.pendingSwitch = nil
                return
            }
            self.applyDefault(for: bundleID)
            self.pendingSwitch = nil
            self.scheduleIndicator(for: bundleID)
        }
    }

    func applyDefault(for bundleID: String) {
        guard isEnabled, frontmostBundleID() == bundleID else { return }
        lastError = nil
        guard let rule = rules.first(where: { $0.bundleID == bundleID }) else { return }
        refreshSources()
        guard sources.contains(where: { $0.id == rule.inputSource }) else {
            lastError = "\(rule.appName) 的默认输入法“\(rule.inputSourceName)”不可用，请在系统设置中启用或重新选择。"
            return
        }
        guard service.currentSourceID() != rule.inputSource else { return }
        let status = service.select(rule.inputSource)
        if status != 0 {
            lastError = "无法切换 \(rule.appName) 的输入法：\(NSError(domain: NSOSStatusErrorDomain, code: Int(status)).localizedDescription)"
        }
    }

    /// 手动切换输入法时只更新提示，不重新应用默认输入法。
    func inputSourceDidChange() {
        guard pendingSwitch == nil else { return }
        scheduleIndicator(for: frontmostBundleID())
    }

    private func scheduleIndicator(for bundleID: String?) {
        pendingIndicator?.cancel()
        pendingIndicator = nil
        guard showsIndicator, indicator != nil, let bundleID else { return }
        pendingIndicator = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.showCurrentInputSource(for: bundleID)
        }
    }

    func showCurrentInputSource(for bundleID: String) {
        guard showsIndicator, frontmostBundleID() == bundleID,
              bundleID != Bundle.main.bundleIdentifier else { return }
        // 从系统回读实际输入法，切换失败时也不能把配置值显示成当前值。
        guard let current = service.currentSourceID(),
              let source = service.availableSources().first(where: { $0.id == current }) else {
            indicator?.hide()
            return
        }
        let app = NSWorkspace.shared.frontmostApplication
        let rule = rules.first(where: { $0.bundleID == bundleID })
        let name = app?.bundleIdentifier == bundleID ? app?.localizedName : nil
        let path = app?.bundleIdentifier == bundleID ? app?.bundleURL?.path : nil
        indicator?.show(InputSourceIndicatorContent(
            source: source, bundleID: bundleID,
            appName: name ?? rule?.appName ?? bundleID, appPath: path ?? rule?.appPath
        ))
    }
}
