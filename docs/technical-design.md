# CopyCapsule - 技术设计文档

## 技术栈

| 层级 | 技术选型 | 版本 |
|------|----------|------|
| 语言 | Swift | 5.9+ |
| UI 框架 | SwiftUI + AppKit | macOS 14+ |
| 数据存储 | SQLite (via GRDB) | 6.28+ |
| 全文搜索 | SQLite FTS5 | 内置 |
| 构建工具 | Swift Package Manager | 6.2 |
| 打包 | 自写 build.sh | - |

## 架构模式

采用 **MVVM + Service Layer** 架构：

```
View (SwiftUI) → ViewModel (@Observable) → Services → Storage (SQLite)
```

### 层级职责

| 层 | 职责 | 示例 |
|----|------|------|
| **View** | UI 渲染、用户交互 | HistoryPanelView, ClipCardView |
| **ViewModel** | 状态管理、UI 逻辑 | ClipHistoryViewModel (@MainActor, @Observable) |
| **Service** | 业务逻辑、数据操作 | ClipboardMonitor, ClipRepository |
| **Model** | 数据结构 | ClipItem, Settings |

### 数据流

```
用户复制 → NSPasteboard.changeCount 变化
  → ClipboardMonitor 检测到变化
  → 读取 pasteboard 内容（文字/图片）
  → DedupService 去重检查
  → ClipRepository.insert() 写入 SQLite
  → 通知 ClipHistoryViewModel
  → ViewModel 刷新 items 数组
  → SwiftUI 自动重绘 UI
```

## 核心模块设计

### 1. 剪贴板监听 (ClipboardMonitor)

- **方式**: Timer 轮询 `NSPasteboard.general.changeCount`
- **间隔**: 0.5 秒
- **内容读取优先级**: TIFF图片 > RTF富文本 > 纯文本
- **图片处理**: TIFF → PNG 转换（减小体积，统一格式）
- **线程**: 主线程读取，异步写入数据库

### 2. 数据存储 (ClipRepository)

- **数据库**: SQLite，使用 GRDB 库封装
- **位置**: `~/Library/Application Support/com.copycapsule.app/copycapsule.sqlite`
- **表结构**:

```sql
CREATE TABLE clip_items (
    id              TEXT PRIMARY KEY,    -- UUID
    type            TEXT NOT NULL,       -- 'text' | 'image' | 'rtf'
    text_content    TEXT,                -- 文本内容
    image_data      BLOB,                -- PNG 图片数据
    rtf_data        BLOB,                -- RTF 富文本数据
    source_app_name TEXT,                -- 来源应用名
    content_hash    TEXT NOT NULL,       -- SHA-256 去重哈希
    created_at      REAL NOT NULL,       -- Unix 时间戳
    is_pinned       INTEGER DEFAULT 0,   -- 是否置顶
    pinned_at       REAL                 -- 置顶时间戳
);

-- FTS5 全文搜索虚拟表
CREATE VIRTUAL TABLE clip_items_fts USING fts5(
    text_content,
    content='clip_items',
    content_rowid='rowid'
);
```

- **索引**: created_at DESC, is_pinned, content_hash

### 3. 菜单栏管理 (MenuBarManager)

- **图标**: NSStatusItem + SF Symbol `clipboard`
- **面板**: NSPopover，behavior = `.transient`（点击外部自动关闭）
- **内容**: NSHostingController 承载 SwiftUI View
- **尺寸**: 380 x 520 pt

### 4. 全局快捷键 (HotKeyManager)

- **API**: Carbon `RegisterEventHotKey`
- **组合键**: Shift + Command + V
- **权限**: 无需辅助功能权限
- **回调**: C callback → DispatchQueue.main.async → closure

### 5. 开机启动 (LoginItemManager)

- **API**: `SMAppService.mainApp.register()` (macOS 13+)
- **要求**: App 必须在 .app bundle 中且经过签名

### 6. 去重服务 (DedupService)

- **哈希算法**: SHA-256
- **缓存**: 最近 100 条哈希的 `Set<String>`
- **逻辑**: 先查缓存，未命中查数据库

## 关键文件清单

```
Sources/CopyCapsule/
├── App/main.swift                    # @main 入口
├── App/AppDelegate.swift             # 生命周期，组装各模块
├── Managers/MenuBarManager.swift     # 菜单栏图标+弹窗
├── Managers/HotKeyManager.swift      # Carbon 快捷键
├── Managers/LoginItemManager.swift   # SMAppService 开机启动
├── Services/ClipboardMonitor.swift   # 剪贴板轮询
├── Services/ClipRepository.swift     # SQLite 数据操作
├── Services/RetentionService.swift   # 过期清理
├── Services/DedupService.swift       # 去重
├── Models/ClipItem.swift             # 数据模型
├── Models/ClipType.swift             # 类型枚举
├── Models/Settings.swift             # 用户设置
├── ViewModels/ClipHistoryViewModel.swift  # UI 状态管理
├── Views/HistoryPanelView.swift      # 根视图
├── Views/ClipCardView.swift          # 剪贴卡片
├── Views/SearchBarView.swift         # 搜索栏
├── Views/EmptyStateView.swift        # 空状态
├── Views/SettingsView.swift          # 设置面板
└── Extensions/
    ├── Color+Theme.swift             # 主题色
    ├── Date+Relative.swift           # 相对时间
    └── NSImage+Resize.swift          # 图片缩略图
```

## 构建流程

1. `swift build -c release --disable-sandbox` 编译二进制
2. `./Scripts/build.sh` 创建 .app bundle 结构
3. 复制二进制文件和 Info.plist
4. `codesign --force --sign -` 临时签名
5. `open CopyCapsule.app` 启动应用

## v2 变更：面板架构

### 从 NSPopover 迁移到 NSWindow

| 对比 | v1 NSPopover | v2 NSWindow |
|------|-------------|-------------|
| 关闭方式 | 点击外部自动关闭 | 点图标/Esc 关闭 |
| 缩放 | 不支持 | 支持自由拖拽缩放 |
| 最小尺寸 | 固定 | 设有最小值 |
| 标题栏 | 无 | 有（标题: "CopyCapsule"） |
| 外观 | 系统 popover 样式 | 普通窗口样式 |

### 新增文件类型支持

剪贴板监听新增 `NSPasteboard.PasteboardType.fileURL` 检测，读取文件路径后以 `ClipType.file` 类型存储。

## 数据库 Schema v2

```sql
-- 新增字段（通过 ALTER TABLE 迁移）
ALTER TABLE clip_items ADD COLUMN is_favorited INTEGER NOT NULL DEFAULT 0;
ALTER TABLE clip_items ADD COLUMN favorited_at REAL;
ALTER TABLE clip_items ADD COLUMN file_path TEXT;
```

迁移后完整表结构：

```sql
CREATE TABLE clip_items (
    id              TEXT PRIMARY KEY,    -- UUID
    type            TEXT NOT NULL,       -- 'text' | 'image' | 'rtf' | 'file'
    text_content    TEXT,                -- 文本内容
    image_data      BLOB,                -- PNG 图片数据
    rtf_data        BLOB,                -- RTF 富文本数据
    file_path       TEXT,                -- 文件路径（仅 file 类型）
    source_app_name TEXT,                -- 来源应用名
    content_hash    TEXT NOT NULL,       -- SHA-256 去重哈希
    created_at      REAL NOT NULL,       -- Unix 时间戳
    is_pinned       INTEGER DEFAULT 0,   -- 是否置顶
    pinned_at       REAL,                -- 置顶时间戳
    is_favorited    INTEGER DEFAULT 0,   -- 是否收藏
    favorited_at    REAL                 -- 收藏时间戳
);
```

### 数据排序规则（v2）

```
1. 收藏区 (is_favorited=1) — 按 favorited_at 降序
   └─ 收藏数 ≥ 6 条时自动折叠为一组
2. 置顶区 (is_pinned=1) — 按 pinned_at 降序  
3. 最近区 — 按 created_at 降序
```

## 数据库迁移策略

- 版本号存储在 UserDefaults (`db_schema_version`)
- 首次启动：执行完整建表 SQL
- 升级时：按版本号顺序执行 ALTER TABLE 语句
- v1 版本号: 1
- v2 版本号: 2（新增 is_favorited, favorited_at, file_path 字段）
