import Foundation

@MainActor
final class RemoteCoordinator: ObservableObject {
    @Published private(set) var devices: [RemoteDevice] = RecentDeviceStore.load()
    @Published private(set) var selectedDevice: RemoteDevice?
    @Published private(set) var state = RemoteConnectionState.disconnected
    @Published var pairingPrompt: PairingPrompt?
    @Published var errorMessage: String?
    @Published var statusMessage = "Choose a TV to begin."
    @Published private(set) var colorRelayDevice: RemoteDevice?
    @Published private(set) var colorRelayState = RemoteConnectionState.disconnected
    @Published private(set) var colorRelayMessage: String?

    private let rokuAdapter = RokuAdapter()
    private let googleTVAdapter = GoogleTVAdapter()
    private let appleTVAdapter = AppleTVAdapter()
    private var activeAdapter: TVRemoteAdapter?
    private var colorRelayAdapter: GoogleTVAdapter?

    var capabilities: RemoteCapabilities? {
        selectedDevice.map { adapter(for: $0.platform).capabilities }
    }

    var isConnected: Bool {
        state == .connected
    }

    var availableColorRelayDevices: [RemoteDevice] {
        guard let selectedDevice, selectedDevice.platform == .googleTV else { return [] }
        return devices.filter {
            $0.platform == .googleTV && $0.id != selectedDevice.id
        }
    }

    var isColorRelayConnected: Bool {
        colorRelayState == .connected && colorRelayAdapter != nil
    }

    func refresh() async {
        state = .discovering
        statusMessage = "Looking for TVs on your Wi-Fi…"
        errorMessage = nil

        async let rokuResult = discover(using: rokuAdapter)
        async let googleResult = discover(using: googleTVAdapter)
        async let appleResult = discover(using: appleTVAdapter)
        let found = await rokuResult + googleResult + appleResult

        var unique: [String: RemoteDevice] = [:]
        for device in RecentDeviceStore.load() + found {
            unique[device.id] = device
        }
        devices = unique.values.sorted {
            if $0.platform == $1.platform {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.platform.displayName < $1.platform.displayName
        }
        state = .disconnected
        statusMessage = found.isEmpty
            ? "No new TVs found. You can add a Roku or Google TV by IP address."
            : "Found \(found.count) TV\(found.count == 1 ? "" : "s")."
    }

    func connect(to device: RemoteDevice) async {
        await disconnectColorRelay(clearPreference: false)
        let adapter = adapter(for: device.platform)
        if let activeAdapter, activeAdapter !== adapter {
            await activeAdapter.disconnect()
        }
        activeAdapter = adapter
        selectedDevice = device
        state = .connecting
        statusMessage = "Connecting to \(device.name)…"
        errorMessage = nil

        do {
            let outcome = try await adapter.connect(to: device)
            switch outcome {
            case .connected:
                finishConnection(to: device)
                await restoreColorRelay(for: device)
            case .pairingRequired(let prompt):
                state = .pairing
                pairingPrompt = prompt
                statusMessage = "Pairing is required."
            }
        } catch {
            fail(error)
        }
    }

    func addManualDevice(name: String, host: String, platform: TVPlatform) async {
        guard platform != .appleTV else {
            errorMessage = "Apple TV must be selected from discovery so its Bonjour service can be paired."
            return
        }
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else {
            errorMessage = TVRemoteError.invalidAddress.localizedDescription
            return
        }
        let device = RemoteDevice(
            name: name.isEmpty ? "\(platform.displayName) \(cleanHost)" : name,
            host: cleanHost,
            port: platform == .roku ? 8060 : 6466,
            platform: platform
        )
        await connect(to: device)
    }

    func submitPIN(_ pin: String) async {
        guard let activeAdapter, let selectedDevice else { return }
        state = .pairing
        errorMessage = nil
        do {
            try await activeAdapter.submitPIN(pin)
            pairingPrompt = nil
            finishConnection(to: selectedDevice)
            await restoreColorRelay(for: selectedDevice)
        } catch {
            fail(error)
            pairingPrompt = pairingPrompt ?? PairingPrompt(
                title: "Try pairing again",
                message: error.localizedDescription,
                placeholder: selectedDevice.platform == .appleTV ? "1234" : "A1B2C3",
                keyboard: selectedDevice.platform == .appleTV ? .numeric : .hexadecimal
            )
        }
    }

    func disconnect() async {
        await disconnectColorRelay(clearPreference: false)
        await activeAdapter?.disconnect()
        activeAdapter = nil
        selectedDevice = nil
        pairingPrompt = nil
        state = .disconnected
        statusMessage = "Choose a TV to begin."
    }

    func forget(_ device: RemoteDevice) {
        RecentDeviceStore.remove(device)
        ColorRelayStore.removeReferences(to: device.id)
        devices.removeAll { $0.id == device.id }
        if colorRelayDevice?.id == device.id {
            Task { await disconnectColorRelay(clearPreference: false) }
        }
        if selectedDevice?.id == device.id {
            Task { await disconnect() }
        }
    }

    func send(_ command: RemoteCommand) async {
        guard let activeAdapter else {
            fail(TVRemoteError.notConnected)
            return
        }
        let targetAdapter: TVRemoteAdapter
        if GoogleTVAdapter.isColorCommand(command),
           isColorRelayConnected,
           let colorRelayAdapter {
            targetAdapter = colorRelayAdapter
        } else {
            targetAdapter = activeAdapter
        }
        do {
            try await targetAdapter.send(command)
            errorMessage = nil
        } catch {
            fail(error, preserveConnection: true)
        }
    }

    func connectColorRelay(to device: RemoteDevice) async {
        guard let selectedDevice,
              selectedDevice.platform == .googleTV,
              device.platform == .googleTV,
              selectedDevice.id != device.id else {
            colorRelayMessage = "Choose a different Google TV as the color-button relay."
            return
        }

        await disconnectColorRelay(clearPreference: false)
        colorRelayState = .connecting
        colorRelayMessage = "Connecting color buttons through \(device.name)…"

        let adapter = GoogleTVAdapter()
        do {
            let outcome = try await adapter.connect(to: device)
            switch outcome {
            case .connected:
                colorRelayAdapter = adapter
                colorRelayDevice = device
                colorRelayState = .connected
                colorRelayMessage = "Color buttons route through \(device.name) via HDMI-CEC."
                ColorRelayStore.save(primaryDeviceID: selectedDevice.id, relayDeviceID: device.id)
            case .pairingRequired:
                await adapter.disconnect()
                colorRelayState = .failed("Pair the relay TV first.")
                colorRelayMessage = "Connect to \(device.name) normally once to pair it, then reconnect to \(selectedDevice.name)."
            }
        } catch {
            await adapter.disconnect()
            colorRelayState = .failed(error.localizedDescription)
            colorRelayMessage = "Could not connect the color relay: \(error.localizedDescription)"
        }
    }

    func disableColorRelay() async {
        await disconnectColorRelay(clearPreference: true)
    }

    func sendText(_ text: String) async -> Bool {
        guard let activeAdapter else {
            fail(TVRemoteError.notConnected)
            return false
        }
        do {
            try await activeAdapter.sendText(text)
            statusMessage = "Text sent to \(selectedDevice?.name ?? "TV")."
            return true
        } catch {
            fail(error, preserveConnection: true)
            return false
        }
    }

    private func discover(using adapter: TVRemoteAdapter) async -> [RemoteDevice] {
        (try? await adapter.discover(timeout: 2.5)) ?? []
    }

    private func adapter(for platform: TVPlatform) -> TVRemoteAdapter {
        switch platform {
        case .roku: rokuAdapter
        case .googleTV: googleTVAdapter
        case .appleTV: appleTVAdapter
        }
    }

    private func restoreColorRelay(for primaryDevice: RemoteDevice) async {
        guard primaryDevice.platform == .googleTV,
              let relayID = ColorRelayStore.relayDeviceID(for: primaryDevice.id),
              let relayDevice = devices.first(where: { $0.id == relayID }) else {
            return
        }
        await connectColorRelay(to: relayDevice)
    }

    private func disconnectColorRelay(clearPreference: Bool) async {
        let primaryDeviceID = selectedDevice?.id
        await colorRelayAdapter?.disconnect()
        colorRelayAdapter = nil
        colorRelayDevice = nil
        colorRelayState = .disconnected
        colorRelayMessage = nil
        if clearPreference, let primaryDeviceID {
            ColorRelayStore.remove(primaryDeviceID: primaryDeviceID)
        }
    }

    private func finishConnection(to device: RemoteDevice) {
        RecentDeviceStore.save(device)
        if !devices.contains(where: { $0.id == device.id }) {
            devices.append(device)
        }
        state = .connected
        statusMessage = "Connected to \(device.name)."
        errorMessage = nil
    }

    private func fail(_ error: Error, preserveConnection: Bool = false) {
        let message = error.localizedDescription
        errorMessage = message
        statusMessage = message
        if !preserveConnection {
            state = .failed(message)
        }
    }
}
