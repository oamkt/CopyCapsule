import SwiftUI

/// Root view displayed inside the menu bar popover.
struct HistoryPanelView: View {
    let viewModel: ClipHistoryViewModel

    enum Tab: String, CaseIterable {
        case recent, pinned, favorites
    }

    @State private var selectedTab: Tab = .recent
    @State private var lastTabTime: Date = .distantPast
    @State private var showSettingsRow = false
    @State private var deleteTagTarget: String? = nil
    @State private var lastTagTap: (tag: String, time: Date)? = nil
    @State private var editingTag: String? = nil
    @State private var editingTagText = ""
    @FocusState private var isTagEditFocused: Bool

    /// Threshold at which a category gets its own tab.
    private let favGroupThreshold = 1
    private let pinGroupThreshold = 4

    var body: some View {
        // Force @Observable tracking so body re-evaluates when selection changes
        let _ = viewModel.selectedTags
        VStack(spacing: 0) {
            // Content — single page filtered by selected tab
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            } else {
                tabContent
            }

            // Tags bar
            if !viewModel.allTags.isEmpty {
                tagsBar
                    .padding(.horizontal, 22)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }

            // Search bar
            SearchBarView(viewModel: viewModel)
                .padding(.bottom, 3)

            // Footer with category tabs
            footerView

            // Settings row (expands below footer)
            if showSettingsRow {
                settingsRow
            }
        }
        .frame(minWidth: 300, minHeight: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if viewModel.showTagInput {
                TagInputView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        let items: [ClipItem] = {
            // When tag filter is active, all tabs show the full filtered results
            if viewModel.isSearching {
                return viewModel.favoritedItems + viewModel.pinnedItems + viewModel.items
            }
            switch selectedTab {
            case .recent:
                var combined: [ClipItem] = []
                let favCount = viewModel.favoritedItems.count
                let pinCount = viewModel.pinnedItems.count
                if favCount < favGroupThreshold { combined += viewModel.favoritedItems }
                if pinCount < pinGroupThreshold { combined += viewModel.pinnedItems }
                combined += viewModel.items
                return combined
            case .pinned:   return viewModel.pinnedItems
            case .favorites: return viewModel.favoritedItems
            }
        }()

        if items.isEmpty {
            EmptyStateView()
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(items) { item in
                        cardView(for: item)
                    }
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Card Factory

    private func cardView(for item: ClipItem) -> some View {
        let inline = item.isPinned && selectedTab == .recent
        return ClipCardView(
            item: item,
            isSelected: viewModel.selectedItemIDs.contains(item.id),
            showPinButton: !item.isFavorited,
            isPinnedInline: inline,
            onTap: {
                let shift = NSEvent.modifierFlags.contains(.shift)
                viewModel.selectOrCopy(item, shiftHeld: shift)
            },
            onPin: { viewModel.togglePin(id: item.id) },
            onFavorite: { viewModel.toggleFavorite(id: item.id) },
            onDelete: { viewModel.deleteItem(id: item.id) },
            onTag: { viewModel.startTagging(item) },
            onRemoveTag: { tag in viewModel.removeTag(id: item.id, tag: tag) }
        )
    }

    // MARK: - Settings Row

    private let settingsMargin: CGFloat = 20

    private var settingsRow: some View {
        let s = AppSettings.shared
        return VStack(spacing: 0) {
            Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 1)
                .padding(.horizontal, settingsMargin)
                .padding(.bottom, 10)
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 1) {
                        ForEach([1, 3, 5], id: \.self) { d in
                            Button {
                                s.retentionDays = d
                            } label: {
                                Text("\(d)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(s.retentionDays == d ? .white : .secondary)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(s.retentionDays == d ? Color.gray.opacity(0.7) : Color.gray.opacity(0.18)))
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 3).padding(.vertical, 2)
                    .background(Capsule().fill(Color.gray.opacity(0.12)))
                }

                Spacer()

                HStack(spacing: 4) {
                    shortcutCapsule("新建标签", s.tagShortcut) { s.tagShortcut = $0 }
                    shortcutCapsule("快捷窗口", s.windowShortcut) { s.windowShortcut = $0 }
                    shortcutCapsule("导出标签组", s.exportShortcut) { s.exportShortcut = $0 }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { s.autoStartEnabled.toggle() }
                        LoginItemManager.syncWithSetting(s.autoStartEnabled)
                    } label: {
                        HStack(spacing: 0) {
                            if s.autoStartEnabled { Spacer(minLength: 0) }
                            Circle().fill(s.autoStartEnabled ? Color.gray.opacity(0.8) : Color.gray.opacity(0.5))
                                .frame(width: 16, height: 16).padding(1)
                            if !s.autoStartEnabled { Spacer(minLength: 0) }
                        }
                        .frame(width: 30, height: 18)
                        .background(Capsule().fill(s.autoStartEnabled ? Color.gray.opacity(0.25) : Color.gray.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 3).padding(.vertical, 2)
                    .background(Capsule().fill(Color.gray.opacity(0.12)))
                }
            }
            .padding(.horizontal, settingsMargin)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
    }

    private func shortcutCapsule(_ name: String, _ sc: Shortcut, _ onChange: @escaping (Shortcut) -> Void) -> some View {
        ShortcutCapsuleView(name: name, shortcut: sc, onChange: onChange)
    }

    // MARK: - Tags Bar

    private var tagsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
            ForEach(viewModel.allTags, id: \.self) { tag in
                if editingTag == tag {
                    // Inline edit field
                    TextField("", text: $editingTagText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .focused($isTagEditFocused)
                        .frame(width: max(CGFloat(editingTagText.count) * 9 + 30, 60))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.yellow.opacity(0.5)))
                        .onSubmit { commitRename(old: tag) }
                        .onKeyPress(.escape) {
                            editingTag = nil
                            editingTagText = ""
                            return .handled
                        }
                } else {
                    Text("#\(tag)")
                        .font(.system(size: 12, weight: viewModel.selectedTags.contains(tag) ? .semibold : .regular))
                        .foregroundColor(viewModel.selectedTags.contains(tag) ? .white : .secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(
                            viewModel.selectedTags.contains(tag)
                                ? Color.green.opacity(0.5)
                                : Color.gray.opacity(0.15)))
                        .contentShape(Capsule())
                        .onTapGesture {
                            let now = Date()
                            if NSEvent.modifierFlags.contains(.shift) {
                                if let prev = lastTagTap, prev.tag == tag,
                                   now.timeIntervalSince(prev.time) < 0.35 {
                                    deleteTagTarget = tag
                                    lastTagTap = nil
                                } else {
                                    lastTagTap = (tag, now)
                                    viewModel.toggleTag(tag)
                                }
                            } else if let prev = lastTagTap, prev.tag == tag,
                                      now.timeIntervalSince(prev.time) < 0.4 {
                                // Double-tap → rename
                                lastTagTap = nil
                                editingTag = tag
                                editingTagText = tag
                                isTagEditFocused = true
                            } else {
                                lastTagTap = (tag, now)
                                viewModel.toggleTag(tag)
                            }
                        }
                }
            }
            }
        }
        .alert("删除标签组", isPresented: Binding(
            get: { deleteTagTarget != nil },
            set: { if !$0 { deleteTagTarget = nil } }
        )) {
            Button("取消", role: .cancel) { deleteTagTarget = nil }
            Button("删除", role: .destructive) {
                if let tag = deleteTagTarget {
                    viewModel.deleteByTag(tag)
                    deleteTagTarget = nil
                }
            }
        } message: {
            if let tag = deleteTagTarget {
                Text("将删除所有带「#\(tag)」标签的记录，此操作不可撤销。")
            } else {
                Text("")
            }
        }
    }

    private func commitRename(old tag: String) {
        let newName = editingTagText.trimmingCharacters(in: .whitespaces)
        if !newName.isEmpty, newName != tag {
            viewModel.renameTag(from: tag, to: newName)
        }
        editingTag = nil
        editingTagText = ""
    }

    // MARK: - Footer

    private var footerView: some View {
        let pinCount = viewModel.pinnedItems.count
        let favCount = viewModel.favoritedItems.count
        let total = viewModel.itemCount
        let showPinTab = pinCount >= pinGroupThreshold
        let showFavTab = favCount >= favGroupThreshold

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    // [total 🧹] capsule
                    HStack(spacing: 4) {
                        Text("\(total)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.gray.opacity(0.18)))
                        Button {
                            viewModel.clearHistory()
                        } label: {
                            Text("🧹").font(.system(size: 12))
                        }
                        .buttonStyle(.plain).help("Clear recent history")
                    }
                    .padding(.leading, 4).padding(.trailing, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.gray.opacity(0.12)))

                    // Settings capsule (⚙️ + optional expanded title)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showSettingsRow.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text("⚙️").font(.system(size: 12))
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.gray.opacity(0)))
                            if showSettingsRow {
                                Text("保留天数 > 快捷键 > 开机自启")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.leading, 4).padding(.trailing, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.gray.opacity(0.12)))
                    }
                    .buttonStyle(.plain).help("设置")
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                HStack(spacing: 14) {
                    if showFavTab { tabButton(tab: .favorites, label: "☀️", count: favCount) }
                    if showPinTab { tabButton(tab: .pinned, label: "⛳️", count: pinCount) }
                    if total > 0 { tabButton(tab: .recent, label: "📄", count: nil) }
                }
                .layoutPriority(3)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)
            .padding(.bottom, 18)
        }
    }

    /// A single tab button in the footer.
    private func tabButton(tab: Tab, label: String, count: Int?) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            let now = Date()
            guard now.timeIntervalSince(lastTabTime) > 0.15 else { return }
            lastTabTime = now
            selectedTab = tab
        } label: {
            Text(label)
                .font(.system(size: isSelected ? 14 : 12))
        }
        .buttonStyle(.plain)
        .help(tooltip(for: tab, count: count))
    }

    private var separatorDot: some View {
        Text("｜")
            .foregroundColor(.secondary)
            .font(.system(size: 11))
    }

    private func tooltip(for tab: Tab, count: Int?) -> String {
        switch tab {
        case .recent:   return "Recent items"
        case .pinned:   return "Pinned items (\(count ?? 0))"
        case .favorites: return "Favorites (\(count ?? 0))"
        }
    }
}

// MARK: - Shortcut Capsule View

private struct ShortcutCapsuleView: View {
    let name: String
    let shortcut: Shortcut
    let onChange: (Shortcut) -> Void
    @State private var isHovering = false
    @State private var isRecording = false

    var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            Text(isRecording ? "···" : (isHovering ? shortcut.displayString : name))
                .font(.system(size: (isHovering && !isRecording) ? 10 : 11.5))
                .foregroundColor(isRecording ? .white : .secondary)
                .frame(width: 56, height: 18)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(
                    isRecording ? Color.gray.opacity(0.7) : Color.gray.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .background(KeyCaptureView(isRecording: $isRecording, onCapture: { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            onChange(Shortcut(keyCode: Int(event.keyCode), modifiers: mods.rawValue))
            isRecording = false
        }))
    }
}
