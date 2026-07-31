import SwiftUI

struct TVKeyboardView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var text = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    let deviceName: String
    let onSend: (String) async -> Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Open a text field on \(deviceName), then type here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $text)
                    .focused($isFocused)
                    .font(.body)
                    .padding(8)
                    .frame(minHeight: 130)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.35))
                    )

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Send to TV", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(text.isEmpty || isSending)

                Text("Text entry works only while the TV or its current app has an editable field active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("TV Keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { isFocused = true }
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        let succeeded = await onSend(text)
        isSending = false
        if succeeded {
            dismiss()
        } else {
            errorMessage = "The TV did not accept the text. Make sure a text field is active."
        }
    }
}
