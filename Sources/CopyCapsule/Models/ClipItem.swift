import Foundation

/// A single clipboard history entry.
struct ClipItem: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let type: ClipType
    let textContent: String?
    let imageData: Data?
    let rtfData: Data?
    let filePath: String?
    let sourceAppName: String?
    let contentHash: String
    let createdAt: Date
    var isPinned: Bool
    var pinnedAt: Date?
    var isFavorited: Bool
    var favoritedAt: Date?
    /// Up to 3 tags. Tags require favorited; unfavoriting clears them.
    var tags: [String]

    /// Create a new clip item (auto-generates id and createdAt).
    init(
        type: ClipType,
        textContent: String? = nil,
        imageData: Data? = nil,
        rtfData: Data? = nil,
        filePath: String? = nil,
        sourceAppName: String? = nil,
        contentHash: String,
        isPinned: Bool = false,
        pinnedAt: Date? = nil,
        isFavorited: Bool = false,
        favoritedAt: Date? = nil,
        tags: [String] = []
    ) {
        self.id = UUID()
        self.type = type
        self.textContent = textContent
        self.imageData = imageData
        self.rtfData = rtfData
        self.filePath = filePath
        self.sourceAppName = sourceAppName
        self.contentHash = contentHash
        self.createdAt = Date()
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.isFavorited = isFavorited
        self.favoritedAt = favoritedAt
        self.tags = tags
    }

    /// Create a clip item from stored data (explicit id and createdAt).
    init(
        id: UUID,
        type: ClipType,
        textContent: String?,
        imageData: Data?,
        rtfData: Data?,
        filePath: String?,
        sourceAppName: String?,
        contentHash: String,
        createdAt: Date,
        isPinned: Bool,
        pinnedAt: Date?,
        isFavorited: Bool,
        favoritedAt: Date?,
        tags: [String] = []
    ) {
        self.id = id
        self.type = type
        self.textContent = textContent
        self.imageData = imageData
        self.rtfData = rtfData
        self.filePath = filePath
        self.sourceAppName = sourceAppName
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.isFavorited = isFavorited
        self.favoritedAt = favoritedAt
        self.tags = tags
    }
}
