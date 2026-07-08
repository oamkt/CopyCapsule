import Foundation

/// Seeds the database with built-in guide items on first launch.
/// Structure: 4 untagged items + 13 tagged items across A/B/C groups.
enum GuideSeeder {
    private static let seededKey = "guideSeeded_v1"

    static var isSeeded: Bool {
        UserDefaults.standard.bool(forKey: seededKey)
    }

    static func seedIfNeeded(into repository: ClipRepository) throws {
        guard !isSeeded else { return }

        let now = Date()
        var offset: TimeInterval = 0

        func makeItem(_ text: String, tags: [String] = []) -> ClipItem {
            offset -= 1
            let date = now.addingTimeInterval(offset)
            return ClipItem(
                id: UUID(),
                type: .text,
                textContent: text,
                imageData: nil,
                rtfData: nil,
                filePath: nil,
                sourceAppName: "CopyCapsule",
                contentHash: DedupService.hashString("guide:\(text)"),
                createdAt: date,
                isPinned: false,
                pinnedAt: nil,
                isFavorited: !tags.isEmpty,
                favoritedAt: tags.isEmpty ? nil : date,
                tags: tags
            )
        }

        // MARK: 碎碎念 (no tags — appear in Recent)

        let thoughts = [
            "这个剪贴的初步想法是来自b站up主大牙大分享的一个入门的Vibecoding教学案例开始的，在我跟着操作之后根据我日常使用的习惯进行相应的增加及操作逻辑上的梳理，认为是可以投入到日常办公使用的阶段；",
            "适用于经常在复制之间来回辗转的办公日常，可以复制各种格式的文件，如图片jpg、xlsx甚至是.md文件；",
            "在使用下来我认为标签组在收集信息，看书摘要，学习新事物上真的蛮好用；",
        ]
        for text in thoughts {
            try repository.insert(makeItem(text))
        }

        // MARK: A.标签指南

        let tagA = [
            "A-1.单击剪贴按Command + G可以创建编组，按住Shift点击可多选；",
            "A-2.在剪贴条上的标签，双击标签可以移出到常规；",
            "A-2-1.可以试试双击这条卡片上的标签",
            "A-3.按住Shift双击指定的标签组可以将整个标签组删除；",
            "A-4.双击标签组进行重命名；",
            "A-5.单选标签组按住Command + E 可以将该标签组进行导出markdown文件，多选则导出在同一份md文件里；",
            "A-5-1.建议您将操作手册作为练手点击所有进行导出，以便后续查看；",
        ]
        for text in tagA {
            try repository.insert(makeItem(text, tags: ["A.标签指南"]))
        }

        // MARK: B.分类管理

        let tagB = [
            "B-1.除了可以对单条剪贴进行收藏，标签组的剪贴也将统一归纳在收藏里，收藏的剪贴将永久存在；",
            "B-2.置顶≥3(大于等于)会编组到置顶里，置顶的剪贴保留天数是6天；",
            "B-3.常规的剪贴保留天数可在设置选项里自行选择；",
        ]
        for text in tagB {
            try repository.insert(makeItem(text, tags: ["B.分类管理"]))
        }

        // MARK: C.关于设置

        let tagC = [
            "C-1.设置旁的\"🗑️\"是一键清除按键，只对常规页面有效（没有收藏和置顶的剪贴）；",
            "C-2.窗口颜色默认跟随系统，点击切换后只能手动切换，按住shif点击切换按键可以重置回默认；",
            "C-3.单击快捷键显示 \" … \"则表示当前正在录制阶段，可以在键盘按下你想要的快捷键；",
        ]
        for text in tagC {
            try repository.insert(makeItem(text, tags: ["C.关于设置"]))
        }

        UserDefaults.standard.set(true, forKey: seededKey)
        let total = thoughts.count + tagA.count + tagB.count + tagC.count
        print("[CopyCapsule] Guide seeded: \(total) items")
    }
}
