import SwiftUI

/// Tag input popup with autocomplete, summoned via ⌘+G.
struct TagInputView: View {
    @Bindable var viewModel: ClipHistoryViewModel
    @State private var xHovered = false
    @FocusState private var isFocused: Bool

    /// Existing tags that match the current input and aren't already on the item.
    private var suggestions: [String] {
        let text = viewModel.tagInputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        return viewModel.allTags.filter { tag in
            tag.localizedCaseInsensitiveContains(text)
        }
    }

    var body: some View {
        ZStack {
            // Blur overlay
            Color.black.opacity(0.15)
                .ignoresSafeArea()
                .onTapGesture { viewModel.cancelTagInput() }

            VStack {
                Spacer()

                VStack(spacing: 0) {
                    // Input row
                    HStack(spacing: 10) {
                        TextField("#添加标签", text: $viewModel.tagInputText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .focused($isFocused)
                            .onSubmit { viewModel.confirmTag() }

                        if viewModel.tagInputText.isEmpty {
                            Button { viewModel.cancelTagInput() } label: {
                                Text("✕")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .rotationEffect(.degrees(xHovered ? 180 : 0))
                                    .animation(.easeInOut(duration: 0.3), value: xHovered)
                            }
                            .buttonStyle(.plain)
                            .onHover { xHovered = $0 }
                        } else {
                            Button { viewModel.confirmTag() } label: {
                                Text("⏎")
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    // Divider + suggestions
                    if !suggestions.isEmpty {
                        Divider()
                            .padding(.leading, 14)
                            .opacity(0.4)

                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(suggestions, id: \.self) { tag in
                                    Button {
                                        viewModel.tagInputText = tag
                                        viewModel.confirmTag()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text("#\(tag)")
                                                .font(.system(size: 13))
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Text("⏎")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary.opacity(0.5))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    if tag != suggestions.last {
                                        Divider()
                                            .padding(.leading, 14)
                                            .opacity(0.25)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: min(CGFloat(suggestions.count) * 32, 160))
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onAppear { isFocused = true }
    }
}
