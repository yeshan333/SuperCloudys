import SwiftUI

/// 应用 Logo 是识别内容的一部分，即使系统默认隐藏菜单动作图标也应保留。
struct ApplicationMenuLabel: View {
    let title: String
    let appPath: String
    @ObservedObject private var iconCache = AppIconCache.shared

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(nsImage: iconCache.icon(forPath: appPath))
        }
        .labelStyle(.titleAndIcon)
    }
}
