import SwiftUI

// MARK: - CopyCapsule Light Blue Theme

extension Color {
    /// Primary accent — buttons, selected state, pin active (#5AACFA)
    static let clipAccent = Color(red: 0.353, green: 0.675, blue: 0.980)

    /// Light accent — hover background, subtle highlights
    static let clipAccentLight = Color(red: 0.851, green: 0.929, blue: 0.992)

    /// Card background (#F7F8FA)
    static let clipCardBackground = Color(red: 0.969, green: 0.973, blue: 0.980)

    /// Highlight — search match or active state (#E3F2FC)
    static let clipHighlight = Color(red: 0.890, green: 0.949, blue: 0.992)

    /// Brief green flash after re-copying an item
    static let clipCopyFlash = Color.green.opacity(0.25)

    /// Favorite star gold (#FFB800)
    static let clipFavoriteGold = Color(red: 1.0, green: 0.722, blue: 0.0)

    // MARK: - Dark Mode Variants

    /// Dark card background (#212226)
    static let clipCardBackgroundDark = Color(red: 0.129, green: 0.129, blue: 0.149)

    /// Dark accent light — hover background (#1A2E48)
    static let clipAccentLightDark = Color(red: 0.102, green: 0.180, blue: 0.282)
}
