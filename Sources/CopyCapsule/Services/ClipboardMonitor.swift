import AppKit
import SQLite3

/// Monitors the system clipboard for changes at a regular interval.
@MainActor
final class ClipboardMonitor {
    private nonisolated static let pollInterval: TimeInterval = 0.5
    private nonisolated static let maxTextBytes = 50_000
    private nonisolated static let maxImageBytes = 10_000_000
    private nonisolated static let maxFileReadBytes: Int64 = 50_000_000
    private nonisolated static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "webp", "heif"
    ]
    private let imageLoadQueue = DispatchQueue(label: "com.copycapsule.image-load")

    private var timer: Timer?
    private var lastChangeCount: Int
    private var isProcessing = false
    private let dedupService: DedupService
    private let repository: ClipRepository

    var onNewItem: ((ClipItem) -> Void)?

    init(dedupService: DedupService, repository: ClipRepository) {
        self.dedupService = dedupService
        self.repository = repository
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPasteboard() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// Call after programmatic pasteboard writes to sync the change count,
    /// so the self-written data is not re-captured as a new clip.
    func syncChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    // MARK: - Polling

    private func checkPasteboard() {
        guard !isProcessing else { return }
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        isProcessing = true
        defer { isProcessing = false }

        guard let item = readItem(from: pb) else { return }
        guard !isDuplicate(item.contentHash) else { return }

        do {
            try repository.insert(item)
            dedupService.recordHash(item.contentHash)
            onNewItem?(item)

            // If it's a file that looks like an image, load the real image
            // in the background, then update the DB entry and notify the UI.
            if item.type == .file, let path = item.filePath {
                let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
                if Self.imageExtensions.contains(ext) {
                    loadImageAsync(itemID: item.id, filePath: path)
                }
            }
        } catch {
            print("[CopyCapsule] insert failed: \(error)")
        }
    }

    private func loadImageAsync(itemID: UUID, filePath: String) {
        nonisolated(unsafe) let db = repository.dbPointer
        imageLoadQueue.async {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
                  let size = attrs[.size] as? Int64, size <= Self.maxFileReadBytes,
                  let nsImage = NSImage(contentsOfFile: filePath),
                  let tiff = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let pngData = bitmap.representation(using: .png, properties: [:]),
                  pngData.count <= Self.maxImageBytes else { return }

            let hash = DedupService.hashData(pngData)
            let sql = "UPDATE clip_items SET type = 'image', image_data = ?, content_hash = ? WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            _ = pngData.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 1, ptr.baseAddress, Int32(pngData.count), nil)
            }
            sqlite3_bind_text(stmt, 2, (hash as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (itemID.uuidString as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_DONE else { return }

            Task { @MainActor in
                let img = ClipItem(
                    id: itemID, type: .image, textContent: nil,
                    imageData: pngData, rtfData: nil, filePath: filePath,
                    sourceAppName: nil, contentHash: hash, createdAt: Date(),
                    isPinned: false, pinnedAt: nil,
                    isFavorited: false, favoritedAt: nil
                )
                self.onNewItem?(img)
            }
        }
    }

    // MARK: - Read

    private func readItem(from pb: NSPasteboard) -> ClipItem? {
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName

        // 1. File URL (any type — image or not). Fast: no disk read.
        //    Finder image copies are stored as .file so we don't block
        //    the main thread reading large images from disk.
        if let item = readFile(pb, sourceApp: sourceApp) { return item }

        // 2. Direct image data (TIFF/PNG from apps like WPS, browser, Photoshop)
        if let item = readImage(pb, sourceApp: sourceApp) { return item }

        // 3. RTF
        if let item = readRTF(pb, sourceApp: sourceApp) { return item }

        // 4. Plain text
        if let item = readText(pb, sourceApp: sourceApp) { return item }

        return nil
    }

    // MARK: - File URL (all types — fast, no disk read)

    private func readFile(_ pb: NSPasteboard, sourceApp: String?) -> ClipItem? {
        for url in fileURLs(from: pb) {
            let path = url.path
            guard FileManager.default.fileExists(atPath: path) else { continue }
            return ClipItem(type: .file, filePath: path, sourceAppName: sourceApp,
                            contentHash: DedupService.hashString(path))
        }
        return nil
    }

    // MARK: - Direct image data

    private func readImage(_ pb: NSPasteboard, sourceApp: String?) -> ClipItem? {
        if let tiff = pb.data(forType: .tiff), tiff.count <= Self.maxImageBytes,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return ClipItem(type: .image, imageData: png, sourceAppName: sourceApp,
                            contentHash: DedupService.hashData(png))
        }
        if let png = pb.data(forType: .png), png.count <= Self.maxImageBytes {
            return ClipItem(type: .image, imageData: png, sourceAppName: sourceApp,
                            contentHash: DedupService.hashData(png))
        }
        return nil
    }

    // MARK: - RTF

    private func readRTF(_ pb: NSPasteboard, sourceApp: String?) -> ClipItem? {
        guard let rtf = pb.data(forType: .rtf), rtf.count <= Self.maxTextBytes else { return nil }
        let text = truncated(pb.string(forType: .string) ?? "")
        return ClipItem(type: .rtf, textContent: text.isEmpty ? nil : text, rtfData: rtf,
                        sourceAppName: sourceApp, contentHash: DedupService.hashString(text))
    }

    // MARK: - Text

    private func readText(_ pb: NSPasteboard, sourceApp: String?) -> ClipItem? {
        guard let raw = pb.string(forType: .string),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let text = truncated(raw)
        return ClipItem(type: .text, textContent: text, sourceAppName: sourceApp,
                        contentHash: DedupService.hashString(text))
    }

    // MARK: - Dedup

    private func isDuplicate(_ hash: String) -> Bool {
        if dedupService.isDuplicate(hash) { return true }
        if let lastItems = try? repository.fetchRecent(limit: 1),
           let last = lastItems.first, last.contentHash == hash {
            dedupService.recordHash(hash)
            return true
        }
        return false
    }

    // MARK: - Helpers

    private func fileURLs(from pb: NSPasteboard) -> [URL] {
        if let items = pb.pasteboardItems {
            let urls = items.compactMap { item -> URL? in
                guard let s = item.string(forType: .fileURL), let u = URL(string: s), u.isFileURL else { return nil }
                return u
            }
            if !urls.isEmpty { return urls }
        }
        if let s = pb.string(forType: .fileURL), let u = URL(string: s), u.isFileURL { return [u] }
        return []
    }

    private func truncated(_ text: String) -> String {
        guard let data = text.data(using: .utf8), data.count > Self.maxTextBytes else { return text }
        // Estimate character count from average bytes-per-char, single-pass O(n)
        let avgBytesPerChar = Double(data.count) / Double(text.count)
        let targetChars = max(1, Int(Double(Self.maxTextBytes) / avgBytesPerChar))
        return String(text.prefix(targetChars))
    }
}
