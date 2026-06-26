import SwiftUI

/// Shown when the clipboard history is empty.
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("No clipboard history yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)

            Text("Copy something to get started")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown when a search returns no results.
struct EmptySearchView: View {
    let query: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary)

            Text("No results for \"\(query)\"")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
