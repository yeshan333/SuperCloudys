# RMenu

macOS 桌面增效工具:**Finder 右键菜单增强** + **Dock 全局快捷键** + **菜单栏管理**。

## 截图

| 菜单栏管理 | Finder 右键菜单 |
|:---:|:---:|
| ![菜单栏](screenshots/menubar.png) | ![右键菜单](screenshots/context-menu.png) |

## 功能

### Finder 右键菜单

- **快速打开应用** - 右键直接通过 VSCode、Zed、Warp、Kaku 等应用打开文件/文件夹(自动检测已安装应用,显示对应图标)
- **复制路径** - 一键复制选中文件/文件夹的完整路径
- **自定义应用** - 通过菜单栏添加任意 `.app` 作为打开方式,可随时增删

### Dock 全局快捷键

- **Cmd+1 ~ Cmd+9 / Cmd+0** - 一键激活/隐藏 Dock 中的前 10 个应用
  - 应用未运行 → **冷启动**(直接用 Dock plist 里的路径,不依赖 LaunchServices 查询,沙盒下也稳)
  - 应用在后台 → 聚焦到前台
  - 应用在前台 → 隐藏(toggle)
- **自动跟随 Dock 变化** - 后台每 5 秒轮询 Dock 配置,自动重新绑定
- **全局开关** - 菜单栏一键禁用/启用所有快捷键
- **辅助功能授权(推荐)** - 授予后通过 `AXUIElement` 激活目标 App,绕过 macOS 14+ 焦点保护;未授权自动 fallback 到 `NSRunningApplication.activate()`

### 其他

- **开机自启** - 菜单栏 Toggle 启用,基于 `SMAppService`(macOS 13+ API,无需 Login Items 权限对话框)
- **菜单栏管理** - Dock 应用列表、自定义打开应用、Finder 扩展启用状态一目了然

## 系统要求

- macOS 14.0 (Sonoma) 及以上
- Xcode 15+ (从源码构建时)

## 安装

### 从 Release 下载

1. 在 [Releases](../../releases) 页面下载最新 `.dmg` 文件
2. 打开 DMG,将 `RMenu.app` 拖入 `Applications` 文件夹
3. 启动 `RMenu.app`
4. 在 **系统设置 > 登录项与扩展 > 添加的扩展** 中找到 RMenu,启用 Finder 扩展

### 从源码构建

**前置依赖:**

```bash
brew install xcodegen
xcodegen generate
```

**推荐:一键脚本(签名稳定,TCC 权限不丢)**

```bash
./scripts/install-local.sh
```

脚本一次完成:**确保自签证书** → **Release 构建** → **替换 `~/Applications/RMenu.app`** → **重启**。

- 首次运行会创建一个 10 年期的本地证书 `RMenu Local Dev` 导入登录钥匙串(只导一次)
- 因为签名身份固定,**辅助功能等 TCC 授权在每次重新 build 后都会保留**(adhoc 签名每次都会让 TCC 失效,这就是为什么需要稳定证书)
- 首次安装后仍需在 **系统设置 > 隐私与安全性 > 辅助功能** 添加一次 RMenu;之后所有迭代都不再需要

**手动构建(适合 CI 风格):**

```bash
xcodebuild \
  -project RMenu.xcodeproj \
  -scheme RMenu \
  -configuration Release \
  build \
  CODE_SIGN_IDENTITY="RMenu Local Dev" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  CONFIGURATION_BUILD_DIR="$(pwd)/build"

cp -R build/RMenu.app ~/Applications/
open ~/Applications/RMenu.app
pluginkit -e use -i com.yeshan333.RMenu.FinderSyncExtension
killall Finder
```

## 启用 Finder 扩展

首次安装后需手动启用扩展:

1. 打开 **系统设置**
2. 进入 **登录项与扩展** > **添加的扩展**
3. 找到 **RMenu**,开启 Finder 扩展开关

启用后在 Finder 中右键即可看到 RMenu 菜单项。

## 使用

### 菜单栏

启动后 RMenu 以菜单栏图标形式运行,点击可以:

- 查看 Finder 扩展启用状态(自动检测,无需手动刷新)
- **查看 Dock 应用列表 + 对应的 Cmd 快捷键标记**
- **启用/禁用 Cmd+1~0 全局快捷键**
- **开机自启 Toggle**
- 添加/移除自定义打开应用
- 快速跳转系统设置页面

### 右键菜单

在 Finder 中对文件或文件夹右键,菜单中会出现:

- **通过 XXX 打开** - 已安装的内置应用(VSCode、Zed、Warp、Kaku)及自定义添加的应用
- **复制路径** - 将选中项的完整路径复制到剪贴板

### Dock 快捷键

启动 RMenu 后,Cmd+1 ~ Cmd+9、Cmd+0 自动映射到 Dock 中的前 10 个应用:

- 按 **Cmd+N** 激活第 N 个应用(N 在前台时改为隐藏,实现 toggle)
- Dock 顺序变化后 5 秒内自动重新绑定
- 在菜单栏关闭"启用 Cmd+1~0 快捷键"Toggle 可整体禁用
- 首次启动会弹窗请求 **辅助功能** 权限。在 **系统设置 > 隐私与安全性 > 辅助功能** 勾选 RMenu 后,激活会通过 `AXUIElement` 直接 setFrontmost,**避免目标 App 弹出后被 macOS 14+ 焦点保护反弹**。不授权也能用,只是某些场景下目标 App 会被原前台 App 抢回焦点

> ⚠️ Cmd+数字 是全局快捷键,会"抢走"其他 App 内的同款快捷键(如浏览器切换标签页)。如果按了 Cmd+N 目标 App 弹出后立刻被反弹,通常是 **另一个工具(如 Magnet、Rectangle 等)注册了相同热键** —— 在菜单栏关闭或退出冲突的工具即可。

## 性能调优经验

如果遇到 Finder 右键卡顿,真凶常常**不在 RMenu 本身**,而在其他启用的 Finder Sync 扩展(Finder 必须等所有扩展返回菜单才能显示)。可用项目自带的诊断脚本定位:

```bash
./scripts/diagnose_rightclick.sh
```

脚本会同时:
1. 采样 Finder 主线程 3 秒
2. 抓取 RMenu 扩展的 `os_log` perf 数据
3. 检查 `spindump` 慢响应报告

排查命令:

```bash
# 列出所有启用的 Finder Sync 扩展
pluginkit -m -p com.apple.FinderSync

# 临时禁用某个可疑扩展
pluginkit -e ignore -i <bundle.id>
killall Finder
```

RMenu 自身的 `menu(for:)` 实现已优化到 **稳态 < 0.5ms**(后台预构建 MenuSnapshot,主线程纯组装 NSMenu)。perf 日志默认 debug 级,需要时:

```bash
log stream --level debug --predicate 'subsystem == "com.yeshan333.RMenu"'
```

## 测试

```bash
xcodegen generate
xcodebuild test \
  -project RMenu.xcodeproj \
  -scheme RMenuTests \
  -destination 'platform=macOS'
```

覆盖 `DockApp.shortcutLabel` 和 `DockReader.parseApps` 的 15 个用例(含 Dock 含 spacer/separator tile 的回归测试)。

## 项目结构

```
r-menu/
├── project.yml                       # XcodeGen 项目配置
├── RMenu/                            # 主应用(菜单栏)
│   ├── RMenuApp.swift                # App 入口
│   ├── MenuBarView.swift             # 菜单栏 UI
│   ├── Dock/                         # Dock 快捷键功能
│   │   ├── DockApp.swift             # 模型
│   │   ├── DockReader.swift          # 解析 Dock plist
│   │   ├── DockAppLauncher.swift     # launch/hide toggle
│   │   ├── DockShortcutManager.swift # Carbon 全局快捷键注册
│   │   ├── DockMonitor.swift         # 后台轮询 + 状态
│   │   └── AccessibilityActivator.swift # AXUIElement 激活(绕焦点保护)
│   ├── MenuBar/
│   │   └── DockAppsSection.swift     # 菜单栏 Dock 子区
│   ├── Services/
│   │   ├── ExtensionStatus.swift     # Finder 扩展状态检测
│   │   ├── LoginItemManager.swift    # 开机自启 (SMAppService)
│   │   └── IconPrewarmer.swift       # 启动时预热 LaunchServices
│   ├── Info.plist
│   └── RMenu.entitlements
├── RMenuExtension/                   # Finder Sync 扩展
│   ├── FinderSync.swift              # 扩展入口 (MenuSnapshot 预构建)
│   ├── AppLocator.swift              # 应用定位检测
│   ├── Actions/
│   │   ├── OpenAppAction.swift       # 打开应用动作
│   │   └── CopyPathAction.swift      # 复制路径动作
│   ├── Info.plist
│   └── RMenuExtension.entitlements
├── Shared/                           # 两个 Target 共享代码
│   ├── Constants.swift               # 常量 & ExternalApp 模型
│   ├── CustomAppStore.swift          # 自定义应用持久化(JSON, mtime 缓存)
│   └── DockShortcutSettings.swift    # 快捷键启用状态
├── RMenuTests/                       # 单元测试
│   ├── DockAppTests.swift
│   └── DockReaderTests.swift
├── scripts/
│   ├── install-local.sh              # 本地一键 build + 替换 + 重启(稳定签名)
│   ├── create-dmg.sh                 # DMG 打包脚本
│   ├── diagnose_rightclick.sh        # 右键卡顿诊断
│   └── rmenu-icon.svg                # App 图标源文件(改色调后用 rsvg-convert 重新导出)
└── .github/workflows/
    └── build.yml                     # CI: 自动构建 & 发布 DMG
```

## CI/CD

项目使用 GitHub Actions 自动构建和发布:

- **推送 `v*` tag** 时自动触发构建,生成 DMG 并创建 GitHub Release
- 支持 **手动触发**(Actions > Build & Package DMG > Run workflow)

```bash
# 发布新版本
git tag v1.2.0
git push origin v1.2.0
```

## 技术实现

- **Finder Sync Extension** (`FIFinderSync`) 注入右键菜单项;`MenuSnapshot` 模式在后台 utility queue 预构建菜单数据(apps + icons + mtime),主线程 `menu(for:)` 仅做 NSMenu 组装,稳态 < 0.5ms
- **Carbon `RegisterEventHotKey`** 注册 Cmd+1~0 全局快捷键(注册本身不需要 Accessibility 权限)
- **激活策略双路径**:授权 Accessibility 后用 `AXUIElement` setFrontmost(绕 macOS 14+ 焦点保护),否则 fallback 到 `NSRunningApplication.activate()`;`.hide()` 隐藏,全程避免 AppleScript / Automation 权限
- **`CFPreferences` / 直接读 plist** 解析 Dock 配置,沙盒下通过 `com.apple.security.temporary-exception.files.absolute-path.read-write` 入境
- **`SMAppService.mainApp`** 实现开机自启(macOS 13+)
- **SwiftUI `MenuBarExtra`** 实现菜单栏管理界面
- **App Sandbox** 启用以满足 macOS 扩展加载要求
- **XcodeGen** 管理项目配置,避免 `.xcodeproj` 冲突
- 自定义应用配置通过 JSON 文件在主应用与扩展间共享,带 mtime 缓存避免重复磁盘读

## License

MIT
