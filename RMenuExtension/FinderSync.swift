import Cocoa
import FinderSync
import os

class FinderSync: FIFinderSync {

    /// 当前菜单使用的应用列表(每次 menu(for:) 时刷新)
    private var menuApps: [ExternalApp] = []

    /// 缓存:内置应用中已安装的列表(init 时检测一次,避免每次右键重复检测)
    private var cachedBuiltinApps: [ExternalApp] = []

    /// 预构建的菜单快照(后台 utility queue 维护,menu(for:) 主线程读)
    private struct MenuSnapshot {
        let apps: [ExternalApp]
        let icons: [String: NSImage]
        let customAppsMTime: Date?
    }
    private let snapshotLock = NSLock()
    private var snapshot: MenuSnapshot?

    private static let log = Logger(subsystem: "com.yeshan333.RMenu", category: "perf")

    override init() {
        let t0 = Date()
        super.init()
        let t1 = Date()
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/")
        ]
        let t2 = Date()
        cachedBuiltinApps = detectInstalledBuiltinApps()
        let t3 = Date()
        let superMs = (t1.timeIntervalSince(t0)) * 1000
        let dirMs   = (t2.timeIntervalSince(t1)) * 1000
        let detMs   = (t3.timeIntervalSince(t2)) * 1000
        let totMs   = (t3.timeIntervalSince(t0)) * 1000
        Self.log.debug("init breakdown super=\(superMs, format: .fixed(precision: 1))ms dirURLs=\(dirMs, format: .fixed(precision: 1))ms detect=\(detMs, format: .fixed(precision: 1))ms total=\(totMs, format: .fixed(precision: 1))ms apps=\(self.cachedBuiltinApps.count)")
        rebuildSnapshotInBackground()
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
        menuApps = apps

        let menu = NSMenu(title: AppConstants.appName)
        for (index, app) in apps.enumerated() {
            let item = NSMenuItem(
                title: "通过 \(app.name) 打开",
                action: #selector(handleOpenApp(_:)),
                keyEquivalent: ""
            )
            item.tag = index
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
        copyPathItem.image = NSImage(systemSymbolName: "doc.on.doc",
                                     accessibilityDescription: nil)
        menu.addItem(copyPathItem)

        let totalMs = Date().timeIntervalSince(menuStart) * 1000
        Self.log.debug("menu(for:) total=\(totalMs, format: .fixed(precision: 2))ms apps=\(apps.count) snapshotHit=\(snapshotHit)")
        return menu
    }

    // MARK: - Actions

    @objc func handleOpenApp(_ sender: NSMenuItem) {
        let urls = resolveTargetURLs()
        guard !urls.isEmpty else { return }
        let index = sender.tag
        guard index >= 0, index < menuApps.count else { return }
        OpenAppAction.execute(app: menuApps[index], urls: urls)
    }

    @objc func handleCopyPath(_ sender: NSMenuItem) {
        let urls = resolveTargetURLs()
        guard !urls.isEmpty else { return }
        CopyPathAction.execute(urls: urls)
    }

    // MARK: - Snapshot pipeline

    /// 命中时返回快照里的数据;失效时同步构建并触发后台刷新
    private func resolveMenuData() -> ([ExternalApp], [String: NSImage], Bool) {
        let currentMTime = CustomAppStore.fileMTime()

        snapshotLock.lock()
        let snap = snapshot
        snapshotLock.unlock()

        if let snap, snap.customAppsMTime == currentMTime {
            return (snap.apps, snap.icons, true)
        }

        // 降级:同步构建一次,返回结果,同时触发后台重建以命中下一次
        let apps = computeAppList()
        let icons = loadIcons(for: apps)
        rebuildSnapshotInBackground()
        return (apps, icons, false)
    }

    private func rebuildSnapshotInBackground() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let t0 = Date()
            let apps = self.computeAppList()
            let icons = self.loadIcons(for: apps)
            let mtime = CustomAppStore.fileMTime()
            let snap = MenuSnapshot(apps: apps, icons: icons, customAppsMTime: mtime)
            self.snapshotLock.lock()
            self.snapshot = snap
            self.snapshotLock.unlock()
            let ms = Date().timeIntervalSince(t0) * 1000
            Self.log.debug("snapshot rebuilt in \(ms, format: .fixed(precision: 1)) ms apps=\(apps.count)")
        }
    }

    private func computeAppList() -> [ExternalApp] {
        var apps = cachedBuiltinApps
        for custom in CustomAppStore.load() {
            guard !apps.contains(where: { $0.appPath == custom.appPath }) else { continue }
            guard FileManager.default.fileExists(atPath: custom.appPath) else { continue }
            apps.append(ExternalApp(
                name: custom.name,
                bundleID: "",
                appPath: custom.appPath,
                cliNames: []
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
        ExternalApp.allApps.filter { app in
            FileManager.default.fileExists(atPath: app.appPath)
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
