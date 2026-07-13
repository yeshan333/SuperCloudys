import ServiceManagement
import Combine

/// 用 SMAppService.mainApp (macOS 13+) 管理 SuperCloudys 的开机自启状态。
/// 整个 App 一份实例,菜单栏 Toggle 读写 isEnabled。
@MainActor
final class LoginItemManager: ObservableObject {

    @Published private(set) var isEnabled: Bool
    @Published private(set) var lastError: String?
    @Published private(set) var status: SMAppService.Status

    init() {
        let status = Self.queryStatus()
        self.status = status
        self.isEnabled = status == .enabled
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
        refresh()
    }

    /// 系统设置里用户可能改了状态,菜单打开时重读
    func refresh() {
        status = Self.queryStatus()
        isEnabled = status == .enabled
    }

    var statusMessage: String? {
        if let lastError { return "开机自启设置失败：\(lastError)" }
        switch status {
        case .requiresApproval: return "开机自启等待在系统设置中批准"
        case .notFound: return "当前安装位置不支持开机自启"
        default: return nil
        }
    }

    private static func queryStatus() -> SMAppService.Status {
        SMAppService.mainApp.status
    }
}
