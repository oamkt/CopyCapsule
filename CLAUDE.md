# CLAUDE.md - CopyCapsule 项目指引

## 项目概述

CopyCapsule 是一个 macOS 原生剪贴板历史管理器。以菜单栏小图标形式运行，自动记录用户复制的内容（文字+图片+文件），支持搜索、收藏、置顶、删除和再次粘贴。

**当前版本**: v2 已完成（15 阶段全部完成），进入按需增强阶段

## 重要：开始任何工作前

在修改任何代码之前，请务必先阅读以下标准文档：

| 文档 | 路径 | 内容 |
|------|------|------|
| 需求文档 | `docs/requirements.md` | 功能需求（含 v2 新增 F11-F15）、非功能需求、范围边界 |
| 技术设计 | `docs/technical-design.md` | 架构、模块设计、数据库表结构（含 v2 schema） |
| UI 设计规范 | `docs/design-spec.md` | 颜色、字体、间距、组件规格（含 v2 新组件） |
| 开发计划 | `docs/development-plan.md` | 15 阶段执行计划与进度（v1: 1-10, v2: 11-15） |

## 每日开发流程

1. **读最新日志**: 查看 `dev-logs/` 目录下最新日期的日志文件，了解当前进度
2. **确认阶段**: 查看 `docs/development-plan.md` 中当前阶段的状态
3. **编写代码**: 只做当前阶段的工作，不要跨阶段
4. **编译验证**: 每个阶段完成后执行 `swift build` 验证编译
5. **⚠️ 自动记录日志**: **每次代码改动后，必须自动更新以下两处，不需要等用户提醒**：
   - **dev-logs/YYYY-MM-DD.md**: 按当日日志格式追加，记录做了什么、改了哪些文件、编译状态
   - **memory/**: 如果是新功能或重要修改，在 `/Users/mini/.claude/projects/-Users-mini-Desktop-oabkt/memory/` 创建/更新记忆文件，并更新 `MEMORY.md` 索引
6. **更新进度**: 更新 `docs/development-plan.md` 中的进度表

## 技术关键点

- **语言版本**: Swift 5.9+
- **最低系统**: macOS 14 (Sonoma)
- **架构模式**: MVVM + Service Layer
- **UI 框架**: SwiftUI + AppKit（NSStatusItem + NSWindow）
- **数据库**: SQLite3（系统内置） + FTS5 全文搜索
- **窗口标题**: "CopyCapsule"
- **关键入口**: `Sources/CopyCapsule/App/main.swift`
- **核心模块**: `ClipboardMonitor` (监听)、`ClipRepository` (存储)、`MenuBarManager` (UI)

## 构建命令

```bash
# 编译
swift build -c release --disable-sandbox

# 打包 .app
./Scripts/build.sh

# 运行
open CopyCapsule.app
```

## 项目结构

```
Sources/CopyCapsule/
├── App/           # 入口 + 生命周期
├── Managers/      # 菜单栏（NSWindow）、快捷键、开机启动
├── Services/      # 剪贴板监听、数据存储、清理、去重
├── Models/        # ClipItem, ClipType, Settings
├── ViewModels/    # ClipHistoryViewModel
├── Views/         # SwiftUI 视图组件
└── Extensions/    # Color+Theme, Date+Relative, NSImage+Resize
```

## v2 新增功能（阶段 11-15）

| 阶段 | 功能 | 关键变更 |
|------|------|----------|
| 11 | 数据模型升级 | ClipType 加 `.file`、ClipItem 加收藏/文件字段、Schema v1→v2 迁移 |
| 12 | 剪贴板增强 | 修复图片复制丢失、新增文件类型监听 |
| 13 | 收藏功能 | 收藏⭐按钮、排序（收藏>置顶>普通）、≥6条自动折叠 |
| 14 | 窗口改造 | NSPopover → NSWindow、自由缩放、设置页铺满面板 |
| 15 | 集成打磨 | 全功能测试、暗黑模式、性能检查 |

## 注意

- 一次只做当前阶段的工作
- 不要引入未在技术设计中列出的第三方依赖
- 保持 UI 简洁，遵循 `docs/design-spec.md` 中的规范
- 所有数据存储在本地，绝不发送网络请求
- v2 阶段从 11 开始，不要重复做 v1 已完成的工作
