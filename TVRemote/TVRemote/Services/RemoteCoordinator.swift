import Foundation

@MainActor
final class RemoteCoordinator: ObservableObject {
    @Published private(set) var devices: [RemoteDevice]
    @Published private(set) var selectedDevice: RemoteDevice?
    @Published private(set) var state = RemoteConnectionState.disconnected
    @Published private(set) var isRefreshingDevices = false
    @Published private(set) var hasCompletedDeviceRefresh = false
    @Published private(set) var availableDeviceIDs: Set<String> = []
    @Published var pairingPrompt: PairingPrompt?
    @Published var errorMessage: String?
    @Published var statusMessage = "Choose a TV to begin."
    @Published private(set) var colorRelayDevice: RemoteDevice?
    @Published private(set) var colorRelayState = RemoteConnectionState.disconnected
    @Published private(set) var colorRelayMessage: String?
    @Published private(set) var textInputSession: RemoteTextInputSession?

    private let rokuAdapter: TVRemoteAdapter
    private let googleTVAdapter: TVRemoteAdapter
    private let appleTVAdapter: TVRemoteAdapter
    private let colorRelayAdapterFactory: @MainActor () -> TVRemoteAdapter
    private var activeAdapter: TVRemoteAdapter?
    private var colorRelayAdapter: TVRemoteAdapter?
    @Published private(set) var liveText = ""
    private var textUpdateTask: Task<Void, Never>?
    private var textInputDismissedAt: Date?
    private var hasAttemptedStartupConnection = false
    private var connectionGeneration = 0
    private var colorRelayGeneration = 0

    init(
        rokuAdapter: TVRemoteAdapter? = nil,
        googleTVAdapter: TVRemoteAdapter? = nil,
        appleTVAdapter: TVRemoteAdapter? = nil,
        initialDevices: [RemoteDevice]? = nil,
        colorRelayAdapterFactory: (@MainActor () -> TVRemoteAdapter)? = nil
    ) {
        let resolvedRokuAdapter = rokuAdapter ?? RokuAdapter()
        let resolvedGoogleTVAdapter = googleTVAdapter ?? GoogleTVAdapter()
        let resolvedAppleTVAdapter = appleTVAdapter ?? AppleTVAdapter()
        self.rokuAdapter = resolvedRokuAdapter
        self.googleTVAdapter = resolvedGoogleTVAdapter
        self.appleTVAdapter = resolvedAppleTVAdapter
        self.colorRelayAdapterFactory = colorRelayAdapterFactory ?? { GoogleTVAdapter() }
        devices = initialDevices ?? RecentDeviceStore.load()

        configurePrimaryAdapterCallbacks(resolvedRokuAdapter)
        configurePrimaryAdapterCallbacks(resolvedGoogleTVAdapter)
        configurePrimaryAdapterCallbacks(resolvedAppleTVAdapter)
    }

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

    func prepareDeviceList() async {
        if !hasAttemptedStartupConnection {
            hasAttemptedStartupConnection = true
            if let lastConnectedDevice = RecentDeviceStore.load().first {
                await connect(to: lastConnectedDevice)
                if isConnected || state == .pairing {
                    return
                }
            }
        }

        await refresh()
    }

    func refresh() async {
        guard !isRefreshingDevices else { return }

        let startingConnectionGeneration = connectionGeneration
        let preserveConnectionState = state == .connected
            || state == .connecting
            || state == .pairing
        isRefreshingDevices = true
        defer { isRefreshingDevices = false }

        if !preserveConnectionState {
            state = .discovering
            statusMessage = "Looking for TVs on your Wi-Fi…"
            errorMessage = nil
        }

        async let rokuResult = discover(using: rokuAdapter)
        async let googleResult = discover(using: googleTVAdapter)
        async let appleResult = discover(using: appleTVAdapter)
        let results = await [rokuResult, googleResult, appleResult]
        let found = results.flatMap(\.devices)
        let discoveryErrors = results.compactMap(\.errorMessage)

        guard !Task.isCancelled else { return }

        let refreshedDevices = Self.reconcileDevices(
            recent: RecentDeviceStore.load(),
            discovered: found,
            connectedDevice: isConnected ? selectedDevice : nil
        )
        availableDeviceIDs = refreshedDevices.availableIDs
        hasCompletedDeviceRefresh = true

        devices = refreshedDevices.devices.sorted {
            let firstIsAvailable = refreshedDevices.availableIDs.contains($0.id)
            let secondIsAvailable = refreshedDevices.availableIDs.contains($1.id)
            if firstIsAvailable != secondIsAvailable {
                return firstIsAvailable
            }
            if $0.platform == $1.platform {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.platform.displayName < $1.platform.displayName
        }

        let discoveryMessage: String
        if found.isEmpty, !discoveryErrors.isEmpty {
            discoveryMessage = "TV discovery failed. Check Local Network access and try again."
        } else if found.isEmpty {
            discoveryMessage = "No new TVs found. You can add a Roku or Google TV by IP address."
        } else if discoveryErrors.isEmpty {
            discoveryMessage = "Found \(found.count) TV\(found.count == 1 ? "" : "s")."
        } else {
            discoveryMessage = "Found \(found.count) TV\(found.count == 1 ? "" : "s"); some providers could not be scanned."
        }

        if !preserveConnectionState,
           startingConnectionGeneration == connectionGeneration,
           state == .discovering {
            state = .disconnected
            statusMessage = discoveryMessage
            errorMessage = discoveryErrors.isEmpty ? nil : discoveryErrors.joined(separator: "\n")
        } else if state == .connected {
            statusMessage = discoveryMessage
        }
    }

    static func reconcileDevices(
        recent: [RemoteDevice],
        discovered: [RemoteDevice],
        connectedDevice: RemoteDevice?
    ) -> (devices: [RemoteDevice], availableIDs: Set<String>) {
        var devices: [RemoteDevice] = []
        var availableIDs = Set<String>()
        var consumedDiscoveryIndexes = Set<Int>()

        for recentDevice in recent {
            guard !devices.contains(where: { representsSameDevice($0, recentDevice) }) else {
                continue
            }

            if let matchIndex = discovered.indices.first(where: {
                !consumedDiscoveryIndexes.contains($0)
                    && representsSameDevice(recentDevice, discovered[$0])
            }) {
                consumedDiscoveryIndexes.insert(matchIndex)
                let match = discovered[matchIndex]
                devices.append(
                    RemoteDevice(
                        id: recentDevice.id,
                        name: recentDevice.name,
                        host: match.host,
                        port: match.port,
                        platform: match.platform,
                        serviceName: match.serviceName ?? recentDevice.serviceName
                    )
                )
                availableIDs.insert(recentDevice.id)
            } else {
                devices.append(recentDevice)
            }
        }

        for index in discovered.indices where !consumedDiscoveryIndexes.contains(index) {
            let discoveredDevice = discovered[index]
            if let existingDevice = devices.first(where: {
                representsSameDevice($0, discoveredDevice)
            }) {
                availableIDs.insert(existingDevice.id)
            } else {
                devices.append(discoveredDevice)
                availableIDs.insert(discoveredDevice.id)
            }
        }

        if let connectedDevice {
            if let existingDevice = devices.first(where: {
                representsSameDevice($0, connectedDevice)
            }) {
                availableIDs.insert(existingDevice.id)
            } else {
                devices.append(connectedDevice)
                availableIDs.insert(connectedDevice.id)
            }
        }

        return (devices, availableIDs)
    }

    private static func representsSameDevice(
        _ first: RemoteDevice,
        _ second: RemoteDevice
    ) -> Bool {
        first.id == second.id
            || (
                first.platform == second.platform
                    && normalizedHost(first.host) == normalizedHost(second.host)
            )
    }

    private static func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")
            .union(.whitespacesAndNewlines))
            .lowercased()
    }

    func connect(to device: RemoteDevice) async {
        connectionGeneration &+= 1
        let generation = connectionGeneration

        await disconnectColorRelay(clearPreference: false)
        guard generation == connectionGeneration else { return }

        let adapter = adapter(for: device.platform)
        if let previousAdapter = activeAdapter {
            activeAdapter = nil
            await previousAdapter.disconnect()
            guard generation == connectionGeneration else { return }
        }

        activeAdapter = adapter
        selectedDevice = device
        pairingPrompt = nil
        state = .connecting
        statusMessage = "Connecting to \(device.name)…"
        errorMessage = nil

        do {
            let outcome = try await adapter.connect(to: device)
            guard generation == connectionGeneration else {
                if activeAdapter !== adapter {
                    await adapter.disconnect()
                }
                return
            }

            switch outcome {
            case .connected:
                finishConnection(to: device)
                await restoreColorRelay(for: device, connectionGeneration: generation)
            case .pairingRequired(let prompt):
                state = .pairing
                pairingPrompt = prompt
                statusMessage = "Pairing is required."
            }
        } catch {
            guard generation == connectionGeneration else { return }
            await adapter.disconnect()
            guard generation == connectionGeneration else { return }
            if activeAdapter === adapter {
                activeAdapter = nil
            }
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
        let generation = connectionGeneration
        state = .pairing
        errorMessage = nil
        do {
            try await activeAdapter.submitPIN(pin)
            guard generation == connectionGeneration,
                  self.activeAdapter === activeAdapter,
                  self.selectedDevice == selectedDevice else {
                return
            }
            pairingPrompt = nil
            finishConnection(to: selectedDevice)
            await restoreColorRelay(
                for: selectedDevice,
                connectionGeneration: generation
            )
        } catch {
            guard generation == connectionGeneration else { return }
            state = .pairing
            errorMessage = error.localizedDescription
            statusMessage = "Pairing failed. Check the code and try again."
            pairingPrompt = pairingPrompt ?? PairingPrompt(
                title: "Try pairing again",
                message: error.localizedDescription,
                placeholder: selectedDevice.platform == .appleTV ? "1234" : "A1B2C3",
                keyboard: selectedDevice.platform == .appleTV ? .numeric : .hexadecimal
            )
        }
    }

    func cancelPairing() async {
        await disconnect()
    }

    func disconnect() async {
        connectionGeneration &+= 1
        let adapter = activeAdapter
        activeAdapter = nil

        textUpdateTask?.cancel()
        textUpdateTask = nil
        textInputSession = nil
        liveText = ""
        selectedDevice = nil
        pairingPrompt = nil
        state = .disconnected
        statusMessage = "Choose a TV to begin."

        await disconnectColorRelay(clearPreference: false)
        await adapter?.disconnect()
    }

    func forget(_ device: RemoteDevice) {
        RecentDeviceStore.remove(device)
        ColorRelayStore.removeReferences(to: device.id)
        adapter(for: device.platform).forgetPairing(for: device)
        availableDeviceIDs.remove(device.id)
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
        let primaryConnectionGeneration = connectionGeneration

        await disconnectColorRelay(clearPreference: false)
        guard primaryConnectionGeneration == connectionGeneration,
              self.selectedDevice?.id == selectedDevice.id else {
            return
        }
        colorRelayGeneration &+= 1
        let generation = colorRelayGeneration
        colorRelayState = .connecting
        colorRelayMessage = "Connecting color buttons through \(device.name)…"

        let adapter = colorRelayAdapterFactory()
        guard adapter.platform == .googleTV else {
            colorRelayState = .failed("The color relay adapter is invalid.")
            colorRelayMessage = "Could not create a Google TV color relay."
            return
        }
        adapter.onConnectionEvent = { [weak self] event in
            self?.handleColorRelayConnectionEvent(event, generation: generation)
        }
        colorRelayAdapter = adapter

        do {
            let outcome = try await adapter.connect(to: device)
            guard generation == colorRelayGeneration,
                  primaryConnectionGeneration == connectionGeneration,
                  colorRelayAdapter === adapter else {
                await adapter.disconnect()
                return
            }
            switch outcome {
            case .connected:
                colorRelayDevice = device
                colorRelayState = .connected
                colorRelayMessage = "Color buttons route through \(device.name) via HDMI-CEC."
                ColorRelayStore.save(primaryDeviceID: selectedDevice.id, relayDeviceID: device.id)
            case .pairingRequired:
                await adapter.disconnect()
                colorRelayAdapter = nil
                colorRelayState = .failed("Pair the relay TV first.")
                colorRelayMessage = "Connect to \(device.name) normally once to pair it, then reconnect to \(selectedDevice.name)."
            }
        } catch {
            guard generation == colorRelayGeneration,
                  primaryConnectionGeneration == connectionGeneration else {
                return
            }
            await adapter.disconnect()
            if colorRelayAdapter === adapter {
                colorRelayAdapter = nil
            }
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

    func presentTextInput(
        context: RemoteTextInputContext = RemoteTextInputContext(),
        automaticallyDetected: Bool = false
    ) {
        guard isConnected, let activeAdapter else { return }
        if automaticallyDetected,
           let textInputDismissedAt,
           Date().timeIntervalSince(textInputDismissedAt) < 1 {
            return
        }
        guard textInputSession == nil else { return }

        liveText = context.text
        textInputSession = RemoteTextInputSession(
            initialText: context.text,
            fieldLabel: context.label,
            wasAutomaticallyDetected: automaticallyDetected
        )
        let previousTask = textUpdateTask
        textUpdateTask = Task { @MainActor [weak self] in
            await previousTask?.value
            guard !Task.isCancelled else { return }
            do {
                try await activeAdapter.beginTextInput()
            } catch {
                self?.fail(error, preserveConnection: true)
            }
        }
    }

    private func handleTextInputContext(
        _ context: RemoteTextInputContext,
        automaticallyDetected: Bool
    ) {
        guard textInputSession != nil else {
            presentTextInput(
                context: context,
                automaticallyDetected: automaticallyDetected
            )
            return
        }

        if liveText != context.text {
            liveText = context.text
        }
    }

    func updateLiveText(_ newText: String) {
        guard textInputSession != nil,
              let activeAdapter,
              newText != liveText else {
            return
        }

        let previousText = liveText
        liveText = newText
        let previousTask = textUpdateTask
        textUpdateTask = Task { @MainActor [weak self] in
            await previousTask?.value
            guard !Task.isCancelled else { return }
            do {
                try await activeAdapter.updateText(from: previousText, to: newText)
                self?.errorMessage = nil
            } catch {
                self?.fail(error, preserveConnection: true)
            }
        }
    }

    func dismissTextInput() {
        textInputSession = nil
        textInputDismissedAt = Date()
    }

    func closeTVKeyboard() async {
        // Intentionally keep textInputSession alive. Google TV applies IME edits only
        // after its on-screen keyboard is closed, while the phone remains the editor.
        await textUpdateTask?.value
        await send(.back)
    }

    private func discover(using adapter: TVRemoteAdapter) async -> DiscoveryResult {
        do {
            return DiscoveryResult(
                devices: try await adapter.discover(timeout: 2.5),
                errorMessage: nil
            )
        } catch is CancellationError {
            return DiscoveryResult(devices: [], errorMessage: nil)
        } catch {
            return DiscoveryResult(
                devices: [],
                errorMessage: "\(adapter.platform.displayName): \(error.localizedDescription)"
            )
        }
    }

    private func adapter(for platform: TVPlatform) -> TVRemoteAdapter {
        switch platform {
        case .roku: rokuAdapter
        case .googleTV: googleTVAdapter
        case .appleTV: appleTVAdapter
        }
    }

    private func configurePrimaryAdapterCallbacks(_ adapter: TVRemoteAdapter) {
        let platform = adapter.platform
        adapter.onTextInputRequested = { [weak self] context in
            self?.handleTextInputContext(context, automaticallyDetected: true)
        }
        adapter.onTextInputEnded = { [weak self] in
            guard self?.textInputSession?.wasAutomaticallyDetected == true else { return }
            self?.dismissTextInput()
        }
        adapter.onConnectionEvent = { [weak self] event in
            self?.handlePrimaryConnectionEvent(event, platform: platform)
        }
    }

    private func handlePrimaryConnectionEvent(
        _ event: RemoteAdapterConnectionEvent,
        platform: TVPlatform
    ) {
        guard selectedDevice?.platform == platform,
              activeAdapter === adapter(for: platform) else {
            return
        }

        switch event {
        case .restored:
            guard state == .connected, let selectedDevice else { return }
            errorMessage = nil
            statusMessage = "Connected to \(selectedDevice.name)."

        case .lost(let message):
            guard state == .connected else { return }
            textUpdateTask?.cancel()
            textUpdateTask = nil
            textInputSession = nil
            liveText = ""
            activeAdapter = nil
            state = .failed(message)
            errorMessage = message
            statusMessage = message
        }
    }

    private func handleColorRelayConnectionEvent(
        _ event: RemoteAdapterConnectionEvent,
        generation: Int
    ) {
        guard generation == colorRelayGeneration else { return }

        switch event {
        case .restored:
            guard colorRelayState == .connected, let colorRelayDevice else { return }
            colorRelayMessage = "Color buttons route through \(colorRelayDevice.name) via HDMI-CEC."

        case .lost(let message):
            guard colorRelayState == .connected else { return }
            colorRelayAdapter = nil
            colorRelayState = .failed(message)
            colorRelayMessage = "The color-button relay disconnected: \(message)"
        }
    }

    private func restoreColorRelay(
        for primaryDevice: RemoteDevice,
        connectionGeneration: Int
    ) async {
        guard connectionGeneration == self.connectionGeneration,
              selectedDevice?.id == primaryDevice.id,
              primaryDevice.platform == .googleTV,
              let relayID = ColorRelayStore.relayDeviceID(for: primaryDevice.id),
              let relayDevice = devices.first(where: { $0.id == relayID }) else {
            return
        }
        await connectColorRelay(to: relayDevice)
    }

    private func disconnectColorRelay(clearPreference: Bool) async {
        colorRelayGeneration &+= 1
        let primaryDeviceID = selectedDevice?.id
        let adapter = colorRelayAdapter
        colorRelayAdapter = nil
        adapter?.onConnectionEvent = nil
        colorRelayDevice = nil
        colorRelayState = .disconnected
        colorRelayMessage = nil
        if clearPreference, let primaryDeviceID {
            ColorRelayStore.remove(primaryDeviceID: primaryDeviceID)
        }
        await adapter?.disconnect()
    }

    private func finishConnection(to device: RemoteDevice) {
        RecentDeviceStore.save(device)
        availableDeviceIDs.insert(device.id)
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
        guard !preserveConnection else { return }
        statusMessage = message
        state = .failed(message)
    }
}

private struct DiscoveryResult {
    let devices: [RemoteDevice]
    let errorMessage: String?
}
