import Foundation
import Network
import OSLog
import Security
import UIKit

private let googleTVLog = Logger(subsystem: "com.sbarai.TVRemote", category: "GoogleTV")

@MainActor
final class GoogleTVAdapter: TVRemoteAdapter {
    let platform = TVPlatform.googleTV
    let capabilities = RemoteCapabilities.googleTV
    var onTextInputRequested: ((RemoteTextInputContext) -> Void)?
    var onTextInputEnded: (() -> Void)?
    var onConnectionEvent: ((RemoteAdapterConnectionEvent) -> Void)?

    private enum Mode: Sendable {
        case pairing
        case remote
    }

    private enum SessionState: Equatable {
        case idle
        case opening
        case waitingForPIN
        case paired
        case connected
        case failed(String)
    }

    private let networkQueue = DispatchQueue(label: "com.sbarai.TVRemote.google-tv")
    private lazy var identity = GoogleTVIdentityStore.loadIdentity()
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var serverCertificateData: Data?
    private var currentDevice: RemoteDevice?
    private var mode = Mode.remote
    private var sessionState = SessionState.idle
    private var activeRemoteFeatures = GoogleTVAdapter.requestedRemoteFeatures
    private var pendingTrustFailureMessage: String?
    private var imeCounter = 0
    private var imeFieldCounter = 0
    private var shouldReconnect = false
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?

    // Feature bits used by the Android TV Remote v2 protocol:
    // ping, key input, IME, power, volume, and app links.
    static let requestedRemoteFeatures = 1 | 2 | 4 | 32 | 64 | 512

    func discover(timeout: TimeInterval) async throws -> [RemoteDevice] {
        let services = await BonjourServiceScanner.scan(
            serviceType: "_androidtvremote2._tcp.",
            timeout: timeout
        )
        return services.map {
            RemoteDevice(
                name: $0.name,
                host: $0.host,
                port: $0.port,
                platform: .googleTV,
                serviceName: $0.name
            )
        }
    }

    func connect(to device: RemoteDevice) async throws -> ConnectionOutcome {
        guard identity != nil else {
            throw TVRemoteError.protocolFailure("Could not create a secure Google TV pairing identity.")
        }
        currentDevice = device
        shouldReconnect = true
        reconnectAttempts = 0
        imeCounter = 0
        imeFieldCounter = 0
        if KeychainStore.load(account: pairingAccount(for: device)) != nil {
            open(host: device.host, port: device.port ?? 6466, mode: .remote)
            try await wait(for: { $0 == .connected }, timeout: 6)
            return .connected
        }

        open(host: device.host, port: 6467, mode: .pairing)
        try await wait(for: { $0 == .waitingForPIN }, timeout: 8)
        return .pairingRequired(
            PairingPrompt(
                title: "Pair with \(device.name)",
                message: "Enter the six-character code shown on your TV.",
                placeholder: "A1B2C3",
                keyboard: .hexadecimal
            )
        )
    }

    func submitPIN(_ pin: String) async throws {
        let normalized = pin.uppercased().filter(\.isHexDigit)
        guard normalized.count == 6 else {
            throw TVRemoteError.invalidPIN("The Google TV code must contain six hexadecimal characters.")
        }
        guard let identity, let serverCertificateData,
              let serverCertificate = SecCertificateCreateWithData(
                nil,
                serverCertificateData as CFData
              ),
              let digest = GoogleTVPairingSecret.make(
                pin: normalized,
                identity: identity,
                serverCertificate: serverCertificate
              ) else {
            throw TVRemoteError.invalidPIN("That code did not match the TV. Start pairing again.")
        }

        sendPayload(GoogleTVPairingMessage.secret(digest))
        try await wait(for: { $0 == .paired }, timeout: 8)
        guard let device = currentDevice else { throw TVRemoteError.notConnected }
        try KeychainStore.save(
            serverCertificateData,
            account: serverCertificateAccount(for: device)
        )
        try KeychainStore.save(Data([1]), account: pairingAccount(for: device))

        open(host: device.host, port: device.port ?? 6466, mode: .remote)
        try await wait(for: { $0 == .connected }, timeout: 8)
    }

    func disconnect() async {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll()
        currentDevice = nil
        sessionState = .idle
        serverCertificateData = nil
        pendingTrustFailureMessage = nil
        activeRemoteFeatures = Self.requestedRemoteFeatures
        imeCounter = 0
        imeFieldCounter = 0
    }

    func forgetPairing(for device: RemoteDevice) {
        KeychainStore.delete(account: pairingAccount(for: device))
        KeychainStore.delete(account: serverCertificateAccount(for: device))
    }

    func send(_ command: RemoteCommand) async throws {
        guard sessionState == .connected else { throw TVRemoteError.notConnected }
        let keyCode = Self.keyCode(for: command)
        sendKeyCode(keyCode, direction: 3)
    }

    func sendText(_ text: String) async throws {
        guard sessionState == .connected else { throw TVRemoteError.notConnected }
        guard !text.isEmpty else { return }
        googleTVLog.debug(
            "Sending IME insert with imeCounter=\(self.imeCounter), fieldCounter=\(self.imeFieldCounter), length=\(text.utf16.count)."
        )
        sendPayload(
            Self.imeBatchEditMessage(
                text: text,
                imeCounter: imeCounter,
                fieldCounter: imeFieldCounter,
                insert: 1
            )
        )
    }

    func beginTextInput() async throws {
        guard sessionState == .connected else { throw TVRemoteError.notConnected }
    }

    func updateText(from previousText: String, to newText: String) async throws {
        guard sessionState == .connected else { throw TVRemoteError.notConnected }
        guard previousText != newText else { return }

        if previousText.hasPrefix(newText) {
            for _ in 0..<previousText.dropFirst(newText.count).count {
                sendKeyCode(67, direction: 3)
            }
        } else if newText.hasPrefix(previousText) {
            let addedText = String(newText.dropFirst(previousText.count))
            try await sendText(addedText)
        } else {
            for _ in previousText {
                sendKeyCode(67, direction: 3)
            }
            try await sendText(newText)
        }
    }

    private func open(host: String, port: UInt16, mode: Mode) {
        guard let identity else {
            sessionState = .failed("Google TV pairing identity is unavailable.")
            return
        }
        guard let networkIdentity = sec_identity_create(identity) else {
            sessionState = .failed("The Google TV pairing identity is invalid.")
            return
        }
        guard let networkPort = NWEndpoint.Port(rawValue: port) else {
            sessionState = .failed("The Google TV port is invalid.")
            return
        }

        connection?.cancel()
        receiveBuffer.removeAll()
        sessionState = .opening
        self.mode = mode
        pendingTrustFailureMessage = nil
        activeRemoteFeatures = Self.requestedRemoteFeatures

        let expectedServerCertificate = mode == .remote
            ? currentDevice.flatMap {
                KeychainStore.load(account: serverCertificateAccount(for: $0))
            }
            : nil

        let tls = NWProtocolTLS.Options()
        let securityOptions = tls.securityProtocolOptions
        sec_protocol_options_set_local_identity(securityOptions, networkIdentity)
        sec_protocol_options_set_verify_block(
            securityOptions,
            { [weak self] _, trust, complete in
                let certificateData: Data?
                if let secTrust = sec_trust_copy_ref(trust).takeRetainedValue() as SecTrust?,
                   let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate] {
                    certificateData = chain.first.map {
                        SecCertificateCopyData($0) as Data
                    }
                } else {
                    certificateData = nil
                }

                let certificateMatches = expectedServerCertificate == nil
                    || expectedServerCertificate == certificateData
                let shouldTrust = certificateData != nil
                    && (mode == .pairing || certificateMatches)

                Task { @MainActor in
                    guard let self else {
                        complete(false)
                        return
                    }
                    self.serverCertificateData = certificateData
                    if !shouldTrust {
                        self.pendingTrustFailureMessage =
                            "The Google TV identity changed. Forget the device and pair it again if the TV was reset."
                    }
                    complete(shouldTrust)
                }
            },
            networkQueue
        )

        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: networkPort,
            using: parameters
        )
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handleConnectionState(state) }
        }
        connection.start(queue: networkQueue)
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            receiveNext()
            if mode == .pairing {
                sendPayload(GoogleTVPairingMessage.request(clientName: UIDevice.current.name))
            }
        case .failed(let error):
            handleSessionFailure(pendingTrustFailureMessage ?? error.localizedDescription)
        case .cancelled:
            break
        default:
            break
        }
    }

    private func receiveNext() {
        guard let receivingConnection = connection else { return }
        receivingConnection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65_536
        ) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connection === receivingConnection else { return }
                if let data {
                    self.receiveBuffer.append(data)
                    self.consumeFrames()
                }
                if let error {
                    self.handleSessionFailure(error.localizedDescription)
                } else if !complete {
                    self.receiveNext()
                } else {
                    self.handleSessionFailure("Google TV closed the connection.")
                }
            }
        }
    }

    private func consumeFrames() {
        while let length = GoogleTVProto.readVarint(receiveBuffer, at: 0),
              receiveBuffer.count >= length.bytes + length.value {
            let payload = receiveBuffer.subdata(
                in: length.bytes..<(length.bytes + length.value)
            )
            receiveBuffer.removeSubrange(0..<(length.bytes + length.value))
            handle(payload)
        }
    }

    private func handle(_ payload: Data) {
        let fields = GoogleTVProto.fields(payload)
        if mode == .pairing {
            if fields[11] != nil {
                sendPayload(GoogleTVPairingMessage.options())
            } else if fields[20] != nil {
                sendPayload(GoogleTVPairingMessage.configuration())
            } else if fields[31] != nil {
                sessionState = .waitingForPIN
            } else if fields[41] != nil {
                sessionState = .paired
            }
            return
        }

        if let configure = fields[1] {
            let supportedFeatures = GoogleTVProto.intField(configure, number: 1)
                ?? Self.requestedRemoteFeatures
            activeRemoteFeatures = Self.negotiatedRemoteFeatures(
                supported: supportedFeatures
            )
            let client = GoogleTVProto.varintField(3, 1)
                + GoogleTVProto.stringField(4, "1")
                + GoogleTVProto.stringField(5, "ios-tv-remote")
                + GoogleTVProto.stringField(6, "1.0")
            let response = GoogleTVProto.varintField(1, activeRemoteFeatures)
                + GoogleTVProto.message(field: 2, payload: client)
            sendPayload(GoogleTVProto.message(field: 1, payload: response))
        } else if fields[2] != nil {
            sendPayload(
                GoogleTVProto.message(
                    field: 2,
                    payload: GoogleTVProto.varintField(1, activeRemoteFeatures)
                )
            )
        } else if let ping = fields[8] {
            let value = GoogleTVProto.intField(ping, number: 1) ?? 0
            sendPayload(
                GoogleTVProto.message(
                    field: 9,
                    payload: GoogleTVProto.varintField(1, value)
                )
            )
        } else if let imeKeyInject = fields[20] {
            if let context = Self.textInputContext(fromContainer: imeKeyInject) {
                handleTextInputContext(context, source: "IME key-inject status")
            }
        } else if let ime = fields[21] {
            imeCounter = GoogleTVProto.intField(ime, number: 1) ?? imeCounter
            imeFieldCounter = GoogleTVProto.intField(ime, number: 2) ?? imeFieldCounter
            googleTVLog.debug(
                "Received IME batch state with imeCounter=\(self.imeCounter), fieldCounter=\(self.imeFieldCounter)."
            )
            if let context = Self.textInputContext(fromBatchEdit: ime) {
                handleTextInputContext(context, source: "IME batch-edit status")
            }
        } else if let showRequest = fields[22] {
            handleTextInputContext(
                Self.textInputContext(fromShowRequest: showRequest),
                source: "IME show request"
            )
        } else if fields[40] != nil {
            reconnectAttempts = 0
            sessionState = .connected
            persistServerCertificateIfNeeded()
            onConnectionEvent?(.restored)
        }
    }

    private func sendPayload(_ payload: Data) {
        connection?.send(
            content: GoogleTVProto.framed(payload),
            completion: .contentProcessed { [weak self] error in
                guard let error else { return }
                Task { @MainActor in self?.handleSessionFailure(error.localizedDescription) }
            }
        )
    }

    private func sendKeyCode(_ keyCode: Int, direction: Int) {
        let keyEvent = GoogleTVProto.varintField(1, keyCode)
            + GoogleTVProto.varintField(2, direction)
        sendPayload(GoogleTVProto.message(field: 10, payload: keyEvent))
    }

    private func handleTextInputContext(_ context: RemoteTextInputContext, source: String) {
        googleTVLog.debug(
            "Detected focused text field from \(source, privacy: .public), statusCounter=\(context.fieldCounter ?? -1)."
        )
        onTextInputRequested?(context)
    }

    private func handleSessionFailure(_ message: String) {
        if pendingTrustFailureMessage != nil {
            shouldReconnect = false
            sessionState = .failed(message)
            onConnectionEvent?(.lost(message))
            return
        }

        let wasConnected = sessionState == .connected
        guard mode == .remote,
              shouldReconnect,
              currentDevice != nil,
              (wasConnected || reconnectAttempts > 0) else {
            sessionState = .failed(message)
            return
        }
        guard reconnectAttempts < 3 else {
            let message = "Lost the Google TV connection after three reconnect attempts."
            sessionState = .failed(message)
            onConnectionEvent?(.lost(message))
            return
        }

        reconnectAttempts += 1
        sessionState = .opening
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled, let device = self.currentDevice else { return }
            self.open(host: device.host, port: device.port ?? 6466, mode: .remote)
        }
    }

    private func wait(
        for predicate: (SessionState) -> Bool,
        timeout: TimeInterval
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(sessionState) { return }
            if case .failed(let message) = sessionState {
                throw TVRemoteError.connectionFailed(message)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw TVRemoteError.timedOut("The TV did not respond in time.")
    }

    private func persistServerCertificateIfNeeded() {
        guard let currentDevice, let serverCertificateData,
              KeychainStore.load(account: serverCertificateAccount(for: currentDevice)) == nil else {
            return
        }
        do {
            try KeychainStore.save(
                serverCertificateData,
                account: serverCertificateAccount(for: currentDevice)
            )
        } catch {
            googleTVLog.error(
                "Could not pin Google TV certificate: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func pairingAccount(for device: RemoteDevice) -> String {
        "google-tv.paired.\(device.id)"
    }

    private func serverCertificateAccount(for device: RemoteDevice) -> String {
        "google-tv.server-certificate.\(device.id)"
    }

    static func negotiatedRemoteFeatures(supported: Int) -> Int {
        supported & requestedRemoteFeatures
    }

    static func keyCode(for command: RemoteCommand) -> Int {
        switch command {
        case .up: 19
        case .down: 20
        case .left: 21
        case .right: 22
        case .select: 23
        case .back: 4
        case .home: 3
        case .playPause: 85
        case .rewind: 89
        case .fastForward: 90
        case .volumeUp: 24
        case .volumeDown: 25
        case .mute: 164
        case .power: 26
        case .channelUp: 166
        case .channelDown: 167
        case .red: 183
        case .green: 184
        case .yellow: 185
        case .blue: 186
        case .digit0: 7
        case .digit1: 8
        case .digit2: 9
        case .digit3: 10
        case .digit4: 11
        case .digit5: 12
        case .digit6: 13
        case .digit7: 14
        case .digit8: 15
        case .digit9: 16
        case .delete: 67
        case .input: 178
        case .menu: 82
        case .info: 165
        case .guide: 172
        case .captions: 175
        case .search: 84
        }
    }

    static func isColorCommand(_ command: RemoteCommand) -> Bool {
        switch command {
        case .red, .green, .yellow, .blue:
            true
        default:
            false
        }
    }

    static func textInputContext(fromContainer container: Data) -> RemoteTextInputContext? {
        guard let status = GoogleTVProto.fields(container)[2] else { return nil }
        let fields = GoogleTVProto.fields(status)
        let text = fields[2].flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let selectionStart = GoogleTVProto.intField(status, number: 3) ?? text.utf16.count
        let selectionEnd = GoogleTVProto.intField(status, number: 4) ?? selectionStart
        let label = fields[6].flatMap { String(data: $0, encoding: .utf8) }
        return RemoteTextInputContext(
            text: text,
            selectionStart: selectionStart,
            selectionEnd: selectionEnd,
            label: label?.isEmpty == false ? label : nil,
            fieldCounter: GoogleTVProto.intField(status, number: 1)
        )
    }

    static func textInputContext(fromShowRequest showRequest: Data) -> RemoteTextInputContext {
        // Some Android TV Remote Service versions send an empty show request.
        // The message itself still means a TV text field gained focus.
        textInputContext(fromContainer: showRequest) ?? RemoteTextInputContext()
    }

    static func textInputContext(fromBatchEdit batchEdit: Data) -> RemoteTextInputContext? {
        guard let editInfo = GoogleTVProto.fields(batchEdit)[3],
              let textObject = GoogleTVProto.fields(editInfo)[2] else {
            return nil
        }
        let fields = GoogleTVProto.fields(textObject)
        let text = fields[3].flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let selectionStart = GoogleTVProto.intField(textObject, number: 1) ?? text.utf16.count
        let selectionEnd = GoogleTVProto.intField(textObject, number: 2) ?? selectionStart
        return RemoteTextInputContext(
            text: text,
            selectionStart: selectionStart,
            selectionEnd: selectionEnd,
            fieldCounter: GoogleTVProto.intField(batchEdit, number: 2)
        )
    }

    static func imeBatchEditMessage(
        text: String,
        imeCounter: Int,
        fieldCounter: Int,
        insert: Int
    ) -> Data {
        let finalPosition = max(text.utf16.count - 1, 0)
        let textFieldStatus = GoogleTVProto.varintField(1, finalPosition)
            + GoogleTVProto.varintField(2, finalPosition)
            + GoogleTVProto.stringField(3, text)
        let edit = GoogleTVProto.varintField(1, insert)
            + GoogleTVProto.message(field: 2, payload: textFieldStatus)
        let batch = GoogleTVProto.varintField(1, imeCounter)
            + GoogleTVProto.varintField(2, fieldCounter)
            + GoogleTVProto.message(field: 3, payload: edit)
        return GoogleTVProto.message(field: 21, payload: batch)
    }
}
