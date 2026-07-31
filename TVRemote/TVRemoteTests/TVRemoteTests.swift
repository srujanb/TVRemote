import XCTest
@testable import TVRemote

final class TVRemoteTests: XCTestCase {
    func testRokuCommandMapping() {
        XCTAssertEqual(RokuAdapter.keyName(for: .home), "Home")
        XCTAssertEqual(RokuAdapter.keyName(for: .playPause), "Play")
        XCTAssertEqual(RokuAdapter.keyName(for: .volumeUp), "VolumeUp")
        XCTAssertNil(RokuAdapter.keyName(for: .red))
        XCTAssertNil(RokuAdapter.keyName(for: .blue))
    }

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
    }

    func testColorRelayMappingPersistence() {
        let primaryID = "test-primary-\(UUID().uuidString)"
        let relayID = "test-relay-\(UUID().uuidString)"
        ColorRelayStore.save(primaryDeviceID: primaryID, relayDeviceID: relayID)
        XCTAssertEqual(ColorRelayStore.relayDeviceID(for: primaryID), relayID)

        ColorRelayStore.removeReferences(to: relayID)
        XCTAssertNil(ColorRelayStore.relayDeviceID(for: primaryID))
    }
}
