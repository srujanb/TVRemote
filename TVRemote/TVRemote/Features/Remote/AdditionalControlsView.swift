import SwiftUI

struct NumberPadView: View {
    @ObservedObject var coordinator: RemoteCoordinator
    let device: RemoteDevice

    private let keypadItems: [KeypadItem] = [
        .digit("1", .digit1), .digit("2", .digit2), .digit("3", .digit3),
        .digit("4", .digit4), .digit("5", .digit5), .digit("6", .digit6),
        .digit("7", .digit7), .digit("8", .digit8), .digit("9", .digit9),
        .symbol("delete.left", "Delete", .delete),
        .digit("0", .digit0),
        .symbol("return.left", "Enter", .select)
    ]

    var body: some View {
        VStack(spacing: 18) {
            keypad
                .frame(maxHeight: .infinity, alignment: .top)

            Text("Numbers are sent directly to \(device.name).")
                .font(.caption)
                .foregroundStyle(AdditionalControlsPalette.secondaryText)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(AdditionalControlsPalette.background.ignoresSafeArea())
        .navigationTitle("Number Pad")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var keypad: some View {
        if capabilities.supportsNumberPad {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                spacing: 12
            ) {
                ForEach(keypadItems) { item in
                    KeypadButton(item: item) {
                        send(item.command)
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Number Pad Unavailable",
                systemImage: "rectangle.grid.3x2.slash",
                description: Text(
                    "\(device.platform.displayName) does not expose number keys."
                )
            )
        }
    }

    private var capabilities: RemoteCapabilities {
        switch device.platform {
        case .roku: .roku
        case .googleTV: .googleTV
        case .appleTV: .appleTV
        }
    }

    private func send(_ command: RemoteCommand) {
        Task { await coordinator.send(command) }
    }
}

struct AdditionalRemotePage: View {
    @ObservedObject var coordinator: RemoteCoordinator
    let device: RemoteDevice
    let onShowDevices: () -> Void
    let onShowSettings: () -> Void
    let onShowRemote: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                pageHeader
                    .padding(.bottom, 28)

                VStack(alignment: .leading, spacing: 14) {
                    Text("TV Controls")
                        .font(.headline)
                        .foregroundStyle(AdditionalControlsPalette.primaryText)

                    extraControls
                }

                Spacer(minLength: 24)

                Label("Swipe right to return to the remote", systemImage: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AdditionalControlsPalette.secondaryText)
                    .padding(.bottom, 16)

                modeSwitcher
            }
            .padding(.horizontal, 32)
            .padding(.top, 18)
            .padding(.bottom, 12)
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .top
            )
        }
        .background(AdditionalControlsPalette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("More Controls")
                    .font(.title2.bold())
                    .foregroundStyle(AdditionalControlsPalette.primaryText)
                Text("\(device.platform.displayName) · \(device.name)")
                    .font(.subheadline)
                    .foregroundStyle(AdditionalControlsPalette.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onShowRemote) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AdditionalControlsPalette.primaryText)
                    .frame(width: 44, height: 38)
                    .background(AdditionalControlsPalette.control, in: Capsule())
            }
            .buttonStyle(AdditionalControlPressStyle())
            .accessibilityLabel("Return to remote")
        }
    }

    @ViewBuilder
    private var extraControls: some View {
        if supportedExtraControls.isEmpty {
            ContentUnavailableView(
                "No Additional Controls",
                systemImage: "ellipsis.circle",
                description: Text(
                    "\(device.platform.displayName) does not expose additional commands."
                )
            )
            .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2),
                spacing: 14
            ) {
                ForEach(supportedExtraControls) { control in
                    ExtraControlButton(control: control) {
                        send(control.command)
                    }
                }
            }
        }
    }

    private var capabilities: RemoteCapabilities {
        switch device.platform {
        case .roku: .roku
        case .googleTV: .googleTV
        case .appleTV: .appleTV
        }
    }

    private var supportedExtraControls: [ExtraControl] {
        [
            ExtraControl(command: .input, label: "Input", symbol: "rectangle.on.rectangle"),
            ExtraControl(
                command: .menu,
                label: device.platform == .roku ? "Options" : "Menu",
                symbol: "ellipsis.circle"
            ),
            ExtraControl(command: .info, label: "Info", symbol: "info.circle"),
            ExtraControl(command: .guide, label: "Guide", symbol: "list.bullet.rectangle"),
            ExtraControl(command: .captions, label: "Captions", symbol: "captions.bubble"),
            ExtraControl(command: .search, label: "Search", symbol: "magnifyingglass")
        ]
        .filter { capabilities.extraCommands.contains($0.command) }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 2) {
            ModeButton(
                symbol: "airplayvideo",
                label: "Devices",
                action: onShowDevices
            )
            ModeButton(symbol: "av.remote.fill", label: "Remote", action: onShowRemote)
            ModeButton(symbol: "square.grid.2x2.fill", label: "More", isSelected: true) {}
            ModeButton(
                symbol: "slider.horizontal.3",
                label: "Settings",
                action: onShowSettings
            )
        }
        .padding(4)
        .background(RemotePalette.switcherBackground, in: Capsule())
    }

    private func send(_ command: RemoteCommand) {
        Task { await coordinator.send(command) }
    }
}

private struct KeypadItem: Identifiable {
    let title: String?
    let symbol: String?
    let accessibilityLabel: String
    let command: RemoteCommand

    var id: RemoteCommand { command }

    static func digit(_ title: String, _ command: RemoteCommand) -> KeypadItem {
        KeypadItem(
            title: title,
            symbol: nil,
            accessibilityLabel: title,
            command: command
        )
    }

    static func symbol(
        _ symbol: String,
        _ accessibilityLabel: String,
        _ command: RemoteCommand
    ) -> KeypadItem {
        KeypadItem(
            title: nil,
            symbol: symbol,
            accessibilityLabel: accessibilityLabel,
            command: command
        )
    }
}

private struct ExtraControl: Identifiable {
    let command: RemoteCommand
    let label: String
    let symbol: String

    var id: RemoteCommand { command }
}

private struct KeypadButton: View {
    let item: KeypadItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let title = item.title {
                    Text(title)
                        .font(.title3.weight(.medium))
                } else if let symbol = item.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .medium))
                }
            }
            .foregroundStyle(AdditionalControlsPalette.primaryText)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                AdditionalControlsPalette.control,
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
        .buttonStyle(AdditionalControlPressStyle())
        .accessibilityLabel(item.accessibilityLabel)
    }
}

private struct ExtraControlButton: View {
    let control: ExtraControl
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: control.symbol)
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 22)
                Text(control.label)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(AdditionalControlsPalette.primaryText)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                AdditionalControlsPalette.control,
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
        .buttonStyle(AdditionalControlPressStyle())
    }
}

private struct AdditionalControlPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.76 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private enum AdditionalControlsPalette {
    static let background = Color(red: 8 / 255, green: 8 / 255, blue: 15 / 255)
    static let control = Color(red: 34 / 255, green: 34 / 255, blue: 57 / 255)
    static let primaryText = Color(red: 240 / 255, green: 240 / 255, blue: 247 / 255)
    static let secondaryText = Color(red: 159 / 255, green: 157 / 255, blue: 170 / 255)
}
