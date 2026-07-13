import Cocoa
import FinderSync
import os

class FinderSync: FIFinderSync, @unchecked Sendable {

    /// 预构建的菜单快照(后台 utility queue 维护,menu(for:) 主线程读)
    private struct MenuSnapshot {
        let apps: [ExternalApp]
        let icons: [String: NSImage]
        let customAppsMTime: Date?
        let createdAt: Date
    }
    private let snapshotLock = NSLock()
    private var snapshot: MenuSnapshot?
    private var isRebuildingSnapshot = false

    private static let log = Logger(subsystem: "com.yeshan333.SuperCloudys", category: "perf")

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/")
        ]
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

        let menu = NSMenu(title: AppConstants.appName)
        for app in apps {
            let item = NSMenuItem(
                title: "通过 \(app.name) 打开",
                action: #selector(handleOpenApp(_:)),
                keyEquivalent: ""
            )
            item.representedObject = [
                "name": app.name,
                "bundleID": app.bundleID,
                "appPath": app.appPath
            ]
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
        guard let value = sender.representedObject as? [String: String],
              let name = value["name"], let bundleID = value["bundleID"],
              let appPath = value["appPath"] else { return }
        OpenAppAction.execute(
            app: ExternalApp(name: name, bundleID: bundleID, appPath: appPath),
            urls: urls
        )
    }

    @objc func handleCopyPath(_ sender: NSMenuItem) {
        let urls = resolveTargetURLs()
        guard !urls.isEmpty else { return }
        CopyPathAction.execute(urls: urls)
    }

    // MARK: - Snapshot pipeline

    /// 命中时返回快照；失效时先返回旧快照并后台刷新，仅冷启动同步构建。
    private func resolveMenuData() -> ([ExternalApp], [String: NSImage], Bool) {
        let currentMTime = CustomAppStore.fileMTime()

        snapshotLock.lock()
        let snap = snapshot
        snapshotLock.unlock()

        if let snap, snap.customAppsMTime != currentMTime {
            let apps = computeAppList()
            rebuildSnapshotInBackground()
            return (apps, snap.icons, false)
        }

        if let snap,
           snap.customAppsMTime == currentMTime,
           Date().timeIntervalSince(snap.createdAt) < 60 {
            return (snap.apps, snap.icons, true)
        }

        if let snap {
            rebuildSnapshotInBackground()
            return (snap.apps, snap.icons, false)
        }

        // 冷启动只同步解析应用列表；图标由已启动的后台快照任务加载。
        let apps = computeAppList()
        rebuildSnapshotInBackground()
        return (apps, [:], false)
    }

    private func rebuildSnapshotInBackground() {
        snapshotLock.lock()
        guard !isRebuildingSnapshot else {
            snapshotLock.unlock()
            return
        }
        isRebuildingSnapshot = true
        snapshotLock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let t0 = Date()
            let apps = self.computeAppList()
            let icons = self.loadIcons(for: apps)
            let mtime = CustomAppStore.fileMTime()
            let snap = MenuSnapshot(
                apps: apps,
                icons: icons,
                customAppsMTime: mtime,
                createdAt: Date()
            )
            self.snapshotLock.lock()
            self.snapshot = snap
            self.isRebuildingSnapshot = false
            self.snapshotLock.unlock()
            let ms = Date().timeIntervalSince(t0) * 1000
            Self.log.debug("snapshot rebuilt in \(ms, format: .fixed(precision: 1)) ms apps=\(apps.count)")
        }
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
