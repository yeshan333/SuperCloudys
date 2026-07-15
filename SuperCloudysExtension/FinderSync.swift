import Cocoa
import FinderSync
import os

class FinderSync: FIFinderSync, @unchecked Sendable {

    /// 预构建的菜单快照(后台 utility queue 维护,menu(for:) 主线程读)
    private struct MenuSnapshot {
        let apps: [ExternalApp]
        let icons: [String: NSImage]
    }
    private let snapshotLock = NSLock()
    private var snapshot: MenuSnapshot?
    private var isRebuildingSnapshot = false
    private let refreshQueue = DispatchQueue(
        label: "com.yeshan333.SuperCloudys.menu-refresh",
        qos: .utility
    )
    private var customAppsSource: DispatchSourceFileSystemObject?
    private var appsByTag: [Int: ExternalApp] = [:]
    private var tagsByPath: [String: Int] = [:]
    private var nextAppTag = 1

    private static let log = Logger(subsystem: "com.yeshan333.SuperCloudys", category: "perf")
    private static let copyPathIcon = NSImage(
        systemSymbolName: "doc.on.doc",
        accessibilityDescription: nil
    )

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/")
        ]
        rebuildSnapshotInBackground()
        startMonitoringCustomApps()
    }

    deinit {
        customAppsSource?.cancel()
    }

    override func beginObservingDirectory(at url: URL) {
        Self.log.debug("beginObservingDirectory \(url.path, privacy: .public)")
    }

    override func endObservingDirectory(at url: URL) {
        Self.log.debug("endObservingDirectory \(url.path, privacy: .public)")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menuStart = Date()

        let (apps, icons, snapshotHit) = resolveMenuData()

        let menu = NSMenu(title: AppConstants.appName)
        for app in apps {
            let item = NSMenuItem(
                title: "通过 \(app.name) 打开",
                action: #selector(handleOpenApp(_:)),
                keyEquivalent: ""
            )
            item.tag = tag(for: app)
            item.image = icons[app.appPath]
            menu.addItem(item)
        }

        if !apps.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }

        let copyPathItem = NSMenuItem(
            title: "复制路径",
            action: #selector(handleCopyPath(_:)),
            keyEquivalent: ""
        )
        copyPathItem.image = Self.copyPathIcon
        menu.addItem(copyPathItem)

        let totalMs = Date().timeIntervalSince(menuStart) * 1000
        Self.log.debug("menu(for:) total=\(totalMs, format: .fixed(precision: 2))ms apps=\(apps.count) snapshotHit=\(snapshotHit)")
        return menu
    }

    // MARK: - Actions

    @objc func handleOpenApp(_ sender: NSMenuItem) {
        let urls = resolveTargetURLs()
        guard !urls.isEmpty else {
            Self.log.error("Open action has no Finder target")
            return
        }
        guard let app = appsByTag[sender.tag] else {
            Self.log.error("Open action has unknown app tag \(sender.tag)")
            return
        }
        OpenAppAction.execute(app: app, urls: urls)
    }

    @objc func handleCopyPath(_ sender: NSMenuItem) {
        let urls = resolveTargetURLs()
        guard !urls.isEmpty else { return }
        CopyPathAction.execute(urls: urls)
    }

    // MARK: - Snapshot pipeline

    private func tag(for app: ExternalApp) -> Int {
        if let tag = tagsByPath[app.appPath] {
            appsByTag[tag] = app
            return tag
        }
        let tag = nextAppTag
        nextAppTag += 1
        tagsByPath[app.appPath] = tag
        appsByTag[tag] = app
        return tag
    }

    /// 热路径只读内存；自定义应用变更由文件事件在后台刷新。
    private func resolveMenuData() -> ([ExternalApp], [String: NSImage], Bool) {
        snapshotLock.lock()
        let snap = snapshot
        snapshotLock.unlock()

        if let snap {
            return (snap.apps, snap.icons, true)
        }

        // 冷启动只同步解析应用列表；图标由已启动的后台快照任务加载。
        return (computeAppList(), [:], false)
    }

    private func rebuildSnapshotInBackground() {
        snapshotLock.lock()
        guard !isRebuildingSnapshot else {
            snapshotLock.unlock()
            return
        }
        isRebuildingSnapshot = true
        snapshotLock.unlock()

        refreshQueue.async { [weak self] in
            guard let self else { return }
            let t0 = Date()
            let apps = self.computeAppList()
            let icons = self.loadIcons(for: apps)
            _ = Self.copyPathIcon
            let snap = MenuSnapshot(apps: apps, icons: icons)
            self.snapshotLock.lock()
            self.snapshot = snap
            self.isRebuildingSnapshot = false
            self.snapshotLock.unlock()
            let ms = Date().timeIntervalSince(t0) * 1000
            Self.log.debug("snapshot rebuilt in \(ms, format: .fixed(precision: 1)) ms apps=\(apps.count)")
        }
    }

    private func startMonitoringCustomApps() {
        refreshQueue.async { [weak self] in
            self?.monitorCustomAppsFile()
        }
    }

    private func monitorCustomAppsFile() {
        customAppsSource?.cancel()

        let fileURL = CustomAppStore.fileURL
        let fileDescriptor = open(fileURL.path, O_EVTONLY)
        if fileDescriptor == -1 {
            monitorCustomAppsDirectory(fileURL.deletingLastPathComponent())
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: refreshQueue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = self.customAppsSource?.data
            self.rebuildSnapshotInBackground()
            if events?.contains(.delete) == true || events?.contains(.rename) == true {
                self.monitorCustomAppsFile()
            }
        }
        source.setCancelHandler { close(fileDescriptor) }
        source.resume()
        customAppsSource = source
    }

    private func monitorCustomAppsDirectory(_ directoryURL: URL) {
        let fileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard fileDescriptor != -1 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: refreshQueue
        )
        source.setEventHandler { [weak self] in
            guard FileManager.default.fileExists(atPath: CustomAppStore.fileURL.path) else {
                return
            }
            self?.monitorCustomAppsFile()
            self?.rebuildSnapshotInBackground()
        }
        source.setCancelHandler { close(fileDescriptor) }
        source.resume()
        customAppsSource = source
    }

    private func computeAppList() -> [ExternalApp] {
        var apps = detectInstalledBuiltinApps()
        for custom in CustomAppStore.load() {
            let appPath = custom.bundleID.flatMap {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path
            } ?? custom.appPath
            guard !apps.contains(where: { existing in
                existing.appPath == appPath
                    || (custom.bundleID.map { $0 == existing.bundleID } ?? false)
            }) else { continue }
            guard FileManager.default.fileExists(atPath: appPath) else { continue }
            apps.append(ExternalApp(
                name: custom.name,
                bundleID: custom.bundleID ?? "",
                appPath: appPath
            ))
        }
        return apps
    }

    private func loadIcons(for apps: [ExternalApp]) -> [String: NSImage] {
        var icons: [String: NSImage] = [:]
        for app in apps {
            guard FileManager.default.fileExists(atPath: app.appPath) else { continue }
            let icon = NSWorkspace.shared.icon(forFile: app.appPath)
            icon.size = NSSize(width: 16, height: 16)
            icons[app.appPath] = icon
        }
        return icons
    }

    // MARK: - Helpers

    private func detectInstalledBuiltinApps() -> [ExternalApp] {
        ExternalApp.allApps.compactMap { app in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
                ?? (FileManager.default.fileExists(atPath: app.appPath)
                    ? URL(fileURLWithPath: app.appPath)
                    : nil)
            guard let url else { return nil }
            return ExternalApp(name: app.name, bundleID: app.bundleID, appPath: url.path)
        }
    }

    private func resolveTargetURLs() -> [URL] {
        if let selected = FIFinderSyncController.default().selectedItemURLs(),
           !selected.isEmpty {
            return selected
        }
        if let targeted = FIFinderSyncController.default().targetedURL() {
            return [targeted]
        }
        return []
    }
}
