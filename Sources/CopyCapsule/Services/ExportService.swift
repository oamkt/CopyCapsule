import Foundation

/// Handles exporting groups of ClipItems to Markdown format.
enum ExportService {

    // MARK: - Format

    enum ExportFormat: String, CaseIterable {
        case markdown = "Markdown"

        var fileExtension: String { "md" }
        var contentType: String { "net.daringfireball.markdown" }
    }

    // MARK: - Export

    static func export(
        itemsByTag: [(tag: String, items: [ClipItem])],
        format: ExportFormat,
        to url: URL
    ) throws {
        switch format {
        case .markdown:
            try exportAsMarkdown(itemsByTag, to: url)
        }
    }

    // MARK: - Markdown

    private static func exportAsMarkdown(
        _ itemsByTag: [(tag: String, items: [ClipItem])],
        to url: URL
    ) throws {
        let formatter = dateFormatter()

        var lines: [String] = []
        var seenIDs = Set<UUID>()

        for (tag, rawItems) in itemsByTag {
            // Filter to text/rtf only, skip already-seen items (shared across tags)
            let items = rawItems.filter { item in
                guard item.type == .text || item.type == .rtf else { return false }
                guard !seenIDs.contains(item.id) else { return false }
                seenIDs.insert(item.id)
                return true
            }
            guard !items.isEmpty else { continue }

            if lines.isEmpty {
                lines.append("# \(tag)")
            } else {
                lines.append("")
                lines.append("---")
                lines.append("")
                lines.append("# \(tag)")
            }
            lines.append("")
            lines.append("*\(items.count) items exported by CopyCapsule*")
            lines.append("")

            for item in items {
                let dateStr = formatter.string(from: item.createdAt)
                let source = item.sourceAppName ?? ""

                lines.append("### \(dateStr) \u{00B7} \(source)")
                lines.append("")

                let content = item.textContent ?? ""
                if content.contains("\n") {
                    for line in content.components(separatedBy: "\n") {
                        lines.append("> \(line)")
                    }
                } else {
                    lines.append("> \(content)")
                }
                lines.append("")
                lines.append("---")
                lines.append("")
            }
        }

        let text = lines.joined(separator: "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func dateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }
}

// MARK: - Error

enum ExportError: LocalizedError {
    case noTagSelected
    case noItemsFound

    var errorDescription: String? {
        switch self {
        case .noTagSelected: return "请先选择标签后再导出"
        case .noItemsFound:  return "所选标签下没有可导出的文字内容"
        }
    }
}
