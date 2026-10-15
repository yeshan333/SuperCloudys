# 开发说明

需要 macOS 14+、Xcode 15+ 和 XcodeGen。项目使用 Swift 5.9；构建配置以 [project.yml](../project.yml) 为准，不直接维护生成的 `.xcodeproj`。

## 构建并替换本地安装

```bash
brew install xcodegen
xcodegen generate
./scripts/install-local.sh
```

安装脚本使用长期本地签名证书，构建 Release 并替换 `~/Applications/SuperCloudys.app`，随后启动应用、刷新系统注册并重启 Finder。稳定的签名身份有助于保留辅助功能授权；该证书仅用于本机开发。替换失败时脚本会尝试恢复原安装。

## 测试

```bash
xcodegen generate
xcodebuild test \
  -project SuperCloudys.xcodeproj \
  -scheme SuperCloudysTests \
  -destination "platform=macOS,arch=$(uname -m)"

xcodebuild analyze \
  -project SuperCloudys.xcodeproj \
  -scheme SuperCloudys \
  -configuration Release \
  -destination 'generic/platform=macOS'
```

[常规 CI](../.github/workflows/check.yml) 在 PR 和 main 分支推送时运行以上检查。测试宿主通过 `XCTestConfigurationFilePath` 跳过常驻监听和全局快捷键注册。

真实输入法切换检查默认跳过。需要验证系统行为时运行以下命令，结束后会尝试恢复原输入法：

```bash
TEST_RUNNER_SUPERCLOUDYS_INPUT_SOURCE_SMOKE=1 xcodebuild test \
  -project SuperCloudys.xcodeproj \
  -scheme SuperCloudysTests \
  -destination "platform=macOS,arch=$(uname -m)" \
  -only-testing:SuperCloudysTests/AppInputSourceControllerTests/testSystemSelectionChangesCurrentInputSourceAndRestoresOriginal
```

提示浮层检查使用环境变量 `TEST_RUNNER_SUPERCLOUDYS_INDICATOR_SMOKE=1` 和参数 `-only-testing:SuperCloudysTests/InputSourceIndicatorTests`；预览图输出到 `/tmp/SuperCloudys-input-source-indicator.png`。

浏览器规则单测不覆盖系统默认浏览器授权。修改分流功能后，还需在安装版本中启用系统链接分流，从编辑器点击命中规则和未命中规则的链接，确认分别进入目标浏览器和兜底浏览器。启用条件见 [README](../README.md#浏览器分流)。

## 代码入口

| 目录 | 职责 |
| --- | --- |
| [SuperCloudys](../SuperCloudys) | 非沙盒菜单栏主应用；入口为 `SuperCloudysApp.swift` |
| [BrowserRouting](../SuperCloudys/BrowserRouting) | 接收 HTTP/HTTPS、规则匹配、指定浏览器打开 |
| [InputSource](../SuperCloudys/InputSource) | 前台应用事件、系统输入源切换、提示浮层 |
| [Dock](../SuperCloudys/Dock) | Carbon 快捷键、Dock 文件事件监听、窗口轮换 |
| [Clipboard](../SuperCloudys/Clipboard) | 采集、持久化、搜索和面板，见[实现说明](clipboard-history-design.md) |
| [SuperCloudysExtension](../SuperCloudysExtension) | 沙盒 Finder Sync 扩展；后台刷新菜单快照 |
| [Shared](../Shared) | 两个应用目标共享的模型和配置 |
| [SuperCloudysTests](../SuperCloudysTests) | 以主应用为宿主的测试 |

Finder 扩展通过 `supercloudys://open` 将打开请求交给主应用，由主应用调用 `NSWorkspace`。浏览器链接由同一应用入口的 URL 事件处理器接收，按规则选择浏览器后打开。

## 排查与性能

- Finder 右键卡顿：运行 `./scripts/diagnose_rightclick.sh`，查看 Finder 采样和扩展日志；同时检查其他 Finder Sync 扩展。
- 剪贴板搜索：[基准脚本](../scripts/benchmark-clipboard-search.swift) 文件头提供编译命令，只使用合成数据。
- 交互问题：先检查[易回归问题](BUG_FIX_RECORDS.md)，再补充对应复现步骤。

## 发布

推送 `v*` tag 会触发[发布工作流](../.github/workflows/build.yml)：测试、静态分析、Developer ID 签名、DMG 公证、GitHub Release。也支持手动运行；手动运行上传构建产物，不创建 Release。

仓库需配置以下 Secrets：

- 签名：`DEVELOPER_ID_CERTIFICATE_BASE64`、`DEVELOPER_ID_CERTIFICATE_PASSWORD`、`DEVELOPER_ID_APPLICATION`、`KEYCHAIN_PASSWORD`
- 公证：`APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_SPECIFIC_PASSWORD`

tag 去掉 `v` 后写入 `MARKETING_VERSION`，构建号使用 GitHub Actions run number。打包脚本为 [create-dmg.sh](../scripts/create-dmg.sh)。
