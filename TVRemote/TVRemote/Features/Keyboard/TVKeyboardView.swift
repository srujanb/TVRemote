import SwiftUI

struct TVKeyboardBar: View {
    @FocusState private var isFocused: Bool
    @Binding private var text: String

    let deviceName: String
    let fieldLabel: String?
    let showsTVKeyboardHint: Bool

    init(
        deviceName: String,
        text: Binding<String>,
        fieldLabel: String?,
        showsTVKeyboardHint: Bool
    ) {
        self.deviceName = deviceName
        self.fieldLabel = fieldLabel
        self.showsTVKeyboardHint = showsTVKeyboardHint
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

                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .disabled(text.isEmpty)
                .accessibilityLabel("Clear text on phone and TV")
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

struct TVKeyboardCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Close TV keyboard")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(
                    Color(red: 240 / 255, green: 240 / 255, blue: 247 / 255)
                )
                .padding(.horizontal, 20)
                .frame(height: 38)
                .background(
                    Color(red: 34 / 255, green: 34 / 255, blue: 57 / 255),
                    in: Capsule()
                )
        }
        .buttonStyle(TVKeyboardCloseButtonStyle())
        .accessibilityLabel("Close TV keyboard")
    }
}

private struct TVKeyboardCloseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
