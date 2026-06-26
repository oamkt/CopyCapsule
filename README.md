# CopyCapsule

macOS 原生剪贴板历史管理器，菜单栏小图标运行，自动记录复制内容，支持标签分组、搜索、收藏、多标签导出。

## 功能

- 🔄 自动记录文字、图片、文件复制
- 🏷️ 标签分组管理（自动补全、重命名）
- 📤 多选标签组批量导出（Markdown）
- ⭐ 收藏 & 置顶
- 🔍 全文搜索
- ⌨️ 全局快捷键
- 🌙 暗黑模式
- 🔄 自动检查更新

## 系统要求

- macOS 14 (Sonoma) 及以上

## 安装

从 [Releases](https://github.com/oamkt/CopyCapsule/releases) 下载最新 DMG，拖到 Applications 即可。

⚠️ 首次打开时，macOS 会提示"无法验证开发者"。请**右键点击** CopyCapsule → **打开**，再点"打开"，只需操作一次。

## 开发

```bash
swift build -c release --disable-sandbox
./Scripts/build.sh    # 构建 app + DMG
```

Swift 5.9+，SwiftUI + SQLite3 + FTS5。
