import SwiftUI

struct PairingView: View {
    let prompt: PairingPrompt
    @Binding var code: String
    let errorMessage: String?
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: "tv.and.mediabox")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)

                VStack(spacing: 8) {
                    Text(prompt.title)
                        .font(.title2.bold())
                    Text(prompt.message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                TextField(prompt.placeholder, text: $code)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(prompt.keyboard == .numeric ? .numberPad : .asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: code) { _, newValue in
                        let filtered: String
                        switch prompt.keyboard {
                        case .numeric:
                            filtered = String(newValue.filter(\.isNumber).prefix(4))
                        case .hexadecimal:
                            filtered = String(newValue.uppercased().filter(\.isHexDigit).prefix(6))
                        }
                        if code != filtered { code = filtered }
                    }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button("Pair", action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!isValid)
            }
            .padding(28)
            .navigationTitle("Pair TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }

    private var isValid: Bool {
        switch prompt.keyboard {
        case .numeric: code.count == 4
        case .hexadecimal: code.count == 6
        }
    }
}
