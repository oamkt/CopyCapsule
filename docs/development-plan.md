# CopyCapsule - 开发计划与执行步骤

## 开发总览

本项目分为两轮迭代：
- **第一轮（v1）**: 阶段 1-10，基础剪贴板历史管理器 ✅ 已完成
- **第二轮（v2）**: 阶段 11-15，收藏、文件支持、窗口缩放、图片修复、设置改进

遵循"一次只做一个阶段"原则，确保每一步都稳定可用。

## 阶段清单

### 阶段 1：项目脚手架 ✅ 待开始
- **目标**: 项目可编译、可打包为 .app、菜单栏无 Dock 图标
- **文件**:
  - `Package.swift` - SwiftPM 项目清单
  - `Resources/Info.plist` - Bundle 配置
  - `Sources/CopyCapsule/App/main.swift` - 应用入口
  - `Scripts/build.sh` - 构建脚本
- **验证**: `swift build` 成功 → `./Scripts/build.sh` 生成 CopyCapsule.app → `open CopyCapsule.app` 启动，菜单栏无 Dock 图标

### 阶段 2：数据模型 ⬜
- **目标**: 定义所有数据结构，编译通过
- **文件**:
  - `Models/ClipItem.swift` - 核心数据模型
  - `Models/ClipType.swift` - 类型枚举 (text/image/rtf)
  - `Models/Settings.swift` - 用户设置 (@Observable)
- **验证**: 编译通过，数据结构定义完整

### 阶段 3：存储层 ⬜
- **目标**: 数据可持久化、可查询、可搜索
- **文件**:
  - `Services/ClipRepository.swift` - SQLite CRUD + FTS5 搜索
  - `Services/DedupService.swift` - SHA-256 去重
- **验证**: 插入、查询、搜索、删除功能正常

### 阶段 4：菜单栏 ⬜
- **目标**: 菜单栏显示图标，点击弹出/关闭面板
- **文件**:
  - `App/AppDelegate.swift` - 应用生命周期
  - `Managers/MenuBarManager.swift` - 状态栏管理
- **验证**: 启动后菜单栏出现图标，点击弹出空面板

### 阶段 5：ViewModel ⬜
- **目标**: UI 状态管理层，连接存储和视图
- **文件**:
  - `ViewModels/ClipHistoryViewModel.swift` - @Observable 状态管理
- **验证**: ViewModel 能正确从存储层加载数据

### 阶段 6：UI 视图 ⬜
- **目标**: 完整 UI 渲染在弹出面板中
- **文件**:
  - `Views/HistoryPanelView.swift` - 根视图
  - `Views/ClipCardView.swift` - 剪贴卡片组件
  - `Views/SearchBarView.swift` - 搜索栏
  - `Views/EmptyStateView.swift` - 空状态
  - `Views/SettingsView.swift` - 设置面板
  - `Views/PinToggleButton.swift` - 置顶按钮
- **验证**: 面板中完整显示 UI（可用 Mock 数据）

### 阶段 7：剪贴板监听 ⬜
- **目标**: 真实复制内容自动出现在历史面板
- **文件**:
  - `Services/ClipboardMonitor.swift` - 轮询监听
- **验证**: 复制文字/图片 → 面板中出现新记录

### 阶段 8：快捷键 ⬜
- **目标**: ⇧⌘V 弹出面板
- **文件**:
  - `Managers/HotKeyManager.swift` - Carbon 全局热键
- **验证**: 按 ⇧⌘V → 弹出/关闭面板

### 阶段 9：辅助服务 ⬜
- **目标**: 自动清理过期数据 + 开机自启
- **文件**:
  - `Services/RetentionService.swift` - 定时清理
  - `Managers/LoginItemManager.swift` - SMAppService
- **验证**: 过期数据被清理，开机自启开关有效

### 阶段 10：视觉打磨 ✅
- **目标**: 主题色、时间格式化、图片缩略图
- **文件**:
  - `Extensions/Color+Theme.swift` - 淡蓝色主题
  - `Extensions/Date+Relative.swift` - "刚刚"、"2小时前"
  - `Extensions/NSImage+Resize.swift` - 图片缩略图生成
- **验证**: UI 美观，时间显示友好，图片显示正常

---

## 第二轮迭代（v2）—— 5 个新阶段

### 阶段 11：数据模型升级 ✅
- **目标**: 数据库 schema 从 v1 升级到 v2，模型支持新字段
- **变更内容**:
  - `ClipType` 新增 `.file` 类型
  - `ClipItem` 新增 `isFavorited`、`favoritedAt`、`filePath` 字段
  - `ClipRepository` 新增 schema 迁移逻辑（v1→v2 ALTER TABLE）
  - `ClipRepository` 新增 `fetchFavorited()`、`toggleFavorite()` 方法
  - 迁移时自动处理旧数据库（新增字段设默认值）
- **文件**:
  - `Models/ClipType.swift` — 加 `.file` case
  - `Models/ClipItem.swift` — 加新字段
  - `Services/ClipRepository.swift` — 迁移 + 新方法
- **验证**: 编译通过，旧数据库自动迁移成功，新字段可读写

### 阶段 12：剪贴板增强 ✅
- **目标**: 修复图片复制丢失问题，新增任意文件类型记录
- **变更内容**:
  - `ClipboardMonitor` 图片读取优化：增加更多 pasteboard type 尝试
  - `ClipboardMonitor` 新增文件 URL 检测
  - `ClipCardView` 新增 `.file` 类型卡片（文件图标+文件名）
  - `ClipHistoryViewModel.reCopyToClipboard()` 支持文件类型
- **文件**:
  - `Services/ClipboardMonitor.swift` — 增强 readImage + 新增 readFileURL
  - `Views/ClipCardView.swift` — 新增 filePreview
  - `ViewModels/ClipHistoryViewModel.swift` — 文件粘贴逻辑
- **验证**: 截图和 Finder 图片正常记录，Finder 文件（PDF/Word/文件夹）正常记录和粘贴

### 阶段 13：收藏功能 ✅
- **目标**: 完整收藏⭐功能，含排序、编组、永久保留
- **变更内容**:
  - `ClipCardView` 新增收藏按钮（star 图标，金黄色）
  - `ClipHistoryViewModel` 新增 `favoritedItems` 数组、`toggleFavorite()` 方法
  - `HistoryPanelView` 新增收藏区分组展示（≥6条自动折叠）
  - `RetentionService` 跳过收藏条目清理
  - `ClipRepository.purgeOlderThan()` 排除收藏条目
- **文件**:
  - `Views/ClipCardView.swift` — 收藏按钮
  - `ViewModels/ClipHistoryViewModel.swift` — 收藏状态管理
  - `Views/HistoryPanelView.swift` — 收藏分区 + 折叠组
  - `Services/RetentionService.swift` — 排除收藏
  - `Services/ClipRepository.swift` — purge 排除 favorited
- **验证**: 收藏/取消收藏正常，排序正确（收藏>置顶>普通），≥6条自动折叠，清理不删收藏

### 阶段 14：窗口改造 + 设置铺满 ✅
- **目标**: NSPopover → NSWindow，支持缩放，设置页替换式导航
- **变更内容**:
  - `MenuBarManager` 重写：用 NSWindow 替代 NSPopover
  - NSWindow 配置：标题 "CopyCapsule"、最小尺寸 300×320pt、默认 380×520pt
  - `HistoryPanelView` 移除 `.frame(width:height:)` 固定尺寸
  - `HistoryPanelView` 新增视图切换（历史列表 ↔ 设置页）
  - `SettingsView` 移除 Sheet 包装，改为全面板视图 + 返回按钮
  - 窗口行为：点图标 toggle，Esc 关闭
- **文件**:
  - `Managers/MenuBarManager.swift` — NSWindow 替代 NSPopover
  - `Views/HistoryPanelView.swift` — 视图切换 + 移除固定尺寸
  - `Views/SettingsView.swift` — 全面板 + 返回按钮
- **验证**: 窗口正常弹出/关闭，可拖拽缩放，不缩到小于最小值，设置页铺满面板，返回正常

### 阶段 15：集成测试与打磨 ✅
- **目标**: 全链路验证，修复 edge case，确保稳定性
- **变更内容**:
  - 全功能回归测试（文字/图片/文件/收藏/置顶/搜索/快捷键/设置/清理）
  - 暗黑模式一致性检查
  - 窗口在不同屏幕上的表现
  - 编译优化、性能检查
  - 清理调试代码
- **文件**: 按需修改
- **验证**: 所有功能正常，无编译警告，swift build 通过

## 进度追踪

| 阶段 | 状态 | 开始日期 | 完成日期 | 备注 |
|------|------|----------|----------|------|
| 1 脚手架 | ✅ | 2026-06-03 | 2026-06-03 | v1 完成 |
| 2 数据模型 | ✅ | 2026-06-03 | 2026-06-03 | - |
| 3 存储层 | ✅ | 2026-06-03 | 2026-06-03 | - |
| 4 菜单栏 | ✅ | 2026-06-03 | 2026-06-03 | - |
| 5 ViewModel | ✅ | 2026-06-04 | 2026-06-04 | - |
| 6 UI视图 | ✅ | 2026-06-04 | 2026-06-04 | - |
| 7 监听 | ✅ | 2026-06-04 | 2026-06-04 | - |
| 8 快捷键 | ✅ | 2026-06-04 | 2026-06-04 | - |
| 9 辅助服务 | ✅ | 2026-06-04 | 2026-06-04 | - |
| 10 打磨 | ✅ | 2026-06-04 | 2026-06-04 | - |
| 11 数据模型升级 | ✅ | 2026-06-05 | 2026-06-05 | v2 开始 |
| 12 剪贴板增强 | ✅ | 2026-06-05 | 2026-06-05 | 图片修复+文件支持 |
| 13 收藏功能 | ⬜ | - | - | - |
| 13 收藏功能 | ✅ | 2026-06-05 | 2026-06-05 | ⭐收藏+自动折叠 |
| 14 窗口改造 | ✅ | 2026-06-05 | 2026-06-05 | NSWindow+缩放+设置铺满 |
| 15 集成打磨 | ✅ | 2026-06-05 | 2026-06-05 | 全链路验证+边界修复 |

## 每日工作流程

1. 查看 `dev-logs/` 中最新日志，了解昨天进度
2. 确认当前阶段目标
3. 编写代码
4. 编译验证
5. 更新当日开发日志
6. 更新本文件中的进度表
