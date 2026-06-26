import SwiftUI

/// Search bar with magnifying glass icon, text field, and clear button.
/// Sends debounced queries to the view model.
struct SearchBarView: View {
    let viewModel: ClipHistoryViewModel
    @State private var query: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))

            TextField("搜索剪贴板...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onChange(of: query) { _, newValue in
                    viewModel.search(newValue)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    viewModel.search("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
