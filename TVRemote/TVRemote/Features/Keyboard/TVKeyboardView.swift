import SwiftUI

struct TVKeyboardBar: View {
    @FocusState private var isFocused: Bool
    @Binding private var text: String

    let deviceName: String
    let fieldLabel: String?
    let showsTVKeyboardHint: Bool
    let onClose: () -> Void

    init(
        deviceName: String,
        text: Binding<String>,
        fieldLabel: String?,
        showsTVKeyboardHint: Bool,
        onClose: @escaping () -> Void
    ) {
        self.deviceName = deviceName
        self.fieldLabel = fieldLabel
        self.showsTVKeyboardHint = showsTVKeyboardHint
        self.onClose = onClose
        _text = text
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)

                TextField(fieldLabel ?? "Type on \(deviceName)", text: $text)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close TV keyboard")
            }
            .frame(height: 36)

            if showsTVKeyboardHint {
                Text("Close the keyboard on your TV for typed text to appear.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2))
        }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .task {
            await Task.yield()
            isFocused = true
        }
    }
}
