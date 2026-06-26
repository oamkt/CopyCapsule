import SwiftUI
import AppKit

/// Manages the UI state for the clipboard history panel.
/// All UI mutations happen on @MainActor via @Observable.
@MainActor
@Observable
final class ClipHistoryViewModel {
    // MARK: - Published State

    var items: [ClipItem] = []
    var pinnedItems: [ClipItem] = []
    var favoritedItems: [ClipItem] = []
    var showSettings = false
    var isLoading = false
    var isSearching = false
    var errorMessage: String?
    var copiedItemID: UUID?         // briefly highlight after re-copy
    var onReCopy: (() -> Void)?     // notify monitor to skip self-written change

    // Tag support
    var showTagInput = false
    var tagInputText = ""
    var selectedItemIDs: Set<UUID> = []  // multi-select via Shift+click
    var taggingItemIDs: Set<UUID> = []   // batch tag targets
    var selectedTags: Set<String> = []
    var allTags: [String] = []

    var filteredByTag: Bool { !selectedTags.isEmpty }

    var itemCount: Int {
        items.count + pinnedItems.count + favoritedItems.count
    }

    // MARK: - Dependencies

    private let repository: ClipRepository
    private var searchTask: Task<Void, Never>?

    init(repository: ClipRepository) {
        self.repository = repository
    }

    // MARK: - Data Loading

    private var isRefreshing = false

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        isLoading = true
        defer { isLoading = false; isRefreshing = false }

        do {
            favoritedItems = try repository.fetchFavorited()
            items = try repository.fetchRecent(limit: 200)
            pinnedItems = try repository.fetchPinned()
            allTags = try repository.allTags()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Called by ClipboardMonitor when a new item is stored.
    func prependItem(_ item: ClipItem) {
        // Remove any existing item with the same ID (e.g., async image load replaces .file entry)
        items = items.filter { $0.id != item.id }
        pinnedItems = pinnedItems.filter { $0.id != item.id }
        favoritedItems = favoritedItems.filter { $0.id != item.id }

        if item.isFavorited {
            var arr = favoritedItems
            arr.insert(item, at: 0)
            favoritedItems = arr
        } else if item.isPinned {
            var arr = pinnedItems
            arr.insert(item, at: 0)
            pinnedItems = arr
        } else {
            var arr = items
            arr.insert(item, at: 0)
            items = arr
        }
    }

    // MARK: - Pin / Unpin

    func togglePin(id: UUID) {
        // Look up from current arrays to always get fresh state
        let all = favoritedItems + pinnedItems + items
        guard let item = all.first(where: { $0.id == id }) else { return }

        do {
            try repository.togglePin(id: id)

            var newItems = items.filter { $0.id != id }
            var newPinned = pinnedItems.filter { $0.id != id }
            var newFav = favoritedItems.filter { $0.id != id }

            var updated = item
            updated.isPinned.toggle()
            updated.pinnedAt = updated.isPinned ? Date() : nil

            if updated.isFavorited {
                // Favorited items stay in favorites regardless of pin state
                newFav.append(updated)
                newFav.sort { ($0.favoritedAt ?? .distantPast) > ($1.favoritedAt ?? .distantPast) }
            } else if updated.isPinned {
                newPinned.append(updated)
                newPinned.sort { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
            } else {
                newItems.append(updated)
                newItems.sort { $0.createdAt > $1.createdAt }
            }

            items = newItems
            pinnedItems = newPinned
            favoritedItems = newFav
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Favorite / Unfavorite

    func toggleFavorite(id: UUID) {
        // Look up from current arrays to always get fresh state
        let all = favoritedItems + pinnedItems + items
        guard let item = all.first(where: { $0.id == id }) else { return }

        do {
            try repository.toggleFavorite(id: id)

            var newItems = items.filter { $0.id != id }
            var newPinned = pinnedItems.filter { $0.id != id }
            var newFav = favoritedItems.filter { $0.id != id }

            var updated = item
            updated.isFavorited.toggle()
            updated.favoritedAt = updated.isFavorited ? Date() : nil

            if updated.isFavorited {
                // Favoriting clears pin — favorite outranks pin
                if updated.isPinned {
                    try? repository.togglePin(id: id)
                    updated.isPinned = false
                    updated.pinnedAt = nil
                }
                newFav.append(updated)
                newFav.sort { ($0.favoritedAt ?? .distantPast) > ($1.favoritedAt ?? .distantPast) }
            } else {
                // Unfavoriting clears tags
                updated.tags = []
                _ = try? repository.setTags(id: id, tags: [])
                if updated.isPinned {
                    newPinned.append(updated)
                    newPinned.sort { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
                } else {
                    newItems.append(updated)
                    newItems.sort { $0.createdAt > $1.createdAt }
                }
            }

            items = newItems
            pinnedItems = newPinned
            favoritedItems = newFav
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete

    func deleteItem(id: UUID) {
        do {
            try repository.delete(id: id)
            items = items.filter { $0.id != id }
            pinnedItems = pinnedItems.filter { $0.id != id }
            favoritedItems = favoritedItems.filter { $0.id != id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Clear only recent items; keeps favorites and pinned intact.
    func clearHistory() {
        do {
            try repository.deleteRecent()
            items = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete all items with a specific tag, then refresh state.
    func deleteByTag(_ tag: String) {
        do {
            try repository.deleteByTag(tag)
            // If currently filtering by this tag, clear selection
            var tags = selectedTags
            tags.remove(tag)
            selectedTags = tags
            refreshAllTags()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Re-copy to Clipboard

    /// Handle click on item — Shift = toggle multi-select, no-Shift = single select + copy
    func selectOrCopy(_ item: ClipItem, shiftHeld: Bool) {
        if shiftHeld {
            // Toggle selection — full Set replacement for @Observable
            var set = selectedItemIDs
            if set.contains(item.id) { set.remove(item.id) } else { set.insert(item.id) }
            selectedItemIDs = set
            taggingItemIDs = set
        } else {
            // Single select + copy to clipboard
            selectedItemIDs = [item.id]
            taggingItemIDs = [item.id]
            reCopyToClipboard(item)
        }
    }

    func clearSelection() {
        selectedItemIDs = []
        taggingItemIDs = []
    }

    func reCopyToClipboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.type {
        case .text:
            if let text = item.textContent {
                pb.setString(text, forType: .string)
            }

        case .rtf:
            if let rtfData = item.rtfData {
                pb.setData(rtfData, forType: .rtf)
            }
            if let text = item.textContent {
                pb.setString(text, forType: .string)
            }

        case .image:
            guard let pngData = item.imageData else { break }

            // Write temp file so Finder can paste as a file
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("copycapsule_image_\(UUID().uuidString).png")
            try? pngData.write(to: tempURL)
            pb.writeObjects([tempURL as NSURL])

            // PNG — baseline, works everywhere
            pb.setData(pngData, forType: .png)

            // TIFF — Photoshop and most bitmap editors
            if let bitmap = NSBitmapImageRep(data: pngData),
               let tiffData = bitmap.representation(using: .tiff, properties: [:]) {
                pb.setData(tiffData, forType: .tiff)
            }

            // PDF (vector wrapper) — Illustrator, Sketch, etc.
            if let image = NSImage(data: pngData) {
                if let pdfData = imageToPDFData(image) {
                    pb.setData(pdfData, forType: .pdf)
                }
                if let tiff = image.tiffRepresentation {
                    pb.setData(tiff, forType: .tiff)
                }
            }

        case .file:
            // Use NSURL to properly put file references on pasteboard
            if let path = item.filePath {
                let url = URL(fileURLWithPath: path)
                pb.writeObjects([url as NSURL])
            }
        }

        // Sync monitor to avoid re-capturing self-written data
        onReCopy?()

        // Brief highlight feedback
        copiedItemID = item.id
        Task {
            try? await Task.sleep(for: .seconds(1))
            if copiedItemID == item.id {
                copiedItemID = nil
            }
        }
    }

    // MARK: - Helpers

    /// Wraps an NSImage in a PDF container so vector apps (Illustrator, Sketch)
    /// paste it as embedded content rather than a linked file icon.
    private func imageToPDFData(_ image: NSImage) -> Data? {
        let size = image.size.width > 0 && image.size.height > 0
            ? image.size
            : NSSize(width: 512, height: 512)

        var rect = NSRect(origin: .zero, size: size)
        let data = NSMutableData()

        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &rect, nil) else {
            return nil
        }

        context.beginPDFPage(nil)
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        image.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()

        return data as Data
    }

    // MARK: - Export

    /// Export all items matching the currently selected tags.
    func exportSelectedTags(format: ExportService.ExportFormat, to url: URL) {
        guard !selectedTags.isEmpty else {
            errorMessage = ExportError.noTagSelected.localizedDescription
            return
        }
        do {
            var itemsByTag: [(tag: String, items: [ClipItem])] = []
            for tag in selectedTags.sorted() {
                let items = try repository.fetchByTag(tag, limit: 1000)
                if !items.isEmpty {
                    itemsByTag.append((tag, items))
                }
            }
            guard !itemsByTag.isEmpty else {
                errorMessage = ExportError.noItemsFound.localizedDescription
                return
            }
            try ExportService.export(itemsByTag: itemsByTag, format: format, to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Tags

    func startTagging(_ item: ClipItem) {
        taggingItemIDs = [item.id]
        selectedItemIDs = [item.id]
        tagInputText = ""
        showTagInput = true
    }

    func confirmTag() {
        let trimmed = tagInputText.trimmingCharacters(in: .whitespaces)
        defer {
            tagInputText = ""
            showTagInput = false
        }
        guard !trimmed.isEmpty, !taggingItemIDs.isEmpty else { return }
        for id in taggingItemIDs {
            addTag(id: id, tag: trimmed)
        }
        clearSelection()
    }

    func cancelTagInput() {
        tagInputText = ""
        showTagInput = false
    }

    func addTag(id: UUID, tag: String) {
        // Find the item
        let all = favoritedItems + pinnedItems + items
        guard var item = all.first(where: { $0.id == id }) else { return }
        guard item.tags.count < 3, !item.tags.contains(tag) else { return }

        // Auto-favorite on tag
        if !item.isFavorited {
            toggleFavorite(id: id)
            // Re-fetch after toggle moved it
            let updated = favoritedItems + pinnedItems + items
            guard let refetched = updated.first(where: { $0.id == id }) else { return }
            item = refetched
        }

        do {
            let newTags = try repository.setTags(id: id, tags: item.tags + [tag])
            updateItemTags(id: id, tags: newTags)
            refreshAllTags()
            if !selectedTags.isEmpty { filterBySelectedTags() } else { refresh() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeTag(id: UUID, tag: String) {
        let all = favoritedItems + pinnedItems + items
        guard let item = all.first(where: { $0.id == id }) else { return }

        do {
            let newTags = try repository.setTags(id: id, tags: item.tags.filter { $0 != tag })
            // Full replace to trigger @Observable
            updateItemTags(id: id, tags: newTags)
            // If all tags removed, unfavorite the item
            if newTags.isEmpty && item.isFavorited {
                toggleFavorite(id: id)
            }
            refreshAllTags()
            if !selectedTags.isEmpty {
                if allTags.contains(tag) {
                    filterBySelectedTags()
                } else {
                    // Tag no longer exists — remove from selection
                    var tags = selectedTags
                    tags.remove(tag)
                    selectedTags = tags
                    if selectedTags.isEmpty {
                        isSearching = false
                        refresh()
                    } else {
                        filterBySelectedTags()
                    }
                }
            } else {
                refresh()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var lastFilterTime: Date = .distantPast

    func renameTag(from oldTag: String, to newTag: String) {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != oldTag, !allTags.contains(trimmed) else { return }
        do {
            try repository.renameTag(from: oldTag, to: trimmed)
            refreshAllTags()
            if selectedTags.contains(oldTag) {
                var tags = selectedTags
                tags.remove(oldTag)
                tags.insert(trimmed)
                selectedTags = tags
            }
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggle a tag in the multi-select filter.
    func toggleTag(_ tag: String) {
        let now = Date()
        guard now.timeIntervalSince(lastFilterTime) > 0.15 else { return }
        lastFilterTime = now

        var tags = selectedTags
        if tags.contains(tag) {
            tags.remove(tag)
        } else {
            tags.insert(tag)
        }
        selectedTags = tags

        if selectedTags.isEmpty {
            isSearching = false
            refresh()
        } else {
            isSearching = true
            filterBySelectedTags()
        }
    }

    /// Run a multi-tag OR query and distribute results.
    private func filterBySelectedTags() {
        guard !selectedTags.isEmpty else {
            isSearching = false
            refresh()
            return
        }
        do {
            let results = try repository.fetchByTags(Array(selectedTags), limit: 200)
            favoritedItems = results.filter { $0.isFavorited }
            pinnedItems = results.filter { $0.isPinned && !$0.isFavorited }
            items = results.filter { !$0.isPinned && !$0.isFavorited }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAllTags() {
        allTags = (try? repository.allTags()) ?? []
    }

    private func updateItemTags(id: UUID, tags: [String]) {
        // Full array replacement triggers @Observable
        for i in items.indices where items[i].id == id {
            var updated = items; updated[i].tags = tags; items = updated; return
        }
        for i in pinnedItems.indices where pinnedItems[i].id == id {
            var updated = pinnedItems; updated[i].tags = tags; pinnedItems = updated; return
        }
        for i in favoritedItems.indices where favoritedItems[i].id == id {
            var updated = favoritedItems; updated[i].tags = tags; favoritedItems = updated; return
        }
    }

    // MARK: - Search

    func search(_ query: String) {
        // Cancel any in-flight search
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            // Empty query → restore full list
            isSearching = false
            refresh()
            return
        }

        // Debounce: wait 250ms after last keystroke
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))

            guard !Task.isCancelled else { return }

            isSearching = true
            do {
                let results = try repository.search(query: trimmed, limit: 100)
                // Distribute results by type, preserving sort order within each
                favoritedItems = results
                    .filter { $0.isFavorited }
                    .sorted { ($0.favoritedAt ?? .distantPast) > ($1.favoritedAt ?? .distantPast) }
                pinnedItems = results
                    .filter { $0.isPinned && !$0.isFavorited }
                    .sorted { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
                items = results.filter { !$0.isPinned && !$0.isFavorited }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
