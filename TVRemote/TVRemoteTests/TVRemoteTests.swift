import XCTest
@testable import TVRemote

final class TVRemoteTests: XCTestCase {
    @MainActor
    func testRokuCommandMapping() {
        XCTAssertEqual(RokuAdapter.keyName(for: .home), "Home")
        XCTAssertEqual(RokuAdapter.keyName(for: .playPause), "Play")
        XCTAssertEqual(RokuAdapter.keyName(for: .volumeUp), "VolumeUp")
        XCTAssertEqual(RokuAdapter.keyName(for: .digit7), "Lit_7")
        XCTAssertEqual(RokuAdapter.keyName(for: .delete), "Backspace")
        XCTAssertEqual(RokuAdapter.keyName(for: .menu), "Info")
        XCTAssertNil(RokuAdapter.keyName(for: .red))
        XCTAssertNil(RokuAdapter.keyName(for: .blue))
        XCTAssertNil(RokuAdapter.keyName(for: .input))
    }

    @MainActor
    func testRokuBaseURLSupportsIPv4AndIPv6() {
        XCTAssertEqual(
            RokuAdapter.baseURL(host: "192.168.1.20", port: 8060)?.absoluteString,
            "http://192.168.1.20:8060/"
        )
        XCTAssertEqual(
            RokuAdapter.baseURL(host: "fe80::1", port: 8060)?.absoluteString,
            "http://[fe80::1]:8060/"
        )
    }

    func testRokuDeviceInfoParsing() {
        let xml = "<device-info><user-device-name>Living &amp; Room</user-device-name></device-info>"
        XCTAssertEqual(
            RokuDeviceInfoParser.value(for: "user-device-name", in: xml),
            "Living & Room"
        )
    }

    func testGoogleTVColorKeyCodes() async {
        let codes = await MainActor.run {
            [
                GoogleTVAdapter.keyCode(for: .red),
                GoogleTVAdapter.keyCode(for: .green),
                GoogleTVAdapter.keyCode(for: .yellow),
                GoogleTVAdapter.keyCode(for: .blue)
            ]
        }
        XCTAssertEqual(codes, [183, 184, 185, 186])
    }

    func testGoogleTVColorCommandDetection() async {
        let values = await MainActor.run {
            [
                GoogleTVAdapter.isColorCommand(.red),
                GoogleTVAdapter.isColorCommand(.blue),
                GoogleTVAdapter.isColorCommand(.home)
            ]
        }
        XCTAssertEqual(values, [true, true, false])
    }

    func testGoogleTVAdditionalControlKeyCodes() async {
        let codes = await MainActor.run {
            [
                GoogleTVAdapter.keyCode(for: .digit0),
                GoogleTVAdapter.keyCode(for: .digit9),
                GoogleTVAdapter.keyCode(for: .delete),
                GoogleTVAdapter.keyCode(for: .input),
                GoogleTVAdapter.keyCode(for: .menu),
                GoogleTVAdapter.keyCode(for: .info),
                GoogleTVAdapter.keyCode(for: .guide),
                GoogleTVAdapter.keyCode(for: .captions),
                GoogleTVAdapter.keyCode(for: .search)
            ]
        }
        XCTAssertEqual(codes, [7, 16, 67, 178, 82, 165, 172, 175, 84])
    }

    func testGoogleTVTextInputRequestDecoding() async {
        let status = GoogleTVProto.varintField(1, 7)
            + GoogleTVProto.stringField(2, "query")
            + GoogleTVProto.varintField(3, 5)
            + GoogleTVProto.varintField(4, 5)
            + GoogleTVProto.stringField(6, "Search")
        let request = GoogleTVProto.message(field: 2, payload: status)
        let context = await MainActor.run {
            GoogleTVAdapter.textInputContext(fromContainer: request)
        }

        XCTAssertEqual(context?.text, "query")
        XCTAssertEqual(context?.selectionStart, 5)
        XCTAssertEqual(context?.selectionEnd, 5)
        XCTAssertEqual(context?.label, "Search")
        XCTAssertEqual(context?.fieldCounter, 7)
    }

    func testGoogleTVEmptyShowRequestStillDetectsTextInput() async {
        let context = await MainActor.run {
            GoogleTVAdapter.textInputContext(fromShowRequest: Data())
        }

        XCTAssertEqual(context, RemoteTextInputContext())
    }

    func testGoogleTVNegotiatesAdvertisedIMEFeatures() async {
        let values = await MainActor.run {
            let allRequested = GoogleTVAdapter.requestedRemoteFeatures
            return (
                allRequested,
                GoogleTVAdapter.negotiatedRemoteFeatures(
                    supported: allRequested | (1 << 12)
                ),
                GoogleTVAdapter.negotiatedRemoteFeatures(
                    supported: allRequested & ~4
                )
            )
        }

        XCTAssertEqual(values.1, values.0)
        XCTAssertEqual(values.2 & 4, 0)
    }

    func testGoogleTVTextInputBatchEditDecoding() async {
        let textObject = GoogleTVProto.varintField(1, 2)
            + GoogleTVProto.varintField(2, 2)
            + GoogleTVProto.stringField(3, "hey")
        let editInfo = GoogleTVProto.varintField(1, 1)
            + GoogleTVProto.message(field: 2, payload: textObject)
        let batchEdit = GoogleTVProto.varintField(1, 3)
            + GoogleTVProto.varintField(2, 9)
            + GoogleTVProto.message(field: 3, payload: editInfo)
        let context = await MainActor.run {
            GoogleTVAdapter.textInputContext(fromBatchEdit: batchEdit)
        }

        XCTAssertEqual(context?.text, "hey")
        XCTAssertEqual(context?.selectionStart, 2)
        XCTAssertEqual(context?.selectionEnd, 2)
        XCTAssertEqual(context?.fieldCounter, 9)
    }

    func testGoogleTVTextInputBatchEncoding() async {
        let message = await MainActor.run {
            GoogleTVAdapter.imeBatchEditMessage(
                text: "query",
                imeCounter: 3,
                fieldCounter: 7,
                insert: 1
            )
        }
        let batch = GoogleTVProto.fields(message)[21]
        let edit = batch.flatMap { GoogleTVProto.fields($0)[3] }
        let status = edit.flatMap { GoogleTVProto.fields($0)[2] }

        XCTAssertNotNil(batch)
        XCTAssertEqual(GoogleTVProto.intField(batch!, number: 1), 3)
        XCTAssertEqual(GoogleTVProto.intField(batch!, number: 2), 7)
        XCTAssertEqual(GoogleTVProto.intField(edit!, number: 1), 1)
        XCTAssertEqual(
            String(data: GoogleTVProto.fields(status!)[3]!, encoding: .utf8),
            "query"
        )
        XCTAssertEqual(GoogleTVProto.intField(status!, number: 1), 4)
        XCTAssertEqual(GoogleTVProto.intField(status!, number: 2), 4)
    }

    func testGoogleTVProtoRoundTrip() {
        let nested = GoogleTVProto.varintField(1, 623)
            + GoogleTVProto.stringField(2, "remote")
        let message = GoogleTVProto.message(field: 10, payload: nested)
        let decoded = GoogleTVProto.fields(message)
        XCTAssertEqual(GoogleTVProto.intField(decoded[10]!, number: 1), 623)
        XCTAssertEqual(
            String(data: GoogleTVProto.fields(decoded[10]!)[2]!, encoding: .utf8),
            "remote"
        )
    }

    func testGoogleTVPairingRequestEnvelope() {
        let request = GoogleTVPairingMessage.request(clientName: "Test iPhone")
        let fields = GoogleTVProto.fields(request)
        XCTAssertEqual(GoogleTVProto.intField(request, number: 1), 2)
        XCTAssertEqual(GoogleTVProto.intField(request, number: 2), 200)
        XCTAssertNotNil(fields[10])
        XCTAssertEqual(
            String(data: GoogleTVProto.fields(fields[10]!)[2]!, encoding: .utf8),
            "Test iPhone"
        )
    }

    func testGoogleTVFramePrefixMatchesPayloadLength() {
        let payload = GoogleTVPairingMessage.options()
        let frame = GoogleTVProto.framed(payload)
        let length = GoogleTVProto.readVarint(frame, at: 0)
        XCTAssertEqual(length?.value, payload.count)
        XCTAssertEqual(frame.dropFirst(length?.bytes ?? 0), payload[...])
    }

    func testCapabilitiesArePlatformAware() {
        XCTAssertFalse(RemoteCapabilities.roku.supportsColorButtons)
        XCTAssertTrue(RemoteCapabilities.googleTV.supportsColorButtons)
        XCTAssertFalse(RemoteCapabilities.appleTV.supportsColorButtons)
        XCTAssertTrue(RemoteCapabilities.roku.supportsKeyboard)
        XCTAssertTrue(RemoteCapabilities.appleTV.supportsKeyboard)
        XCTAssertTrue(RemoteCapabilities.googleTV.supportsNumberPad)
        XCTAssertTrue(RemoteCapabilities.roku.extraCommands.contains(.menu))
        XCTAssertFalse(RemoteCapabilities.appleTV.supportsNumberPad)
    }

    @MainActor
    func testRokuCapabilitiesComeFromDeviceInfo() {
        let xml = """
        <device-info>
            <is-tv>false</is-tv>
            <supports-tv-power-control>true</supports-tv-power-control>
            <supports-audio-volume-control>true</supports-audio-volume-control>
            <supports-tv-tuner>false</supports-tv-tuner>
        </device-info>
        """
        let capabilities = RokuAdapter.capabilities(fromDeviceInfoXML: xml)

        XCTAssertTrue(capabilities.supportsPower)
        XCTAssertTrue(capabilities.supportsVolume)
        XCTAssertFalse(capabilities.supportsChannel)
        XCTAssertTrue(capabilities.supportsNumberPad)
    }

    func testRefreshReconcilesManualGoogleTVWithBonjourDiscovery() async {
        let recent = RemoteDevice(
            name: "Living Room",
            host: "192.168.1.20",
            port: 6466,
            platform: .googleTV
        )
        let discovered = RemoteDevice(
            name: "Android TV",
            host: "192.168.1.20",
            port: 6466,
            platform: .googleTV,
            serviceName: "Android TV"
        )

        let result = await MainActor.run {
            RemoteCoordinator.reconcileDevices(
                recent: [recent],
                discovered: [discovered],
                connectedDevice: nil
            )
        }

        XCTAssertEqual(result.devices.count, 1)
        XCTAssertEqual(result.devices.first?.id, recent.id)
        XCTAssertEqual(result.devices.first?.name, recent.name)
        XCTAssertEqual(result.devices.first?.serviceName, discovered.serviceName)
        XCTAssertEqual(result.availableIDs, [recent.id])
    }

    func testColorRelayMappingPersistence() {
        let primaryID = "test-primary-\(UUID().uuidString)"
        let relayID = "test-relay-\(UUID().uuidString)"
        ColorRelayStore.save(primaryDeviceID: primaryID, relayDeviceID: relayID)
        XCTAssertEqual(ColorRelayStore.relayDeviceID(for: primaryID), relayID)

        ColorRelayStore.removeReferences(to: relayID)
        XCTAssertNil(ColorRelayStore.relayDeviceID(for: primaryID))
    }

    @MainActor
    func testCloseTVKeyboardFlushesTextAndKeepsPhoneEditorOpen() async {
        let roku = TestRemoteAdapter(platform: .roku)
        let coordinator = makeCoordinator(roku: roku)
        let device = RemoteDevice(
            name: "Test Roku",
            host: "192.0.2.10",
            platform: .roku
        )

        await coordinator.connect(to: device)
        coordinator.presentTextInput()
        coordinator.updateLiveText("hello")
        await coordinator.closeTVKeyboard()

        XCTAssertEqual(
            Array(roku.events.suffix(3)),
            ["beginTextInput", "update:->hello", "send:back"]
        )
        XCTAssertNotNil(
            coordinator.textInputSession,
            "Closing the TV keyboard must keep the phone editor open."
        )
        XCTAssertEqual(coordinator.liveText, "hello")
        RecentDeviceStore.remove(device)
    }

    @MainActor
    func testLatestConnectionAttemptWins() async {
        let roku = TestRemoteAdapter(platform: .roku, suspendsConnection: true)
        let google = TestRemoteAdapter(platform: .googleTV, suspendsConnection: true)
        let coordinator = makeCoordinator(roku: roku, google: google)
        let rokuDevice = RemoteDevice(
            name: "Slow Roku",
            host: "192.0.2.11",
            platform: .roku
        )
        let googleDevice = RemoteDevice(
            name: "Fast Google TV",
            host: "192.0.2.12",
            platform: .googleTV
        )

        let firstConnect = Task { await coordinator.connect(to: rokuDevice) }
        while !roku.hasPendingConnection { await Task.yield() }

        let secondConnect = Task { await coordinator.connect(to: googleDevice) }
        while !google.hasPendingConnection { await Task.yield() }

        google.completeConnection(with: .connected)
        await secondConnect.value
        roku.completeConnection(with: .connected)
        await firstConnect.value

        XCTAssertEqual(coordinator.selectedDevice, googleDevice)
        XCTAssertEqual(coordinator.state, .connected)

        await coordinator.send(.home)
        XCTAssertTrue(google.events.contains("send:home"))
        XCTAssertFalse(roku.events.contains("send:home"))
        RecentDeviceStore.remove(rokuDevice)
        RecentDeviceStore.remove(googleDevice)
    }

    @MainActor
    func testAdapterConnectionLossExitsConnectedUI() async {
        let google = TestRemoteAdapter(platform: .googleTV)
        let coordinator = makeCoordinator(google: google)
        let device = RemoteDevice(
            name: "Google TV",
            host: "192.0.2.13",
            platform: .googleTV
        )

        await coordinator.connect(to: device)
        google.emitConnectionEvent(.lost("Connection dropped"))

        XCTAssertEqual(coordinator.state, .failed("Connection dropped"))
        XCTAssertFalse(coordinator.isConnected)
        XCTAssertEqual(coordinator.errorMessage, "Connection dropped")
        RecentDeviceStore.remove(device)
    }

    @MainActor
    func testPairingCanBeCancelledCleanly() async {
        let prompt = PairingPrompt(
            title: "Pair",
            message: "Enter code",
            placeholder: "A1B2C3",
            keyboard: .hexadecimal
        )
        let google = TestRemoteAdapter(
            platform: .googleTV,
            connectionOutcome: .pairingRequired(prompt)
        )
        let coordinator = makeCoordinator(google: google)
        let device = RemoteDevice(
            name: "Unpaired Google TV",
            host: "192.0.2.14",
            platform: .googleTV
        )

        await coordinator.connect(to: device)
        XCTAssertEqual(coordinator.state, .pairing)

        await coordinator.cancelPairing()

        XCTAssertEqual(coordinator.state, .disconnected)
        XCTAssertNil(coordinator.pairingPrompt)
        XCTAssertNil(coordinator.selectedDevice)
    }

    @MainActor
    private func makeCoordinator(
        roku: TestRemoteAdapter? = nil,
        google: TestRemoteAdapter? = nil,
        apple: TestRemoteAdapter? = nil
    ) -> RemoteCoordinator {
        let roku = roku ?? TestRemoteAdapter(platform: .roku)
        let google = google ?? TestRemoteAdapter(platform: .googleTV)
        let apple = apple ?? TestRemoteAdapter(platform: .appleTV)
        return RemoteCoordinator(
            rokuAdapter: roku,
            googleTVAdapter: google,
            appleTVAdapter: apple,
            initialDevices: [],
            colorRelayAdapterFactory: { TestRemoteAdapter(platform: .googleTV) }
        )
    }
}

@MainActor
private final class TestRemoteAdapter: TVRemoteAdapter {
    let platform: TVPlatform
    let capabilities: RemoteCapabilities
    var onTextInputRequested: ((RemoteTextInputContext) -> Void)?
    var onTextInputEnded: (() -> Void)?
    var onConnectionEvent: ((RemoteAdapterConnectionEvent) -> Void)?
    private(set) var events: [String] = []
    private var connectContinuation: CheckedContinuation<ConnectionOutcome, Error>?
    private let suspendsConnection: Bool
    private let connectionOutcome: ConnectionOutcome

    var hasPendingConnection: Bool {
        connectContinuation != nil
    }

    init(
        platform: TVPlatform,
        suspendsConnection: Bool = false,
        connectionOutcome: ConnectionOutcome = .connected
    ) {
        self.platform = platform
        self.suspendsConnection = suspendsConnection
        self.connectionOutcome = connectionOutcome
        capabilities = switch platform {
        case .roku: .roku
        case .googleTV: .googleTV
        case .appleTV: .appleTV
        }
    }

    func discover(timeout: TimeInterval) async throws -> [RemoteDevice] {
        []
    }

    func connect(to device: RemoteDevice) async throws -> ConnectionOutcome {
        events.append("connect:\(device.id)")
        guard suspendsConnection else { return connectionOutcome }
        return try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
        }
    }

    func completeConnection(with outcome: ConnectionOutcome) {
        let continuation = connectContinuation
        connectContinuation = nil
        continuation?.resume(returning: outcome)
    }

    func emitConnectionEvent(_ event: RemoteAdapterConnectionEvent) {
        onConnectionEvent?(event)
    }

    func submitPIN(_ pin: String) async throws {}

    func disconnect() async {
        events.append("disconnect")
    }

    func send(_ command: RemoteCommand) async throws {
        events.append("send:\(command.rawValue)")
    }

    func sendText(_ text: String) async throws {
        events.append("sendText:\(text)")
    }

    func beginTextInput() async throws {
        events.append("beginTextInput")
    }

    func updateText(from previousText: String, to newText: String) async throws {
        events.append("update:\(previousText)->\(newText)")
    }
}
