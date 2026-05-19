import ServiceManagement
import Combine

/// 用 SMAppService.mainApp (macOS 13+) 管理 RMenu 的开机自启状态。
/// 整个 App 一份实例,菜单栏 Toggle 读写 isEnabled。
@MainActor
final class LoginItemManager: ObservableObject {

    @Published private(set) var isEnabled: Bool
    @Published private(set) var lastError: String?

    init() {
        self.isEnabled = Self.queryStatus() == .enabled
    }

    /// 由 UI 调用 — 内部处理 register/unregister 失败,刷新 isEnabled
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        isEnabled = Self.queryStatus() == .enabled
    }

    /// 系统设置里用户可能改了状态,菜单打开时重读
    func refresh() {
        isEnabled = Self.queryStatus() == .enabled
    }

    private static func queryStatus() -> SMAppService.Status {
        SMAppService.mainApp.status
    }
}
