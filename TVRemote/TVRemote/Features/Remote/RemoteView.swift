import SwiftUI

struct RemoteView: View {
    @ObservedObject var coordinator: RemoteCoordinator
    let device: RemoteDevice

    private var capabilities: RemoteCapabilities {
        coordinator.capabilities ?? .roku
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                connectionHeader
                topControls
                directionalPad
                colorControls
                mediaControls
                volumeAndChannelControls
                keyboardButton

                if let error = coordinator.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Disconnect") {
                    Task { await coordinator.disconnect() }
                }
            }
        }
    }

    private var connectionHeader: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.green)
                .frame(width: 9, height: 9)
            Text("Connected · \(device.platform.displayName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var topControls: some View {
        HStack {
            RemoteButton(label: "Power", symbol: "power") {
                send(.power)
            }
            Spacer()
            RemoteButton(label: "Home", symbol: "house.fill") {
                send(.home)
            }
            Spacer()
            RemoteButton(label: "Back", symbol: "arrow.uturn.backward") {
                send(.back)
            }
        }
    }

    private var directionalPad: some View {
        VStack(spacing: 8) {
            DPadButton(symbol: "chevron.up", label: "Up") { send(.up) }
            HStack(spacing: 8) {
                DPadButton(symbol: "chevron.left", label: "Left") { send(.left) }
                Button {
                    send(.select)
                } label: {
                    Text("OK")
                        .font(.headline)
                        .frame(width: 74, height: 74)
                        .background(.tint, in: Circle())
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Select")
                DPadButton(symbol: "chevron.right", label: "Right") { send(.right) }
            }
            DPadButton(symbol: "chevron.down", label: "Down") { send(.down) }
        }
        .padding(.vertical, 4)
    }

    private var colorControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ColorRemoteButton(name: "Red", color: .red, enabled: capabilities.supportsColorButtons) {
                    send(.red)
                }
                ColorRemoteButton(name: "Green", color: .green, enabled: capabilities.supportsColorButtons) {
                    send(.green)
                }
                ColorRemoteButton(name: "Yellow", color: .yellow, enabled: capabilities.supportsColorButtons) {
                    send(.yellow)
                }
                ColorRemoteButton(name: "Blue", color: .blue, enabled: capabilities.supportsColorButtons) {
                    send(.blue)
                }
            }

            if !capabilities.supportsColorButtons {
                Text("\(device.platform.displayName) does not expose color-button commands over Wi-Fi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if device.platform == .googleTV {
                Text("Color buttons not working? Choose a color-button relay in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var mediaControls: some View {
        HStack {
            RemoteButton(label: "Rewind", symbol: "backward.fill") {
                send(.rewind)
            }
            Spacer()
            RemoteButton(label: "Play/Pause", symbol: "playpause.fill") {
                send(.playPause)
            }
            Spacer()
            RemoteButton(label: "Forward", symbol: "forward.fill") {
                send(.fastForward)
            }
        }
    }

    private var volumeAndChannelControls: some View {
        HStack(spacing: 14) {
            ControlGroupBox(title: "Volume") {
                HStack {
                    CompactButton(symbol: "minus") { send(.volumeDown) }
                    CompactButton(symbol: "speaker.slash.fill") { send(.mute) }
                    CompactButton(symbol: "plus") { send(.volumeUp) }
                }
            }
            .opacity(capabilities.supportsVolume ? 1 : 0.45)
            .disabled(!capabilities.supportsVolume)

            ControlGroupBox(title: "Channel") {
                HStack {
                    CompactButton(symbol: "chevron.down") { send(.channelDown) }
                    CompactButton(symbol: "chevron.up") { send(.channelUp) }
                }
            }
            .opacity(capabilities.supportsChannel ? 1 : 0.45)
            .disabled(!capabilities.supportsChannel)
        }
    }

    private var keyboardButton: some View {
        Button {
            coordinator.presentTextInput()
        } label: {
            Label("Type on TV", systemImage: "keyboard")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!capabilities.supportsKeyboard)
    }

    private func send(_ command: RemoteCommand) {
        Task { await coordinator.send(command) }
    }
}

private struct RemoteButton: View {
    let label: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3)
                Text(label)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(width: 84, height: 58)
        }
        .buttonStyle(.bordered)
    }
}

private struct DPadButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.bold())
                .frame(width: 74, height: 54)
                .background(.background, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct ColorRemoteButton: View {
    let name: String
    let color: Color
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(enabled ? color : Color.secondary.opacity(0.25))
                .frame(width: 52, height: 52)
                .overlay {
                    if !enabled {
                        Image(systemName: "nosign")
                            .foregroundStyle(.secondary)
                    }
                }
        }
        .disabled(!enabled)
        .accessibilityLabel("\(name) button\(enabled ? "" : ", unavailable")")
    }
}

private struct CompactButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(minWidth: 30, minHeight: 34)
        }
        .buttonStyle(.bordered)
    }
}

private struct ControlGroupBox<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}
