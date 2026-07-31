import SwiftUI

struct RemoteView: View {
    @ObservedObject var coordinator: RemoteCoordinator
    let device: RemoteDevice
    var onShowSettings: () -> Void = {}
    var onShowDevices: () -> Void = {}

    private static let referenceScreenWidth: CGFloat = 294
    private static let referenceContentWidth: CGFloat = 246
    private static let referenceContentHeight: CGFloat = 563

    private var capabilities: RemoteCapabilities {
        coordinator.capabilities ?? .roku
    }

    var body: some View {
        GeometryReader { proxy in
            let widthScale = proxy.size.width / Self.referenceScreenWidth
            let heightScale = proxy.size.height / Self.referenceContentHeight
            let scale = min(widthScale, heightScale)

            VStack(spacing: 0) {
                connectionHeader
                    .padding(.bottom, 18)
                topControls
                    .padding(.bottom, 11)
                quickControls
                    .padding(.bottom, 15)
                navigationSurface
                    .padding(.bottom, 15)
                mediaControls
                    .padding(.horizontal, 6)
                    .padding(.bottom, 21)
                modeSwitcher

                if let error = coordinator.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(RemotePalette.power)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                        .padding(.horizontal, 8)
                }
            }
            .frame(width: Self.referenceContentWidth)
            .padding(.top, 15)
            .padding(.bottom, 12)
            .scaleEffect(scale, anchor: .top)
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .top
            )
        }
        .background(RemotePalette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
    }

    private var connectionHeader: some View {
        Button(action: onShowDevices) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayDeviceName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RemotePalette.secondaryText)
                        .lineLimit(1)
                    Text("Connected")
                        .font(.system(size: 12))
                        .foregroundStyle(RemotePalette.primaryText)
                }
                Spacer()
                Image(systemName: "airplayvideo")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(RemotePalette.primaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RemotePressStyle())
        .accessibilityLabel("Choose a different TV")
        .frame(height: 31)
    }

    private var topControls: some View {
        HStack {
            RoundRemoteButton(
                symbol: "power",
                foreground: RemotePalette.power,
                accessibilityLabel: "Power"
            ) {
                send(.power)
            }
            .opacity(capabilities.supportsPower ? 1 : 0.4)
            .disabled(!capabilities.supportsPower)

            Spacer()

            RoundRemoteButton(
                symbol: "speaker.slash",
                accessibilityLabel: "Mute"
            ) {
                send(.mute)
            }
        }
        .frame(height: 38)
        .padding(.horizontal, 6)
    }

    private var quickControls: some View {
        HStack(alignment: .top, spacing: 11) {
            RockerControl(
                topSymbol: "chevron.up",
                bottomSymbol: "chevron.down",
                title: "Ch",
                topLabel: "Channel up",
                bottomLabel: "Channel down",
                topAction: { send(.channelUp) },
                bottomAction: { send(.channelDown) }
            )
            .opacity(capabilities.supportsChannel ? 1 : 0.4)
            .disabled(!capabilities.supportsChannel)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ColorRemoteButton(
                        name: "Red",
                        color: .red,
                        enabled: capabilities.supportsColorButtons
                    ) {
                        send(.red)
                    }
                    ColorRemoteButton(
                        name: "Green",
                        color: .green,
                        enabled: capabilities.supportsColorButtons
                    ) {
                        send(.green)
                    }
                }

                HStack(spacing: 10) {
                    ColorRemoteButton(
                        name: "Yellow",
                        color: .yellow,
                        enabled: capabilities.supportsColorButtons
                    ) {
                        send(.yellow)
                    }
                    ColorRemoteButton(
                        name: "Blue",
                        color: .blue,
                        enabled: capabilities.supportsColorButtons
                    ) {
                        send(.blue)
                    }
                }
            }
            .frame(width: 112, height: 86)

            RockerControl(
                topSymbol: "plus",
                bottomSymbol: "minus",
                title: "Vol",
                topLabel: "Volume up",
                bottomLabel: "Volume down",
                topAction: { send(.volumeUp) },
                bottomAction: { send(.volumeDown) }
            )
            .opacity(capabilities.supportsVolume ? 1 : 0.4)
            .disabled(!capabilities.supportsVolume)
        }
    }

    private var navigationSurface: some View {
        RemoteTouchpad(
            keyboardEnabled: capabilities.supportsKeyboard,
            onKeyboard: { coordinator.presentTextInput() },
            send: send
        )
    }

    private var mediaControls: some View {
        HStack(spacing: 0) {
            MediaButton(symbol: "backward.end.fill", label: "Previous") {
                send(.rewind)
            }
            Spacer(minLength: 0)
            MediaButton(symbol: "stop", label: "Stop") {
                send(.playPause)
            }
            Spacer(minLength: 0)
            MediaButton(symbol: "pause.fill", label: "Pause") {
                send(.playPause)
            }
            Spacer(minLength: 0)
            MediaButton(symbol: "play.fill", label: "Play") {
                send(.playPause)
            }
            Spacer(minLength: 0)
            MediaButton(symbol: "forward.end.fill", label: "Next") {
                send(.fastForward)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(RemotePalette.control, in: Capsule())
    }

    private var modeSwitcher: some View {
        HStack(spacing: 2) {
            ModeButton(
                symbol: "airplayvideo",
                label: "Devices",
                action: onShowDevices
            )
            ModeButton(symbol: "remote.fill", label: "Remote", isSelected: true) {}
            ModeButton(symbol: "slider.horizontal.3", label: "Settings", action: onShowSettings)
        }
        .padding(4)
        .background(RemotePalette.switcherBackground, in: Capsule())
    }

    private var displayDeviceName: String {
        if device.name.localizedCaseInsensitiveContains(device.platform.displayName) {
            return device.name
        }
        return "\(device.platform.displayName) - \(device.name)"
    }

    private func send(_ command: RemoteCommand) {
        Task { await coordinator.send(command) }
    }
}

private enum RemotePalette {
    static let background = Color(red: 8 / 255, green: 8 / 255, blue: 15 / 255)
    static let surface = Color(red: 15 / 255, green: 15 / 255, blue: 25 / 255)
    static let control = Color(red: 34 / 255, green: 34 / 255, blue: 57 / 255)
    static let touchpad = Color(red: 35 / 255, green: 35 / 255, blue: 59 / 255)
    static let selected = Color(red: 49 / 255, green: 49 / 255, blue: 79 / 255)
    static let switcherBackground = Color(red: 13 / 255, green: 13 / 255, blue: 22 / 255)
    static let primaryText = Color(red: 240 / 255, green: 240 / 255, blue: 247 / 255)
    static let secondaryText = Color(red: 159 / 255, green: 157 / 255, blue: 170 / 255)
    static let mutedText = Color(red: 103 / 255, green: 102 / 255, blue: 119 / 255)
    static let power = Color(red: 1, green: 43 / 255, blue: 78 / 255)
}

private struct RoundRemoteButton: View {
    let symbol: String
    var foreground = RemotePalette.primaryText
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(foreground)
                .frame(width: 50, height: 38)
                .background(RemotePalette.control, in: Capsule())
        }
        .buttonStyle(RemotePressStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ColorRemoteButton: View {
    let name: String
    let color: Color
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Capsule()
                .stroke(color.opacity(enabled ? 0.95 : 0.25), lineWidth: 1.7)
                .frame(width: 20, height: 11)
                .frame(width: 50, height: 38)
                .background(RemotePalette.control, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.025), lineWidth: 0.5)
                }
        }
        .buttonStyle(RemotePressStyle())
        .disabled(!enabled)
        .accessibilityLabel("\(name) button\(enabled ? "" : ", unavailable")")
    }
}

private struct RockerControl: View {
    let topSymbol: String
    let bottomSymbol: String
    let title: String
    let topLabel: String
    let bottomLabel: String
    let topAction: () -> Void
    let bottomAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: topAction) {
                Image(systemName: topSymbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 50, height: 29)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(topLabel)

            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(RemotePalette.mutedText)
                .frame(height: 27)

            Button(action: bottomAction) {
                Image(systemName: bottomSymbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 50, height: 29)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(bottomLabel)
        }
        .foregroundStyle(RemotePalette.primaryText)
        .frame(width: 50, height: 86)
        .background(RemotePalette.control, in: RoundedRectangle(cornerRadius: 17))
        .buttonStyle(RemotePressStyle())
    }
}

private struct RemoteTouchpad: View {
    let keyboardEnabled: Bool
    let onKeyboard: () -> Void
    let send: (RemoteCommand) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 23)
                    .fill(RemotePalette.surface)

                Button {
                    send(.select)
                } label: {
                    RoundedRectangle(cornerRadius: 40)
                        .fill(RemotePalette.touchpad)
                        .frame(width: 188, height: 165)
                        .overlay {
                            TouchpadDots()
                        }
                }
                .buttonStyle(RemotePressStyle())
                .position(x: width / 2, y: height / 2)
                .accessibilityLabel("Select")
                .accessibilityHint("Tap to select")

                DirectionButton(symbol: "chevron.up", label: "Up") { send(.up) }
                    .position(x: width / 2, y: 12)
                DirectionButton(symbol: "chevron.left", label: "Left") { send(.left) }
                    .position(x: 13, y: height / 2)
                DirectionButton(symbol: "chevron.right", label: "Right") { send(.right) }
                    .position(x: width - 13, y: height / 2)
                DirectionButton(symbol: "chevron.down", label: "Down") { send(.down) }
                    .position(x: width / 2, y: height - 12)

                TouchpadCircleButton(
                    text: "123",
                    accessibilityLabel: "Number pad",
                    action: onKeyboard
                )
                .position(x: 20, y: 20)

                TouchpadCircleButton(
                    symbol: "keyboard",
                    accessibilityLabel: "Keyboard",
                    action: onKeyboard
                )
                .opacity(keyboardEnabled ? 1 : 0.4)
                .disabled(!keyboardEnabled)
                .position(x: width - 20, y: 20)

                TouchpadCircleButton(
                    symbol: "arrow.left",
                    accessibilityLabel: "Back"
                ) {
                    send(.back)
                }
                .position(x: 20, y: height - 20)

                TouchpadCircleButton(
                    symbol: "house",
                    accessibilityLabel: "Home"
                ) {
                    send(.home)
                }
                .position(x: width - 20, y: height - 20)
            }
        }
        .frame(height: 224)
    }
}

private struct TouchpadDots: View {
    var body: some View {
        VStack(spacing: 9) {
            ForEach(0..<5, id: \.self) { row in
                HStack(spacing: 9) {
                    ForEach(0..<5, id: \.self) { column in
                        Circle()
                            .fill(RemotePalette.mutedText)
                            .frame(width: 1.4, height: 1.4)
                            .opacity(dotOpacity(row: row, column: column))
                    }
                }
            }
        }
    }

    private func dotOpacity(row: Int, column: Int) -> Double {
        let distance = abs(row - 2) + abs(column - 2)
        if distance <= 1 { return 0.25 }
        if row == 2 || column == 2 { return 0.12 }
        return 0
    }
}

private struct DirectionButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(RemotePalette.mutedText)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct TouchpadCircleButton: View {
    var symbol: String?
    var text: String?
    let accessibilityLabel: String
    let action: () -> Void

    init(
        symbol: String? = nil,
        text: String? = nil,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.text = text
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .regular))
                } else if let text {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(RemotePalette.primaryText)
            .frame(width: 40, height: 40)
            .background(RemotePalette.control, in: Circle())
        }
        .buttonStyle(RemotePressStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct MediaButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(RemotePalette.primaryText)
                .frame(width: 28, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(RemotePressStyle())
        .accessibilityLabel(label)
    }
}

private struct ModeButton: View {
    let symbol: String
    let label: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(
                    isSelected ? RemotePalette.primaryText : RemotePalette.mutedText
                )
                .frame(width: 42, height: 31)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(RemotePalette.selected)
                    }
                }
        }
        .buttonStyle(RemotePressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct RemotePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
