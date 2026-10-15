# 易回归问题

维护相关代码时，保留以下行为。本文记录实现约束，真实系统交互仍需按场景复测。

## Dock 应用无法切到前台

后台菜单栏应用只调用 `NSRunningApplication.activate()` 曾出现无法聚焦的情况。当前通过 `NSWorkspace.openApplication` 并设置 `activates = true` 打开或聚焦应用，窗口操作配合辅助功能 API。

相关代码：[DockAppLauncher.swift](../SuperCloudys/Dock/DockAppLauncher.swift)。复测未启动、后台、前台多窗口三种情况。

## 剪贴板方向键跳过条目

列表分组和方向键使用不同顺序会造成跳选。排序统一为固定优先、`lastUsedAt ?? createdAt` 倒序，日期分组也使用同一时间字段。

相关代码：[ClipboardSearch.swift](../SuperCloudys/Clipboard/ClipboardSearch.swift)、[EntryListView.swift](../SuperCloudys/Clipboard/Views/EntryListView.swift)。复测固定条目、跨日期条目，以及使用旧条目后的排序。

## 再次打开面板时搜索框没有焦点

面板隐藏后不会销毁视图，首次出现回调不足以处理再次打开。搜索框同时观察可见状态，并延迟 0.1 秒请求焦点，为窗口切换留出时间。

相关代码：[SearchBarView.swift](../SuperCloudys/Clipboard/Views/SearchBarView.swift)。连续开关面板后直接输入，确认无需点击搜索框。

## 辅助功能未授权时操作无反馈

菜单栏显示权限状态和授权入口。未授权时禁用直接粘贴，保留普通复制和启动应用；Dock 前台窗口轮换降级为隐藏。

相关代码：[MenuBarView.swift](../SuperCloudys/MenuBarView.swift)、[ClipboardHistoryController.swift](../SuperCloudys/Clipboard/ClipboardHistoryController.swift)。授权变更后检查菜单状态及可用操作。

## 浏览器预览命中，编辑器链接仍走原浏览器

规则预览只验证匹配。只有系统将 HTTP/HTTPS 交给 SuperCloudys，才能执行转发；启用步骤见 [README](../README.md#浏览器分流)。目标浏览器列表必须排除 SuperCloudys，避免循环打开。

相关代码：[BrowserRoutingController.swift](../SuperCloudys/BrowserRouting/BrowserRoutingController.swift)。真实验证要从编辑器点击链接，分别检查规则目标和兜底浏览器，不能只看预览结果。

## 设为默认浏览器后 HTML 文件打不开

系统可能同时把 `public.html` 文件关联改为 SuperCloudys。只接收网页 URL 事件会漏掉 Finder 的文件打开事件。

应用委托现在接收文件 URL；本地 `.html`、`.htm`、`.xhtml` 使用兜底浏览器，保持原 URL，不参与网页规则匹配。复测 Finder 双击、一次打开多个文件，以及文件名含空格和中文的情况。
