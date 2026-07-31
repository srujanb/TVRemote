import Foundation

enum TVPlatform: String, Codable, CaseIterable, Sendable {
    case roku
    case googleTV
    case appleTV

    var displayName: String {
        switch self {
        case .roku: "Roku"
        case .googleTV: "Google TV"
        case .appleTV: "Apple TV"
        }
    }

    var symbolName: String {
        switch self {
        case .roku: "play.tv"
        case .googleTV: "tv"
        case .appleTV: "appletv"
        }
    }
}

struct RemoteCapabilities: Equatable, Sendable {
    let supportsKeyboard: Bool
    let supportsColorButtons: Bool
    let supportsVolume: Bool
    let supportsPower: Bool
    let supportsChannel: Bool

    static let roku = RemoteCapabilities(
        supportsKeyboard: true,
        supportsColorButtons: false,
        supportsVolume: true,
        supportsPower: true,
        supportsChannel: true
    )

    static let googleTV = RemoteCapabilities(
        supportsKeyboard: true,
        supportsColorButtons: true,
        supportsVolume: true,
        supportsPower: true,
        supportsChannel: true
    )

    static let appleTV = RemoteCapabilities(
        supportsKeyboard: true,
        supportsColorButtons: false,
        supportsVolume: true,
        supportsPower: true,
        supportsChannel: true
    )
}
