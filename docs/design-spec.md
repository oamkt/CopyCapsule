# CopyCapsule - UI 设计规范

## 设计原则

- **简洁**: 去除一切非必要元素
- **直观**: 一看就懂，一用就会
- **原生**: 遵循 macOS Human Interface Guidelines
- **轻量**: 小而美的工具感

## 色彩系统

### 主色调 - 淡蓝

| 色值名称 | Hex | RGB | 用途 |
|----------|-----|-----|------|
| Accent | `#5AACFA` | (90, 172, 250) | 强调色、按钮、选中态 |
| Accent Light | `#D9EDFC` | (217, 237, 252) | 卡片悬停背景 |
| Card Background | `#F7F8FA` | (247, 248, 250) | 卡片背景 |
| Highlight | `#E3F2FC` | (227, 242, 252) | 选中/激活背景 |

### 中性色

| 色值名称 | Hex | 用途 |
|----------|-----|------|
| Primary Text | `#1A1A1A` | 主要文字 |
| Secondary Text | `#8E8E93` | 辅助文字、时间戳 |
| Border | `#E5E5EA` | 分割线、边框 |
| Background | `#FFFFFF` | 面板背景 |

### 语义色

| 用途 | Hex |
|------|-----|
| 删除按钮 | `#FF3B30` (系统红) |
| 置顶激活 | Accent 蓝 |
| 复制成功反馈 | `#34C759` (系统绿) |

## 字体

| 用途 | 字体 | 大小 | 字重 |
|------|------|------|------|
| 标题 | SF Pro | 13pt | Semibold |
| 正文 | SF Pro | 13pt | Regular |
| 辅助文字 | SF Pro | 11pt | Regular |
| 搜索框文字 | SF Pro | 13pt | Regular |
| 时间戳 | SF Pro | 11pt | Regular |

所有字体使用系统默认 SF Pro，不引入自定义字体。

## 间距

| 元素 | 间距 |
|------|------|
| 面板内边距 | 12pt |
| 卡片间距 | 6pt |
| 卡片内边距 | 12pt |
| 图标与文字间距 | 8pt |
| 搜索栏与列表间距 | 8pt |
| 分区标题与卡片间距 | 4pt |

## 组件规格

### 菜单栏图标
- SF Symbol: `clipboard`
- 大小: 自适应（NSStatusItem.variableLength）
- 样式: isTemplate = true（自动适配亮/暗模式）

### 弹出面板
- 窗口类型: NSWindow（v2 从 NSPopover 迁移）
- 默认宽度: 380pt
- 默认高度: 520pt
- 最小宽度: 300pt
- 最小高度: 320pt
- 标题: "CopyCapsule"
- 背景: 系统 windowBackgroundColor
- 行为: 可拖拽边缘缩放，点击菜单栏图标或 Esc 关闭

### 搜索栏
- 高度: 32pt
- 圆角: 8pt
- 背景: Color(nsColor: .controlBackgroundColor)
- 图标: magnifyingglass (左侧)
- 清除按钮: xmark.circle.fill (右侧，有文字时显示)

### 剪贴卡片
- 高度: 自适应（文字约60pt，图片约100pt）
- 圆角: 8pt
- 背景: Card Background
- 阴影: black.opacity(0.05), radius: 2, y: 1
- 点击效果: 背景色短暂变为 Accent Light

### 文字预览
- 最大行数: 3 行
- 超出省略: ...
- 颜色: Primary Text

### 图片预览
- 最大高度: 80pt
- 保持宽高比
- 圆角: 4pt

### 置顶按钮
- SF Symbol: `pin.fill` (已置顶) / `pin` (未置顶)
- 大小: 14pt
- 颜色: Accent (已置顶) / Secondary Text (未置顶)

### 收藏按钮（v2 新增）
- 位置: 卡片右侧，置顶按钮和删除按钮之间
- 图标: `star.fill` (已收藏) / `star` (未收藏)
- 大小: 14pt
- 颜色: 金黄色 `#FFB800` (已收藏) / Secondary Text (未收藏)

### 收藏分区（v2 新增）
- 收藏 ≥ 6 条时自动折叠为可展开组
- 折叠标题: "⭐ Favorites (N)"
- 展开后正常显示所有收藏卡片
- 收藏 < 6 条时正常展开，不显示折叠提示

### 文件卡片（v2 新增）
- 文件类型显示文件图标 + 文件名
- 图标: 系统文件图标（NSWorkspace.shared.icon(forFile:)）
- 文件名: 13pt Regular, 最多2行
- 卡片高度: 自适应（约 50pt）
- 文件路径: 11pt Secondary Text, 1行省略

### 删除按钮
- SF Symbol: `trash`
- 大小: 14pt
- 颜色: Secondary Text → 悬停时变红

### 空状态
- 图标: `tray` (大号, 40pt)
- 标题: "还没有剪贴记录"
- 副标题: "复制一些内容就开始吧"
- 颜色: Secondary Text

## 交互规范

### 面板打开
- 点击菜单栏图标 → 弹出面板
- 按 ⇧⌘V → 弹出面板（如已打开则关闭）
- 面板获得焦点，搜索栏自动激活

### 面板关闭
- 点击面板外部 → 自动关闭（behavior: .transient）
- 再次点击菜单栏图标 → 关闭
- 按 Esc → 关闭
- 选择一条记录复制 → 0.5秒后自动关闭

### 卡片操作
- **点击**: 复制内容到剪贴板
- **置顶按钮**: 切换置顶状态
- **删除按钮**: 直接删除（无确认弹窗）

### 搜索
- 输入即搜，300ms 防抖
- 结果实时更新
- 清除搜索文字 → 恢复默认列表

### 设置（v2 更新）
- 点击面板底部的齿轮图标
- 整个面板内容切换为设置页（不再用 Sheet）
- 设置页顶部有返回按钮（← 箭头）
- 设置内容铺满面板可用空间

## 状态展示

| 状态 | 展示 |
|------|------|
| 加载中 | ProgressView 居中 |
| 空历史 | EmptyStateView |
| 搜索无结果 | "未找到包含 'xxx' 的记录" |
| 复制成功 | 卡片短暂绿色闪烁 (0.3s) |
| 错误 | Alert 弹窗提示 |

## 暗黑模式

v1 使用系统原生配色 + Template 图标，自动适配系统亮/暗模式。不单独设计暗黑主题。
