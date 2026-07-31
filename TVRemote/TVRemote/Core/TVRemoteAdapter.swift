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

enum RemoteCommand: String, CaseIterable, Sendable {
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
