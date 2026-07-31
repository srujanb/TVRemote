import Darwin
import Foundation

@MainActor
final class RokuAdapter: TVRemoteAdapter {
    let platform = TVPlatform.roku
    private(set) var capabilities = RemoteCapabilities.roku
    var onTextInputRequested: ((RemoteTextInputContext) -> Void)?
    var onTextInputEnded: (() -> Void)?
    var onConnectionEvent: ((RemoteAdapterConnectionEvent) -> Void)?

    private let session: URLSession
    private var baseURL: URL?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func discover(timeout: TimeInterval) async throws -> [RemoteDevice] {
        let locations = await Task.detached(priority: .userInitiated) {
            RokuSSDPDiscovery.discover(timeout: timeout)
        }.value

        var devices: [RemoteDevice] = []
        for location in locations {
            guard let url = URL(string: location),
                  let host = url.host else { continue }
            let infoURL = url.appendingPathComponent("query/device-info")
            let name = (try? await deviceName(at: infoURL)) ?? "Roku \(host)"
            devices.append(
                RemoteDevice(
                    name: name,
                    host: host,
                    port: url.port.map(UInt16.init) ?? 8060,
                    platform: .roku
                )
            )
        }
        return devices
    }

    func connect(to device: RemoteDevice) async throws -> ConnectionOutcome {
        guard let url = Self.baseURL(host: device.host, port: device.port ?? 8060) else {
            throw TVRemoteError.invalidAddress
        }
        let requestURL = url.appendingPathComponent("query/device-info")
        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 4
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TVRemoteError.connectionFailed(
                "Could not reach the Roku. Confirm both devices use the same Wi-Fi and “Control by mobile apps” is enabled."
            )
        }
        capabilities = Self.capabilities(
            fromDeviceInfoXML: String(decoding: data, as: UTF8.self)
        )
        baseURL = url
        return .connected
    }

    func submitPIN(_ pin: String) async throws {
        throw TVRemoteError.unsupported("Roku does not require a pairing code.")
    }

    func disconnect() async {
        baseURL = nil
        capabilities = .roku
    }

    func send(_ command: RemoteCommand) async throws {
        guard let key = Self.keyName(for: command) else {
            throw TVRemoteError.unsupported(
                "\(command.rawValue) is not supported by Roku over Wi-Fi."
            )
        }
        try await post(pathComponent: "keypress/\(key)")
    }

    func sendText(_ text: String) async throws {
        guard !text.isEmpty else { return }
        for character in text {
            guard let encoded = String(character).addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
            ) else { continue }
            try await post(pathComponent: "keypress/Lit_\(encoded)")
        }
    }

    func updateText(from previousText: String, to newText: String) async throws {
        guard previousText != newText else { return }

        if newText.hasPrefix(previousText) {
            try await sendText(String(newText.dropFirst(previousText.count)))
        } else if previousText.hasPrefix(newText) {
            for _ in 0..<previousText.dropFirst(newText.count).count {
                try await post(pathComponent: "keypress/Backspace")
            }
        } else {
            for _ in previousText {
                try await post(pathComponent: "keypress/Backspace")
            }
            try await sendText(newText)
        }
    }

    private func post(pathComponent: String) async throws {
        guard let baseURL else { throw TVRemoteError.notConnected }
        guard let url = URL(string: pathComponent, relativeTo: baseURL)?.absoluteURL else {
            throw TVRemoteError.protocolFailure("Could not create the Roku command URL.")
        }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 3
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw TVRemoteError.connectionFailed("The Roku rejected the command.")
            }
        } catch {
            onConnectionEvent?(.lost(error.localizedDescription))
            throw error
        }
    }

    private func deviceName(at url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        let (data, _) = try await session.data(for: request)
        let xml = String(decoding: data, as: UTF8.self)
        return RokuDeviceInfoParser.value(for: "user-device-name", in: xml)
            ?? RokuDeviceInfoParser.value(for: "friendly-device-name", in: xml)
            ?? RokuDeviceInfoParser.value(for: "model-name", in: xml)
            ?? "Roku"
    }

    static func baseURL(host: String, port: UInt16) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let bracketed = trimmed.contains(":") && !trimmed.hasPrefix("[") ? "[\(trimmed)]" : trimmed
        return URL(string: "http://\(bracketed):\(port)/")
    }

    static func capabilities(fromDeviceInfoXML xml: String) -> RemoteCapabilities {
        let isTV = RokuDeviceInfoParser.value(for: "is-tv", in: xml) == "true"
        let supportsPower = isTV
            || RokuDeviceInfoParser.value(for: "supports-tv-power-control", in: xml) == "true"
        let supportsVolume = isTV
            || RokuDeviceInfoParser.value(for: "supports-audio-volume-control", in: xml) == "true"
        let supportsTuner = RokuDeviceInfoParser.value(for: "supports-tv-tuner", in: xml) == "true"

        return RemoteCapabilities(
            supportsKeyboard: true,
            supportsColorButtons: false,
            supportsVolume: supportsVolume,
            supportsPower: supportsPower,
            supportsChannel: supportsTuner,
            supportsNumberPad: true,
            extraCommands: [.menu, .search]
        )
    }

    static func keyName(for command: RemoteCommand) -> String? {
        switch command {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .select: "Select"
        case .back: "Back"
        case .home: "Home"
        case .playPause: "Play"
        case .rewind: "Rev"
        case .fastForward: "Fwd"
        case .volumeUp: "VolumeUp"
        case .volumeDown: "VolumeDown"
        case .mute: "VolumeMute"
        case .power: "PowerOff"
        case .channelUp: "ChannelUp"
        case .channelDown: "ChannelDown"
        case .red, .green, .yellow, .blue: nil
        case .digit0: "Lit_0"
        case .digit1: "Lit_1"
        case .digit2: "Lit_2"
        case .digit3: "Lit_3"
        case .digit4: "Lit_4"
        case .digit5: "Lit_5"
        case .digit6: "Lit_6"
        case .digit7: "Lit_7"
        case .digit8: "Lit_8"
        case .digit9: "Lit_9"
        case .delete: "Backspace"
        case .menu: "Info"
        case .search: "Search"
        case .input, .info, .guide, .captions: nil
        }
    }
}

enum RokuDeviceInfoParser {
    static func value(for tag: String, in xml: String) -> String? {
        guard let startRange = xml.range(of: "<\(tag)>", options: .caseInsensitive),
              let endRange = xml.range(
                of: "</\(tag)>",
                options: .caseInsensitive,
                range: startRange.upperBound..<xml.endIndex
              ) else { return nil }
        return String(xml[startRange.upperBound..<endRange.lowerBound])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum RokuSSDPDiscovery {
    static func discover(timeout: TimeInterval) -> [String] {
        let socketFD = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else { return [] }
        defer { Darwin.close(socketFD) }

        var receiveTimeout = timeval(
            tv_sec: Int(timeout),
            tv_usec: Int32((timeout.truncatingRemainder(dividingBy: 1)) * 1_000_000)
        )
        setsockopt(
            socketFD,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &receiveTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &address.sin_addr)

        let request = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: "ssdp:discover"\r
        MX: 2\r
        ST: roku:ecp\r
        \r
        """
        let bytes = Array(request.utf8)
        let sent = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bytes.withUnsafeBytes {
                    Darwin.sendto(
                        socketFD,
                        $0.baseAddress,
                        $0.count,
                        0,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
        guard sent >= 0 else { return [] }

        let deadline = Date().addingTimeInterval(timeout)
        var locations = Set<String>()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while Date() < deadline {
            let count = Darwin.recv(socketFD, &buffer, buffer.count, 0)
            guard count > 0 else { break }
            let response = String(decoding: buffer.prefix(Int(count)), as: UTF8.self)
            for line in response.components(separatedBy: .newlines) {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "location" {
                    locations.insert(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        return locations.sorted()
    }
}
