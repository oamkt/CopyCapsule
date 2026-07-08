import SwiftUI

/// A single clipboard history entry card.
struct ClipCardView: View {
    let item: ClipItem
    let isSelected: Bool
    var showPinButton: Bool = true
    var isPinnedInline: Bool = false
    let onTap: () -> Void
    let onPin: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void
    var onTag: (() -> Void)?
    var onRemoveTag: ((String) -> Void)?

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Content area — tap to re-copy
            Button(action: onTap) {
                contentPreview
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }
            .buttonStyle(.plain)

            // Bottom bar: timestamp + source app | colored dots
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text(formattedTime(item.createdAt))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let appName = item.sourceAppName {
                        Text("·").foregroundColor(.secondary).font(.system(size: 10))
                        Text(appName).font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    ForEach(item.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Color.gray.opacity(0.12)))
                            .onTapGesture(count: 2) {
                                onRemoveTag?(tag)
                            }
                    }
                }
                Spacer()
                HStack(spacing: 14) {
                    favoriteDot
                    if showPinButton { pinDot }
                    deleteDot
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(backgroundShape)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Content Preview

    @ViewBuilder
    private var contentPreview: some View {
        switch item.type {
        case .text, .rtf:
            textPreview
        case .image:
            imagePreview
        case .file:
            filePreview
        }
    }

    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.textContent ?? "(rich text)")
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var imagePreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let data = item.imageData,
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage.resized(toHeight: 160))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                HStack {
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                    Text("Image")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filePreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let path = item.filePath {
                    let url = URL(fileURLWithPath: path)
                    Image(systemName: "doc")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text(url.lastPathComponent)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                } else {
                    Image(systemName: "doc")
                        .foregroundColor(.secondary)
                    Text("File")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Background

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(cardBackgroundColor)
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    private var cardBackgroundColor: Color {
        let isDark = colorScheme == .dark
        if isSelected {
            return Color.gray.opacity(isDark ? 0.3 : 0.2)
        }
        if isPinnedInline {
            return Color.gray.opacity(isDark ? 0.35 : 0.25)
        }
        if isHovering {
            return isDark ? .clipAccentLightDark : .clipAccentLight
        }
        return isDark ? .clipCardBackgroundDark : .clipCardBackground
    }

    private func formattedTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            fmt.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            fmt.dateFormat = "'昨天' HH:mm"
        } else {
            fmt.dateFormat = "MM-dd HH:mm"
        }
        return fmt.string(from: date)
    }

    // MARK: - Action Dots

    private var favoriteDot: some View {
        Button(action: onFavorite) {
            Image(systemName: "star.fill")
                .font(.system(size: 12))
                .foregroundColor(item.isFavorited ? .green : .secondary)
                .offset(y: -0.5)
        }
        .buttonStyle(.plain)
        .help(item.isFavorited ? "Remove from favorites" : "Add to favorites")
    }

    private var pinDot: some View {
        Button(action: onPin) {
            Image(systemName: "pin.fill")
                .font(.system(size: 12))
                .foregroundColor(item.isPinned ? .green : .secondary)
                .offset(y: 0.5)
        }
        .buttonStyle(.plain)
        .help(item.isPinned ? "Unpin" : "Pin to top")
    }

    private var deleteDot: some View {
        Button(action: onDelete) {
            Image(systemName: "trash.fill")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Delete")
    }
}
