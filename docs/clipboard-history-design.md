# SuperCloudys 剪贴板历史功能设计

## 概述

本文档为 `SuperCloudys` macOS 菜单栏应用提出剪贴板历史功能方案。目标环境：

- macOS 14+
- `LSUIElement = true`（纯后台应用，无 Dock 图标）
- 基于 `MenuBarExtra` 的主界面
- 无 App Sandbox
- 已有基于 Carbon `RegisterEventHotKey` 的全局快捷键（`Cmd+1` ~ `Cmd+0`）

目标是添加一个原生、注重隐私的剪贴板历史系统，速度够快适合日常使用，并为未来 Raycast 级别的功能留有扩展空间。

## 设计目标

- 捕获常见内容类型：文本、富文本、链接、图片、文件、颜色
- 以键盘优先的浮动窗口呈现历史
- 支持搜索、置顶、预览、复制回剪贴板、粘贴到前台应用
- 通过应用排除列表、敏感类型过滤、保留策略保护隐私
- 作为长时间运行的后台应用，保持内存可控

## 首版非目标

- 跨设备剪贴板同步
- OCR、二维码识别、AI 操作或内容转换
- 所有 pasteboard flavor 的完美富文档往返
- 所有边界情况下的完美来源应用归属

---

## 1. Raycast 剪贴板历史功能分析

Raycast 是一个很好的参照，因为它将广泛的格式支持与启动器风格的搜索 UI 结合在一起。

### 核心行为

Raycast 剪贴板历史保持复制项的滚动记录，并通过可搜索的命令窗口暴露。它追踪：

- 文本
- 图片
- 文件
- 链接
- 邮件
- 颜色

它还保留原始复制格式，因此单个逻辑历史条目可以携带多种 pasteboard 表示（纯文本、富文本、RTF、HTML）。这是一个重要的实现细节：剪贴板管理器应避免过早扁平化富内容。

### 搜索和过滤

Raycast 支持：

- 全文搜索
- 类型过滤
- 条目重命名以便检索

类型过滤很重要，因为剪贴板历史会很快变得嘈杂。用户通常在记住具体内容之前就知道他们在找链接、图片还是文件。对 SuperCloudys 意味着：

- 顶部搜索栏
- 可选的类型过滤标签/键盘快捷过滤
- 对显示文本和元数据进行搜索索引

### 置顶（Pin）

置顶条目是与普通历史不同的行为类别：

- 始终显示在顶部
- 在清除操作中保留
- 作为轻量级片段或收藏使用

对 SuperCloudys，置顶应作为一等公民的元数据建模，而非特殊列表。这简化了排序、持久化和保留逻辑。

### 预览

Raycast 提供条目特定的预览和操作：

- 文本可查看和编辑
- 图片可预览和处理
- 链接显示可视化元数据
- 文件可附加或复制回

SuperCloudys 的预览应务实：

- 文本/富文本：多行预览
- 图片：缩略图 + 原始尺寸信息
- 文件：图标列表 + 文件名和路径
- 链接：URL + 标题（从粘贴内容可推导的，MVP 阶段不网络获取）
- 颜色：色块 + hex/RGB 字符串

### 键盘快捷键

Raycast 强调快捷键驱动：

- 全局快捷键打开剪贴板历史
- Return 粘贴或复制
- 键盘操作支持置顶、重命名、删除、批量删除、类型过滤

核心要求是：剪贴板历史只有在调用和选择都低摩擦时才有用。SuperCloudys 已使用 Carbon 快捷键，新功能使用 `Ctrl+H` 作为全局快捷键，集成到同一全局快捷键注册模型中。

### 从历史粘贴

Raycast 支持：

- 复制到剪贴板（Copy to Clipboard）
- 粘贴到活跃应用（Paste to Active App）

"复制回"更简单可靠。"粘贴到活跃应用"更快但需要额外机制：

- 恢复剪贴板内容
- 重新激活之前的前台应用
- 模拟 `Cmd+V`
- 可能需要辅助功能（Accessibility）权限

SuperCloudys 应同时提供两种操作。MVP 阶段以"复制回"为安全基线，"立即粘贴"作为获得 Accessibility 权限时的增强路径。

### 清除历史

Raycast 支持：

- 删除单个条目
- 按时间窗口批量删除
- 清除所有
- 区分置顶和未置顶条目

推荐行为：

- `清除未置顶历史`
- `清除所有历史`

### 隐私控制

Raycast 明确支持禁用应用，包括常见密码工具。这是核心产品需求，不是锦上添花。

推荐隐私功能集：

- 按 Bundle ID 排除应用
- 内置已知敏感应用的默认排除
- 忽略临时或隐藏的 pasteboard 类型
- 可选保留期限
- 手动"暂停记录"

---

## 2. macOS 剪贴板 API（Swift）

### 主要 API

- `NSPasteboard.general`
- `changeCount` — 每次 pasteboard 所有权变更时递增
- `pasteboardItems`
- `types`
- `string(forType:)` / `data(forType:)`
- `readObjects(forClasses:options:)`
- `clearContents()` / `writeObjects(_:)`

### 基于 changeCount 的轮询

macOS 没有广泛可靠的剪贴板变更回调 API。基于定时器的轮询 `changeCount` 是标准做法。

典型流程：

1. 存储上次 `changeCount`
2. 每 ~500ms 轮询
3. 若 `changeCount` 变化，检查 `pasteboardItems`
4. 解码当前内容为内部模型
5. 过滤/去重后持久化

```swift
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount: Int

    init() {
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return }
        handlePasteboardItems(items)
    }
}
```

### 处理不同 Pasteboard 类型

`NSPasteboard.PasteboardType` 包括：

- `.string` — 纯文本
- `.rtf` / `.rtfd` / `.html` — 富文本
- `.png` / `.tiff` — 图片
- `.fileURL` — 文件引用
- `.URL` — 网页链接
- `.color` — 颜色
- `.pdf` — PDF

剪贴板管理器应当：

- 按稳定优先级顺序偏好已知类型
- 保留所有可用的原始表示以供后续重粘贴
- 根据配置忽略敏感或临时的自定义类型

### 读取文本

```swift
// 纯文本
if let text = pasteboard.string(forType: .string) { /* ... */ }

// 富文本
let rtfData = pasteboard.data(forType: .rtf)
if let rtfData,
   let attributed = try? NSAttributedString(
       data: rtfData,
       options: [.documentType: NSAttributedString.DocumentType.rtf],
       documentAttributes: nil) {
    let plainFallback = attributed.string
}
```

### 读取图片

```swift
if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
   let image = images.first {
    // 持久化时写入 PNG/TIFF 到磁盘 + 生成缩略图
}
```

### 读取文件

```swift
if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
    let fileURLs = urls.filter { $0.isFileURL }
    // 多个文件应作为单个分组条目存储
}
```

### 读取 URL

```swift
if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
   let firstURL = urls.first, !firstURL.isFileURL {
    // 网页 URL
}
```

### 读取颜色

```swift
if let colors = pasteboard.readObjects(forClasses: [NSColor.self], options: nil) as? [NSColor],
   let color = colors.first {
    // 转换为 sRGB 并存储 hex/RGBA
}
```

### 编程式粘贴

macOS 没有"粘贴到前台应用"的高层 API。通用做法：

1. 将选中条目写回 `NSPasteboard.general`
2. 重新激活之前的前台应用
3. 通过 `CGEvent` 合成 `Cmd+V`

```swift
import Carbon.HIToolbox

enum PasteSimulator {
    static func pasteCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
```

重要约束：

- 通常需要 Accessibility 权限
- 时序很重要，目标应用必须先被激活
- 若剪贴板管理器在粘贴期间更新了 pasteboard，会触发自身的监听器（需要抑制机制）

---

## 3. 架构设计

### 设计概要

推荐架构：

- `ClipboardMonitorService` — 轮询 `NSPasteboard.general.changeCount`
- `ClipboardDecoder` — 将 pasteboard items 转换为类型化领域对象
- `ClipboardStore` — 持久化条目并服务查询
- `ClipboardHistoryController` — 协调监听、抑制、去重和粘贴操作
- `ClipboardPanelController` — 托管浮动 `NSPanel`
- SwiftUI 视图 — 渲染搜索、列表、预览和设置

### 实际模块布局

```
SuperCloudys/Clipboard/
├── ClipboardEntry.swift              # 数据模型（含指纹去重）
├── ClipboardMonitorService.swift     # 轮询服务 + 内容解码
├── ClipboardStore.swift              # JSON 持久化（防抖写入）
├── ClipboardHistoryController.swift  # 业务协调（@MainActor）
├── ClipboardPanelController.swift    # NSPanel 管理
├── ClipboardHotkeyManager.swift      # Carbon Ctrl+H 全局快捷键
├── ClipboardSettings.swift           # 设置/隐私配置
└── Views/
    ├── ClipboardHistoryView.swift    # 主视图
    ├── SearchBarView.swift           # 搜索栏
    ├── EntryListView.swift           # 左侧历史列表
    ├── DetailPanelView.swift         # 右侧预览+信息面板
    └── BottomBarView.swift           # 底部操作栏
```

### 数据模型

```swift
enum ClipboardContentType: String, Codable, CaseIterable {
    case text
    case richText
    case url
    case fileGroup
    case image
    case color
    case unknown
}

struct ClipboardEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let contentType: ClipboardContentType
    let plainText: String?          // 可搜索的纯文本
    let title: String               // 一行显示文本
    let subtitle: String?           // 元数据（主机名、文件数、尺寸等）
    let createdAt: Date
    let sourceAppBundleID: String?  // 来源应用（用于排除规则）
    let sourceAppName: String?
    var isPinned: Bool
    var lastUsedAt: Date?
    let fingerprint: String         // 去重键（djb2 哈希）
    let imagePath: String?          // 图片原图路径
    let thumbnailPath: String?      // 缩略图路径
    let filePaths: [String]?        // 文件路径列表
    let colorHex: String?           // 颜色 hex 值
}
```

### 指纹与去重

去重策略：

- 按逻辑类型 + 标准化负载计算指纹
- 新条目与最近未置顶条目比较
- 若指纹相同且在短时间窗口内，更新时间戳而非插入新行
- 不对置顶条目进行去重

### 来源应用归属

```swift
let frontmost = NSWorkspace.shared.frontmostApplication
let bundleID = frontmost?.bundleIdentifier
let appName = frontmost?.localizedName
```

这是推断而非精确事实，但足以用于应用排除和显示。

### 存储策略

**实际采用：JSON 文件持久化（防抖写入）**

选择 JSON 而非 SQLite 的理由：

- MVP 阶段条目数量有限（默认上限 500 条），JSON 足够高效
- 无需引入第三方依赖（GRDB）
- 实现简单，调试方便
- 通过防抖写入（2 秒合并）避免频繁磁盘 I/O

存储布局：

```
~/Library/Application Support/SuperCloudys/
├── clipboard_history.json        # 条目数组（ISO 8601 日期编码）
└── ClipboardAssets/              # 图片原图 + 缩略图
```

写入策略：

- `scheduleSave()` 取消前一次未执行的写入，延迟 2 秒后在后台队列原子写入
- `flush()` 立即写入（用于测试和应用退出）
- NSLock 保护 entries 数组的线程安全

### 剪贴板监听服务

自写抑制采用**时间窗口方式**（1 秒），而非单次 changeCount+1。原因：`clearContents()` + `writeObjects()` 会递增 changeCount 两次，基于计数的方式无法可靠覆盖。

```swift
final class ClipboardMonitorService {
    private var suppressUntil: Date?

    func markSelfWrite() {
        suppressUntil = Date().addingTimeInterval(1.0)
    }

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        defer { lastChangeCount = current }

        if let until = suppressUntil, Date() < until {
            return
        }
        suppressUntil = nil
        // 解码、过滤、去重、通知 delegate
    }
}
```

解码优先级：URL（非文件）> 文件 URL > 颜色 > 图片 > 文本。图片原图同步写入磁盘确保路径立即有效，缩略图通过 Core Graphics 在专用串行队列异步生成。

### UI 方案

`MenuBarExtra` 适合设置和快速操作，但不适合 Raycast 风格的可搜索历史浏览器。剪贴板 UI 应使用独立的浮动面板。

推荐 UI 技术栈：

- `NSPanel` — 启动器风格的历史窗口
- `NSVisualEffectView` — 背景毛玻璃模糊效果（深色半透明）
- `NSHostingView` + SwiftUI 内容
- 复用已有 Carbon 全局快捷键基础设施（`Ctrl+H` 触发）

面板特性：

- 非激活或实用工具级浮动行为
- 屏幕居中呈现
- 键盘焦点直接进入搜索框
- `ESC` 关闭
- 方向键导航
- `Return` 粘贴到前台应用

为什么选 `NSPanel` 而非纯 SwiftUI Window Scene：

- 更好的层级和激活控制
- 更贴近启动器/剪贴板管理器 UX
- 在 `LSUIElement` 应用中更易保持轻量级瞬态窗口

### UI 布局详细设计

面板采用**三区域垂直布局**：顶部搜索栏、中部主内容区（左右分栏）、底部操作栏。

```
┌─────────────────────────────────────────────────────────────────┐
│  ← │ Type to filter entries...          │ [All Types ▾]         │  ← 顶部搜索栏
├──────────────────────────┬──────────────────────────────────────┤
│  Today                   │                                      │
│  ┌────────────────────┐  │  git -C build/tadpole clean -fdx     │  ← 内容预览区
│  │📄 git -C build/... │  │                                      │
│  └────────────────────┘  │                                      │
│  📎 https://software...  │                                      │
│  📄 clipboard history... │                                      │
│  📄 AI 生成用例方案...    │──────────────────────────────────────│
│  📎 https://gallery....  │  Information                         │  ← 信息面板
│  📄 /your-new-tab        │  ─────────────────────────────────── │
│  📄 ENV http_proxy=...   │  Source          [icon] Warp         │
│  📎 https://shansan...   │  Content type              Text      │
│  📎 https://pagespeed... │  Characters                  31      │
│                          │  Words                        6      │
│                          │  Copied at     Today at 11:00 PM     │
├──────────────────────────┴──────────────────────────────────────┤
│  🔴 Clipboard History    │  Paste to App  ↵ │ Actions │ ⌘ K    │  ← 底部操作栏
└─────────────────────────────────────────────────────────────────┘
```

#### 顶部搜索栏

- **返回按钮**（`←`）：回到上级或关闭面板
- **搜索输入框**：占据主要宽度，placeholder "Type to filter entries..."
- **类型过滤下拉**（右侧）："All Types" 下拉菜单，可选 Text / URL / Image / File / Color

#### 中部主内容区（左右分栏）

**左侧：历史列表**

- 宽度约占面板 40%
- 按时间分组显示（Today / Yesterday / Earlier）
- 每个条目一行：类型图标 + 内容摘要（单行截断，带省略号）
- 类型图标：📄 文本、📎 链接、🖼️ 图片、📁 文件、🎨 颜色
- 选中条目高亮背景
- 支持方向键上下导航
- 支持鼠标点击选择

**右侧：预览 + 信息面板**

右侧垂直分为两个区域：

1. **内容预览区**（上半部分）
   - 文本：显示完整文本内容（可滚动），等宽字体
   - 图片：缩略图居中展示
   - URL：显示完整 URL 文本
   - 文件：文件图标 + 路径列表
   - 颜色：大色块 + hex/RGB 值

2. **Information 信息面板**（下半部分）
   - 带分隔线的键值对列表
   - **Source**：来源应用图标 + 应用名（如 "Warp"、"Chrome"、"Finder"）
   - **Content type**：内容类型（Text / URL / Image / File / Color）
   - **Characters**：字符数（仅文本/URL 类型）
   - **Words**：词数（仅文本类型）
   - **Copied at**：复制时间（相对时间，如 "Today at 11:00 PM"）
   - **Size**：数据大小（仅图片/文件类型，如 "2.3 MB"）
   - **Dimensions**：图片尺寸（仅图片类型，如 "1920 × 1080"）

#### 底部操作栏

- **左侧**：应用图标 + "Clipboard History" 标题
- **右侧操作区**：
  - **主操作按钮**："Paste to [App]" + `↵` 快捷键提示（粘贴到之前的前台应用）
  - **Actions 菜单**：展开更多操作（复制、置顶、删除、清除历史）
  - **快捷键提示**：`⌃H`（全局唤起快捷键）

#### 面板内键盘快捷键

| 快捷键 | 操作 |
|--------|------|
| `↑` / `↓` | 上下移动选择 |
| `Return` | 粘贴选中条目到前台应用 |
| `⌘+C` | 仅复制到剪贴板（不粘贴） |
| `⌘+.` | 置顶/取消置顶 |
| `⌘+K` | 打开 Actions 菜单 |
| `Delete` / `⌘+⌫` | 删除选中条目 |
| `Esc` | 关闭面板 |
| 直接输入 | 开始搜索（焦点自动进入搜索框） |

#### 面板尺寸与样式

- 默认尺寸：宽 780pt × 高 500pt
- 圆角：12pt
- 背景：`NSVisualEffectView`（`.hudWindow` 或 `.popover` material，深色模式）
- 无标题栏（`styleMask: [.borderless]`）
- 阴影：系统默认 NSPanel 阴影
- 层级：`NSWindow.Level.floating`

### 搜索设计

推荐分阶段方案：

- 内存过滤：适用于 ~1,000-3,000 条目
- SQLite 索引查询：超出内存范围时使用
- FTS5：仅在历史量大或需要排名时引入（Phase 2）

搜索目标：`plainText`、`title`、标准化 URL、文件名/路径、来源应用名

### 内存管理

长时间运行的后台进程需注意：

- 图片存为文件，而非在内存中保持 `NSImage` 实例
- 摄入时一次性生成缩略图
- 仅对可见行和选中条目懒加载预览资源
- 仅在内存中保留最近的元数据，旧行按需从存储分页
- 在大型解码/写入路径周围使用 `autoreleasepool`

图片摄入策略：

- 标准化为 PNG 或 TIFF
- 缩略图尺寸上限 320px
- 可选拒绝或降采样超大图片

### 隐私控制

必要的隐私设计：

- 按 Bundle ID 禁用应用
- 默认排除的敏感应用（内置）
- 忽略临时和隐藏的 pasteboard 类型
- 自动过期历史
- 手动清除控制

默认排除的 Bundle ID：

- `com.apple.keychainaccess`
- `com.1password.1password`
- `com.agilebits.onepassword7`
- `com.bitwarden.desktop`
- `com.lastpass.LastPass`
- `com.apple.Passwords`

应忽略的 pasteboard 类型/标记：

- `org.nspasteboard.TransientType`
- `org.nspasteboard.ConcealedType`
- `org.nspasteboard.AutoGeneratedType`
- `com.agilebits.onepassword`
- `com.apple.is-remote-clipboard`（可选忽略 Universal Clipboard）

保留期限选项：1 天 / 1 周 / 1 月 / 3 月 / 无限

### 与现有快捷键集成

现有 `Cmd+1...0` 已用于 Dock 应用快捷键。剪贴板历史需要单独的调用快捷键。

**全局快捷键：`Ctrl+H`**

- 按下 `Ctrl+H` 打开/关闭剪贴板历史面板
- 不与现有 `Cmd+1...0` 冲突
- 简短易记，符合"History"语义
- 避免与 macOS 系统快捷键 `Cmd+H`（隐藏窗口）冲突

实现方向：

- 扩展当前 `DockShortcutManager` 或引入通用快捷键注册表
- 面板内的快捷操作保持在面板作用域内，不扩展全局快捷键

---

## 4. 关键技术挑战

### 1. changeCount 轮询是唯一普遍可靠的触发方式

没有更干净的通用剪贴板历史事件 API。轮询虽标准且可接受，但引入：

- CPU 唤醒
- 潜在竞态条件
- 需要去重
- 需要抑制自生成的 pasteboard 写入

结论：每 0.5 秒轮询是正确的基线。

### 2. 大图片存储和缩略图生成

风险：

- 巨大截图
- 相似图片重复复制
- 每次列表渲染的昂贵图片解码

缓解：

- 写入原始图片到资源存储
- 摄入时生成并缓存缩略图
- 存储尺寸和字节大小元数据
- 懒加载预览
- 应用保留策略和可选大小上限

### 3. 去重

挑战：

- 相同可见字符串但不同富负载
- 相同 URL 不同元数据
- 相同图片多次复制

缓解：

- 按逻辑类型 + 标准化负载计算指纹
- 仅与最近条目比较（廉价的插入时去重）
- 保留用户显式操作（置顶、重命名）

### 4. 粘贴模拟

风险：

- 需要 Accessibility 权限
- 时序失败
- 错误应用接收粘贴
- 敏感应用可能阻止或清理输入

缓解：

- 同时提供 `复制` 和 `粘贴` 操作
- 检测权限状态并优雅降级
- 重新激活前台应用后使用小延迟（~80ms）

### 5. 临时 Pasteboard 条目

风险：

- 捕获用户不期望持久化的秘密

缓解：

- 尊重 concealed/transient 标记
- 维护应用黑名单
- 考虑"暂停捕获"模式

### 6. Accessibility 权限

- 剪贴板捕获本身**不需要** Accessibility
- "粘贴到活跃应用"通常**需要**
- 设置 UI 应解释为何需要此权限

现有代码已包含 Accessibility 相关辅助代码（用于窗口管理），可复用。

---

## 5. 开源参考

### Maccy

- 仓库：https://github.com/p0deje/Maccy
- 相关模式：定时器轮询（500ms）、置顶、Accessibility 粘贴、忽略 transient/concealed 类型、密码管理器类型过滤、键盘优先历史窗口
- 与 SuperCloudys 最接近的产品类别和现代 macOS 目标

### Clipy

- 仓库：https://github.com/Clipy/Clipy
- 相关模式：菜单栏结构、片段扩展、长时间运行后台架构
- 展示了菜单栏剪贴板工具如何从原始历史扩展到可复用片段和操作

### CopyClip

- 参考：https://copyclip.app/
- 相关模式：原生菜单栏呈现、搜索优先、收藏/置顶、快捷键粘贴、本地存储隐私
- 更接近 SuperCloudys 作为精品菜单栏工具的定位

### 共同模式总结

- 轮询 `changeCount`
- 保持紧凑的本地元数据索引
- 特殊对待图片
- 保持 UI 键盘优先
- 隐私设置可见，不深埋

---

## 6. MVP 范围 vs 完整功能集

### MVP 范围

聚焦可靠的基础：

- [x] 通过 `changeCount` 轮询捕获剪贴板
- [x] 捕获文本、URL、文件、图片、颜色
- [x] 在浮动 `NSPanel` 中列出最近历史
- [x] 按文本和文件名/URL 搜索
- [x] 置顶/取消置顶
- [x] 复制选中条目回剪贴板
- [x] 可选"粘贴到前台应用"（需 Accessibility 权限）
- [x] 清除单个条目 / 清除未置顶 / 清除所有
- [x] 按 Bundle ID 的应用排除列表
- [x] 保留策略（自动过期）
- [x] 图片缩略图存储到磁盘

### 延后的完整功能集

- 保留并选择原始 pasteboard 表示
- `粘贴为纯文本`
- `粘贴为原始富文本`
- 条目重命名
- 按时间窗口批量删除
- UI 中的类型过滤器
- 片段转换
- 暂停记录
- 忽略下一次复制
- Universal Clipboard 过滤开关
- 图片 OCR
- 链接元数据预览
- 顺序粘贴工作流

---

## 实现备注

### 推荐条目生命周期

1. 轮询 pasteboard
2. `changeCount` 变化则检查 items
3. 从 `NSWorkspace.shared.frontmostApplication` 推断来源应用
4. 应用排除/隐私过滤
5. 解码为 `ClipboardEntry`
6. 计算指纹
7. 与最近历史去重
8. 持久化元数据和负载
9. 向 UI 发布更新

### 推荐面板工作流

1. `Ctrl+H` 打开面板，记录当前前台应用
2. 搜索框自动获焦，可直接输入过滤
3. 方向键上下移动选择，右侧实时更新预览和 Information
4. `Return` 粘贴选中条目到之前的前台应用
5. `Cmd+C` 仅复制到剪贴板不粘贴
6. `Cmd+.` 置顶/取消置顶条目
7. `Cmd+K` 打开 Actions 菜单（更多操作）
8. `Delete` 删除条目
9. `Esc` 关闭面板

### 粘贴流程

1. 打开面板前保存当前前台应用
2. 用户选择条目
3. 写入负载到 `NSPasteboard.general`
4. 监听器抑制自写
5. 重新激活之前的应用
6. 若选择粘贴模式且已授权，合成 `Cmd+V`

```swift
@MainActor
final class ClipboardActionController {
    private var previousApp: NSRunningApplication?
    private let pasteboard = NSPasteboard.general

    func rememberFrontmostApp() {
        previousApp = NSWorkspace.shared.frontmostApplication
    }

    func restore(_ entry: ClipboardEntry, monitor: ClipboardMonitorService, paste: Bool) {
        monitor.markSelfWrite()
        write(entry)

        guard paste, let previousApp else { return }
        previousApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            PasteSimulator.pasteCommandV()
        }
    }

    private func write(_ entry: ClipboardEntry) {
        pasteboard.clearContents()
        switch entry.payloadRef {
        case .fileList(let urls):
            pasteboard.writeObjects(urls as [NSURL])
        case .color(let hex, _):
            pasteboard.setString(hex, forType: .string)
        case .inlineData:
            if let text = entry.plainText {
                pasteboard.setString(text, forType: .string)
            }
        case .fileURL(let url):
            pasteboard.writeObjects([url as NSURL])
        case .imageAsset(let originalURL, _):
            if let image = NSImage(contentsOf: originalURL) {
                pasteboard.writeObjects([image])
            }
        }
    }
}
```

---

## 总结建议

SuperCloudys 的最佳实现路径：

1. **围绕定时器轮询、类型化解码、SQLite 持久化和 NSPanel 搜索 UI 构建稳健 MVP**
2. **保留足够的原始表示数据**，避免将应用局限于纯文本角落
3. **将隐私和自写抑制视为核心架构关注点**（Day 1 就要做对）
4. **将"立即粘贴"作为在可靠"复制回"之上的能力层**

这与应用当前的菜单栏架构匹配，尊重其 `LSUIElement` 后台工具模型，并可在不过度构建首版的前提下向 Raycast 级体验演进。

---

## 参考资料

- [Raycast Clipboard History 手册](https://manual.raycast.com/clipboard-history)
- [Apple NSPasteboard 文档](https://developer.apple.com/documentation/AppKit/NSPasteboard)
- [Apple changeCount 文档](https://developer.apple.com/documentation/appkit/nspasteboard/changecount)
- [Apple NSPasteboard.PasteboardType 文档](https://developer.apple.com/documentation/appkit/nspasteboard/pasteboardtype)
- [Maccy 仓库](https://github.com/p0deje/Maccy)
- [Clipy 仓库](https://github.com/Clipy/Clipy)
- [CopyClip 官网](https://copyclip.app/)
