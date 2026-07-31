import Foundation

struct RemoteDevice: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let host: String
    let port: UInt16?
    let platform: TVPlatform
    let serviceName: String?

    init(
        id: String? = nil,
        name: String,
        host: String,
        port: UInt16? = nil,
        platform: TVPlatform,
        serviceName: String? = nil
    ) {
        self.id = id ?? "\(platform.rawValue):\(serviceName ?? host)"
        self.name = name
        self.host = host
        self.port = port
        self.platform = platform
        self.serviceName = serviceName
    }
}

enum RemoteCommand: String, CaseIterable, Hashable, Sendable {
    case up
    case down
    case left
    case right
    case select
    case back
    case home
    case playPause
    case rewind
    case fastForward
    case volumeUp
    case volumeDown
    case mute
    case power
    case channelUp
    case channelDown
    case red
    case green
    case yellow
    case blue
    case digit0
    case digit1
    case digit2
    case digit3
    case digit4
    case digit5
    case digit6
    case digit7
    case digit8
    case digit9
    case delete
    case input
    case menu
    case info
    case guide
    case captions
    case search
}

enum RemoteConnectionState: Equatable, Sendable {
    case disconnected
    case discovering
    case connecting
    case pairing
    case connected
    case failed(String)
}

struct PairingPrompt: Equatable, Sendable {
    let title: String
    let message: String
    let placeholder: String
    let keyboard: PairingKeyboard
}

enum PairingKeyboard: Equatable, Sendable {
    case numeric
    case hexadecimal
}

struct RemoteTextInputContext: Equatable, Sendable {
    let text: String
    let selectionStart: Int
    let selectionEnd: Int
    let label: String?
    let fieldCounter: Int?

    init(
        text: String = "",
        selectionStart: Int = 0,
        selectionEnd: Int = 0,
        label: String? = nil,
        fieldCounter: Int? = nil
    ) {
        self.text = text
        self.selectionStart = selectionStart
        self.selectionEnd = selectionEnd
        self.label = label
        self.fieldCounter = fieldCounter
    }
}

struct RemoteTextInputSession: Identifiable, Equatable, Sendable {
    let id = UUID()
    let initialText: String
    let fieldLabel: String?
    let wasAutomaticallyDetected: Bool
}

enum ConnectionOutcome: Equatable, Sendable {
    case connected
    case pairingRequired(PairingPrompt)
}

protocol TVRemoteAdapter: AnyObject {
    var platform: TVPlatform { get }
    var capabilities: RemoteCapabilities { get }

    func discover(timeout: TimeInterval) async throws -> [RemoteDevice]
    func connect(to device: RemoteDevice) async throws -> ConnectionOutcome
    func submitPIN(_ pin: String) async throws
    func disconnect() async
    func send(_ command: RemoteCommand) async throws
    func sendText(_ text: String) async throws
    func beginTextInput() async throws
    func updateText(from previousText: String, to newText: String) async throws
}

extension TVRemoteAdapter {
    func beginTextInput() async throws {}

    func updateText(from previousText: String, to newText: String) async throws {
        guard newText != previousText else { return }
        try await sendText(newText)
    }
}

enum TVRemoteError: LocalizedError, Equatable {
    case notConnected
    case invalidAddress
    case invalidPIN(String)
    case unsupported(String)
    case timedOut(String)
    case connectionFailed(String)
    case protocolFailure(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Connect to a TV first."
        case .invalidAddress:
            "Enter a valid TV IP address."
        case .invalidPIN(let message),
             .unsupported(let message),
             .timedOut(let message),
             .connectionFailed(let message),
             .protocolFailure(let message):
            message
        }
    }
}
