import AppKit
import Combine
import SwiftUI
import XCTest
@testable import SuperCloudys

final class DockMenuIconTests: XCTestCase {
    @MainActor
    func testDockMenuShowsImageBeforeLoadingAndApplicationLogoAfterLoading() async throws {
        guard #available(macOS 14.4, *) else {
            throw XCTSkip("原生菜单渲染验证需要 NSHostingMenu（macOS 14.4+）")
        }
        let path = Bundle.main.bundleURL.path
        let monitor = DockMonitor(apps: [DockApp(
            name: "图标测试", bundleID: "test.icon", appPath: path, shortcutLabel: "1"
        )])
        let menu = NSHostingMenu(rootView: DockAppsSection(monitor: monitor))
        menu.update()
        let item = try XCTUnwrap(menu.items.first { $0.title.contains("图标测试") })
        XCTAssertNotNil(item.image, "首次打开菜单也应有占位图标")
        if #available(macOS 27.0, *) {
            XCTAssertEqual(item.preferredImageVisibility, .visible,
                           "macOS 27 默认隐藏菜单图片，应用图标必须明确指定显示")
        }

        let loaded = expectation(description: "后台图标加载通知菜单刷新")
        let subscription = AppIconCache.shared.objectWillChange.first().sink { loaded.fulfill() }
        _ = AppIconCache.shared.icon(forPath: path)
        await fulfillment(of: [loaded], timeout: 5)
        withExtendedLifetime(subscription) {}
        menu.update()
        let updated = try XCTUnwrap(menu.items.first { $0.title.contains("图标测试") })
        let icon = try XCTUnwrap(updated.image)
        XCTAssertEqual(icon.size, NSSize(width: 16, height: 16))
        XCTAssertTrue(icon.isValid)
        if #available(macOS 27.0, *) {
            XCTAssertEqual(updated.preferredImageVisibility, .visible,
                           "异步替换占位图后也必须保留显示策略")
        }
    }

    @MainActor
    func testApplicationLogoRemainsVisibleInsideDefaultOpenSubmenuOnMacOS27() throws {
        guard #available(macOS 27.0, *) else {
            throw XCTSkip("菜单图片自动隐藏策略仅适用于 macOS 27+")
        }
        let menu = NSHostingMenu(rootView: Menu("文件默认打开应用") {
            Button {} label: {
                ApplicationMenuLabel(title: ".txt → 测试应用", appPath: "")
            }
        })
        menu.update()
        let submenu = try XCTUnwrap(menu.items.first?.submenu)
        submenu.update()
        let item = try XCTUnwrap(submenu.items.first)
        XCTAssertEqual(item.title, ".txt → 测试应用")
        XCTAssertNotNil(item.image)
        XCTAssertEqual(item.preferredImageVisibility, .visible,
                       "默认打开应用的子菜单也必须明确显示应用图标")
    }

}
