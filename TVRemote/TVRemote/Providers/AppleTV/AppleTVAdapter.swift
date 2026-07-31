import Foundation
import ItsytvCore

@MainActor
final class AppleTVAdapter: TVRemoteAdapter {
    let platform = TVPlatform.appleTV
    let capabilities = RemoteCapabilities.appleTV
    var onTextInputRequested: ((RemoteTextInputContext) -> Void)?
    var onTextInputEnded: (() -> Void)?

    private let manager = AppleTVManager()
    private var keyboardMonitorTask: Task<Void, Never>?

    func discover(timeout: TimeInterval) async throws -> [RemoteDevice] {
        manager.startScanning()
        try await Task.sleep(for: .seconds(timeout))
        let devices = manager.discoveredDevices.map {
            RemoteDevice(
                id: "appleTV:\($0.id)",
                name: $0.name,
                host: $0.host,
                port: $0.port,
                platform: .appleTV,
                serviceName: $0.name
            )
        }
        manager.stopScanning()
        return devices
    }

    func connect(to device: RemoteDevice) async throws -> ConnectionOutcome {
        let appleDevice = AppleTVDevice(
            id: String(device.id.dropFirst("appleTV:".count)),
            name: device.serviceName ?? device.name,
            host: device.host,
            port: device.port ?? 0,
            modelName: nil
        )
        manager.connect(to: appleDevice)
        let outcome = try await waitForConnection(timeout: 10)
        if outcome == .connected {
            startKeyboardMonitoring()
        }
        return outcome
    }

    func submitPIN(_ pin: String) async throws {
        let normalized = pin.filter(\.isNumber)
        guard normalized.count == 4 else {
            throw TVRemoteError.invalidPIN("The Apple TV code must contain four digits.")
        }
        manager.submitPIN(normalized)
        let outcome = try await waitForConnection(timeout: 12)
        guard outcome == .connected else {
            throw TVRemoteError.protocolFailure("Apple TV requested another pairing code.")
        }
        startKeyboardMonitoring()
    }

    func disconnect() async {
        keyboardMonitorTask?.cancel()
        keyboardMonitorTask = nil
        manager.disconnect()
    }

    func send(_ command: RemoteCommand) async throws {
        guard manager.connectionStatus == .connected else { throw TVRemoteError.notConnected }
        switch command {
        case .up:
            manager.pressButton(.up)
        case .down:
            manager.pressButton(.down)
        case .left:
            manager.pressButton(.left)
        case .right:
            manager.pressButton(.right)
        case .select:
            manager.pressButton(.select)
        case .back:
            manager.pressButton(.menu)
        case .home:
            manager.pressButton(.home)
        case .playPause:
            manager.pressButton(.playPause)
        case .rewind:
            manager.mrpManager.sendCommand(.skipBackward)
        case .fastForward:
            manager.mrpManager.sendCommand(.skipForward)
        case .volumeUp:
            manager.pressButton(.volumeUp)
        case .volumeDown:
            manager.pressButton(.volumeDown)
        case .mute:
            manager.toggleMute()
        case .power:
            manager.pressButton(.sleep)
        case .channelUp:
            manager.pressButton(.channelUp)
        case .channelDown:
            manager.pressButton(.channelDown)
        case .red, .green, .yellow, .blue:
            throw TVRemoteError.unsupported(
                "Apple TV does not expose native red, green, yellow, or blue commands."
            )
        case .digit0, .digit1, .digit2, .digit3, .digit4,
             .digit5, .digit6, .digit7, .digit8, .digit9,
             .delete, .input, .menu, .info, .guide, .captions, .search:
            throw TVRemoteError.unsupported(
                "\(command.rawValue) is not supported by Apple TV."
            )
        }
    }

    func sendText(_ text: String) async throws {
        guard manager.connectionStatus == .connected else { throw TVRemoteError.notConnected }
        manager.resetTextInputState()
        manager.updateRemoteText(text)
    }

    func beginTextInput() async throws {
        guard manager.connectionStatus == .connected else { throw TVRemoteError.notConnected }
        manager.resetTextInputState()
    }

    func updateText(from previousText: String, to newText: String) async throws {
        guard manager.connectionStatus == .connected else { throw TVRemoteError.notConnected }
        guard previousText != newText else { return }
        manager.updateRemoteText(newText)
    }

    private func startKeyboardMonitoring() {
        keyboardMonitorTask?.cancel()
        keyboardMonitorTask = Task { @MainActor [weak self] in
            var wasFocused = false
            while let self,
                  !Task.isCancelled,
                  self.manager.connectionStatus == .connected {
                let isFocused = self.manager.keyboardFocused
                if isFocused && !wasFocused {
                    self.onTextInputRequested?(RemoteTextInputContext())
                } else if !isFocused && wasFocused {
                    self.onTextInputEnded?()
                }
                wasFocused = isFocused
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func waitForConnection(timeout: TimeInterval) async throws -> ConnectionOutcome {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch manager.connectionStatus {
            case .connected:
                return .connected
            case .pairing:
                return .pairingRequired(
                    PairingPrompt(
                        title: "Pair with \(manager.connectedDeviceName ?? "Apple TV")",
                        message: "Enter the four-digit code shown on your Apple TV.",
                        placeholder: "1234",
                        keyboard: .numeric
                    )
                )
            case .error(let message):
                throw TVRemoteError.connectionFailed(message)
            case .disconnected, .connecting:
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw TVRemoteError.timedOut("Apple TV did not respond in time.")
    }
}
