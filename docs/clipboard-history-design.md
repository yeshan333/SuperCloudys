# 剪贴板历史：实现说明

本文记录当前实现。操作方法和快捷键见 [README](../README.md#剪贴板历史)。

## 数据流

后台采集剪贴板变化 → 解码并保存图片 → 插入历史存储 → 面板可见时筛选 → 用户复制或粘贴。

| 文件 | 职责 |
| --- | --- |
| [ClipboardMonitorService.swift](../SuperCloudys/Clipboard/ClipboardMonitorService.swift) | 监听变化、排除敏感来源、解码、图片落盘 |
| [ClipboardEntry.swift](../SuperCloudys/Clipboard/ClipboardEntry.swift) | 内容模型、指纹和内容比较 |
| [ClipboardStore.swift](../SuperCloudys/Clipboard/ClipboardStore.swift) | 去重、容量、保留期、持久化、损坏恢复 |
| [ClipboardHistoryController.swift](../SuperCloudys/Clipboard/ClipboardHistoryController.swift) | 面板状态、搜索调度、复制与粘贴 |
| [ClipboardSearch.swift](../SuperCloudys/Clipboard/ClipboardSearch.swift) | 排序和过滤 |
| [ClipboardPanelController.swift](../SuperCloudys/Clipboard/ClipboardPanelController.swift) | 鼠标附近的浮动窗口、显示与隐藏 |
| [ClipboardImagePreviewLoader.swift](../SuperCloudys/Clipboard/ClipboardImagePreviewLoader.swift) | 异步降采样和预览缓存 |
| [Views](../SuperCloudys/Clipboard/Views) | 搜索栏、列表、详情和操作栏 |

## 采集与内容限制

采集服务使用后台 `.utility` GCD 定时器，每 0.5 秒检查 `NSPasteboard.changeCount`。自身复制通过写入前后的计数抑制重复采集。来源应用根据采样时的前台应用推断，不能作为精确的来源证明。

解码顺序为 URL、文件组、颜色、图片、文本。图片和缩略图先在后台落盘，再发布条目。当前没有完整的富文本格式还原、OCR 或云同步。

- 默认排除常见密码管理器，也支持用户指定排除应用。
- 忽略带有临时、隐藏或自动生成标记的剪贴板内容。
- 单条文本最多 2 MiB；单张图片最多 100 MiB、5000 万像素。
- 图片预览最长边 1024 像素，缓存按解码后的大小设置 32 MiB 预算；保存的原图用于复制和粘贴。

## 历史与搜索

默认最多保留 3000 条未固定记录，不按时间过期。固定条目不受容量和保留期限制；时间清理按最后使用时间计算，没有使用时间时取创建时间。

未固定记录去重时先比较指纹，再核对内容。文本比较实际正文，图片使用 SHA-256；旧版弱图片指纹不作为删除重复图片的依据。重复内容复用原条目并更新使用时间。

列表和键盘导航共用排序：固定条目优先，其余按 `lastUsedAt ?? createdAt` 倒序。日期分组使用相同时间字段，避免视觉顺序和方向键选择不一致。

搜索在后台执行，输入延迟 0.15 秒后筛选，并取消过期查询。仅在面板可见时筛选，历史变化后才重新排序。ASCII 内容使用 Foundation 快速匹配，其他内容使用 Swift Unicode 匹配。所有元数据驻留内存，当前未使用数据库、全文索引或分页。

## 面板与粘贴

面板在鼠标附近显示，按屏幕可用区域调整位置。每次显示都会重新请求搜索框焦点；隐藏时保留视图，因此不能只依赖首次出现回调。

复制只写入系统剪贴板。直接粘贴需要辅助功能权限：先恢复打开面板前的应用，确认前台应用正确，再发送 `Cmd+V`。粘贴请求串行处理，避免快速操作时交叉写入。

## 本地存储与恢复

数据目录为 `~/Library/Application Support/SuperCloudys/`：

| 路径 | 内容 |
| --- | --- |
| `clipboard_history.json` | 历史元数据 |
| `ClipboardAssets/` | 图片及缩略图 |
| `clipboard_recovery_*` | 损坏历史的原始 JSON 和图片备份 |

数据目录权限为 `0700`，历史文件和图片为 `0600`。普通更新合并延迟 2 秒后原子保存，删除与清空会立即调度保存；只有元数据保存成功后才删除不再使用的图片，避免磁盘历史引用已删除文件。

读取到损坏历史时，先保护原 JSON 和图片，再建立新历史。无法读取原文件或无法完成恢复备份时暂停持久化，并显示错误。恢复目录不会被常规清理删除。

设置保存在 UserDefaults，包含暂停状态、容量、保留期和排除应用。单元测试位于 [SuperCloudysTests](../SuperCloudysTests) 中的 `Clipboard*Tests.swift`；搜索性能测量见[开发说明](development.md#排查与性能)。
