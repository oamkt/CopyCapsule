/// Supported clipboard content types.
enum ClipType: String, Codable, Sendable {
    case text
    case image
    case rtf
    case file
}
