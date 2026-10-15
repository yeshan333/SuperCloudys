# 仓库开发约定

SuperCloudys 是 macOS 14+ 菜单栏工具，使用 Swift 5.9、SwiftUI 和 AppKit。界面文字和注释使用简体中文。

## 开始修改前

- 用户功能和默认行为以 [README](README.md) 为入口。
- 构建、安装、测试和发布命令见[开发说明](docs/development.md)。先运行 `xcodegen generate`，项目配置只改 `project.yml`。
- 查看[易回归问题](docs/BUG_FIX_RECORDS.md)；修改功能后同步对应文档，不把计划中的功能写成已实现。

## 架构

`project.yml` 定义三个目标：非沙盒主应用 `SuperCloudys`、沙盒 Finder 扩展 `SuperCloudysExtension`、测试宿主目标 `SuperCloudysTests`。`Shared/` 编译进主应用和扩展。

主应用入口是 `SuperCloudys/SuperCloudysApp.swift`，管理菜单栏、生命周期和 URL 事件。功能分别位于 `Dock/`、`InputSource/`、`BrowserRouting/`、`Clipboard/`；通用服务位于 `Services/`，菜单组件位于 `MenuBar/`。

## 修改时保留的约束

- Finder 扩展在后台刷新菜单快照，菜单回调不做文件或应用解析 I/O。打开文件通过 URL 事件交给主应用执行。
- Dock 配置通过文件系统事件监听；应用输入法通过前台应用事件切换，避免增加轮询。
- 浏览器分流依赖系统默认 HTTP/HTTPS 处理应用注册。规则预览与系统注册分开；目标和兜底浏览器始终排除 SuperCloudys，防止循环。
- 剪贴板采集、图片处理和搜索在后台执行。持久化与恢复约束见[剪贴板实现说明](docs/clipboard-history-design.md)。
- 自定义应用配置位于 `~/Library/Application Support/SuperCloudys/custom_apps.json`，由主应用和扩展共享。
- 本地安装使用稳定签名身份；公开发布使用 Developer ID。不要把本地自签证书用于分发。
- 测试宿主跳过常驻监听和快捷键注册。会改变真实系统输入法或显示浮层的检查需显式启用，见开发说明。
