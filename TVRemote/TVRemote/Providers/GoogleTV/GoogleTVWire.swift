import CryptoKit
import Foundation
import Security

enum GoogleTVProto {
    static func varint(_ value: Int) -> Data {
        var remaining = UInt64(value)
        var output = Data()
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            output.append(byte)
        } while remaining != 0
        return output
    }

    static func varintField(_ number: Int, _ value: Int) -> Data {
        varint(number << 3) + varint(value)
    }

    static func bytesField(_ number: Int, _ value: Data) -> Data {
        message(field: number, payload: value)
    }

    static func stringField(_ number: Int, _ value: String) -> Data {
        message(field: number, payload: Data(value.utf8))
    }

    static func message(field: Int, payload: Data) -> Data {
        varint((field << 3) | 2) + varint(payload.count) + payload
    }

    static func framed(_ payload: Data) -> Data {
        varint(payload.count) + payload
    }

    static func readVarint(_ data: Data, at start: Int) -> (value: Int, bytes: Int)? {
        var value = 0
        var shift = 0
        var index = start
        while index < data.count, shift < 64 {
            let byte = Int(data[index])
            index += 1
            value |= (byte & 0x7F) << shift
            if byte & 0x80 == 0 { return (value, index - start) }
            shift += 7
        }
        return nil
    }

    static func fields(_ data: Data) -> [Int: Data] {
        var result: [Int: Data] = [:]
        var index = 0
        while index < data.count, let tag = readVarint(data, at: index) {
            index += tag.bytes
            let number = tag.value >> 3
            let wireType = tag.value & 7
            switch wireType {
            case 0:
                guard let value = readVarint(data, at: index) else { return result }
                result[number] = data.subdata(in: index..<(index + value.bytes))
                index += value.bytes
            case 2:
                guard let length = readVarint(data, at: index) else { return result }
                index += length.bytes
                guard index + length.value <= data.count else { return result }
                result[number] = data.subdata(in: index..<(index + length.value))
                index += length.value
            default:
                return result
            }
        }
        return result
    }

    static func intField(_ data: Data, number: Int) -> Int? {
        guard let raw = fields(data)[number] else { return nil }
        return readVarint(raw, at: 0)?.value
    }
}

enum GoogleTVPairingMessage {
    private static func base() -> Data {
        GoogleTVProto.varintField(1, 2) + GoogleTVProto.varintField(2, 200)
    }

    static func request(clientName: String) -> Data {
        base() + GoogleTVProto.message(
            field: 10,
            payload: GoogleTVProto.stringField(1, "atvremote")
                + GoogleTVProto.stringField(2, clientName)
        )
    }

    static func options() -> Data {
        let encoding = GoogleTVProto.varintField(1, 3) + GoogleTVProto.varintField(2, 6)
        return base() + GoogleTVProto.message(
            field: 20,
            payload: GoogleTVProto.message(field: 1, payload: encoding)
                + GoogleTVProto.varintField(3, 1)
        )
    }

    static func configuration() -> Data {
        let encoding = GoogleTVProto.varintField(1, 3) + GoogleTVProto.varintField(2, 6)
        return base() + GoogleTVProto.message(
            field: 30,
            payload: GoogleTVProto.message(field: 1, payload: encoding)
                + GoogleTVProto.varintField(2, 1)
        )
    }

    static func secret(_ digest: Data) -> Data {
        base() + GoogleTVProto.message(
            field: 40,
            payload: GoogleTVProto.bytesField(1, digest)
        )
    }
}

enum GoogleTVPairingSecret {
    static func make(
        pin: String,
        identity: SecIdentity,
        serverCertificate: SecCertificate
    ) -> Data? {
        guard let clientCertificate = GoogleTVIdentityStore.certificate(from: identity),
              let clientKey = SecCertificateCopyKey(clientCertificate),
              let serverKey = SecCertificateCopyKey(serverCertificate),
              let clientRSA = RSAKeyNumbers.read(clientKey),
              let serverRSA = RSAKeyNumbers.read(serverKey),
              let pinBytes = Data(hexadecimal: String(pin.dropFirst(2))) else {
            return nil
        }

        var source = Data()
        source.append(clientRSA.modulus)
        source.append(clientRSA.exponent)
        source.append(serverRSA.modulus)
        source.append(serverRSA.exponent)
        source.append(pinBytes)
        let digest = Data(SHA256.hash(data: source))
        guard digest.first == UInt8(pin.prefix(2), radix: 16) else { return nil }
        return digest
    }
}

private enum RSAKeyNumbers {
    static func read(_ key: SecKey) -> (modulus: Data, exponent: Data)? {
        var error: Unmanaged<CFError>?
        guard let raw = SecKeyCopyExternalRepresentation(key, &error) as Data? else { return nil }
        var root = DERReader(data: raw)
        guard let sequence = root.element(tag: 0x30) else { return nil }
        var inner = DERReader(data: sequence)
        guard var modulus = inner.element(tag: 0x02),
              var exponent = inner.element(tag: 0x02) else { return nil }
        while modulus.first == 0 { modulus.removeFirst() }
        while exponent.count > 1 && exponent.first == 0 { exponent.removeFirst() }
        return (modulus, exponent)
    }

    private struct DERReader {
        let data: Data
        var offset = 0

        mutating func element(tag: UInt8) -> Data? {
            guard offset < data.count, data[offset] == tag else { return nil }
            offset += 1
            guard offset < data.count else { return nil }
            var length = Int(data[offset])
            offset += 1
            if length & 0x80 != 0 {
                let byteCount = length & 0x7F
                guard byteCount > 0, offset + byteCount <= data.count else { return nil }
                length = 0
                for _ in 0..<byteCount {
                    length = (length << 8) | Int(data[offset])
                    offset += 1
                }
            }
            guard length >= 0, offset + length <= data.count else { return nil }
            let value = data.subdata(in: offset..<(offset + length))
            offset += length
            return value
        }
    }
}

private extension Data {
    init?(hexadecimal: String) {
        guard hexadecimal.count.isMultiple(of: 2) else { return nil }
        self.init()
        reserveCapacity(hexadecimal.count / 2)
        var index = hexadecimal.startIndex
        while index < hexadecimal.endIndex {
            let next = hexadecimal.index(index, offsetBy: 2)
            guard let byte = UInt8(hexadecimal[index..<next], radix: 16) else { return nil }
            append(byte)
            index = next
        }
    }
}
