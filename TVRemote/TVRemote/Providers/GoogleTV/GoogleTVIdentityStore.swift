import Foundation
import Security

enum GoogleTVIdentityStore {
    private static let certificateLabel = "TV Remote Google TV Client Certificate"
    private static let keyTag = Data("com.sbarai.TVRemote.google-tv-client-key".utf8)

    static func loadIdentity() -> SecIdentity? {
        storedIdentity() ?? generateIdentity()
    }

    static func certificate(from identity: SecIdentity) -> SecCertificate? {
        var certificate: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificate)
        return certificate
    }

    private static func storedIdentity() -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: certificateLabel,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let result else { return nil }
        return (result as! SecIdentity)
    }

    private static func generateIdentity() -> SecIdentity? {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2_048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicDER = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?,
              let certificateDER = SelfSignedCertificate.make(publicKeyPKCS1: publicDER, privateKey: privateKey),
              let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
            return nil
        }

        let certificateItem: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: certificateLabel,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(certificateItem as CFDictionary, nil)
        return storedIdentity()
    }
}

private enum SelfSignedCertificate {
    static func make(publicKeyPKCS1: Data, privateKey: SecKey) -> Data? {
        let sha256WithRSA = sequence(oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]) + null())
        let rsaEncryption = sequence(oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]) + null())
        let commonName = sequence(set(sequence(oid([0x55, 0x04, 0x03]) + utf8("TV Remote"))))
        let issued = Date().addingTimeInterval(-86_400)
        let expiry = Calendar(identifier: .gregorian).date(byAdding: .year, value: 10, to: issued)!
        let validity = sequence(utcTime(issued) + utcTime(expiry))
        let publicKeyInfo = sequence(rsaEncryption + bitString(publicKeyPKCS1))

        var serial = Data(count: 16)
        _ = serial.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
        }
        serial[0] &= 0x7F
        if serial.allSatisfy({ $0 == 0 }) { serial[15] = 1 }

        let version = tagged(0xA0, integer(Data([2])))
        let certificateBody = sequence(
            version + integer(serial) + sha256WithRSA + commonName + validity + commonName + publicKeyInfo
        )
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            certificateBody as CFData,
            &error
        ) as Data? else { return nil }
        return sequence(certificateBody + sha256WithRSA + bitString(signature))
    }

    private static func tagged(_ tag: UInt8, _ value: Data) -> Data {
        Data([tag]) + length(value.count) + value
    }

    private static func sequence(_ value: Data) -> Data { tagged(0x30, value) }
    private static func set(_ value: Data) -> Data { tagged(0x31, value) }
    private static func oid(_ value: [UInt8]) -> Data { tagged(0x06, Data(value)) }
    private static func null() -> Data { Data([0x05, 0x00]) }
    private static func utf8(_ value: String) -> Data { tagged(0x0C, Data(value.utf8)) }
    private static func bitString(_ value: Data) -> Data { tagged(0x03, Data([0]) + value) }

    private static func integer(_ value: Data) -> Data {
        var bytes = value
        while bytes.count > 1 && bytes[0] == 0 && bytes[1] & 0x80 == 0 {
            bytes.removeFirst()
        }
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }
        return tagged(0x02, bytes)
    }

    private static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return tagged(0x17, Data(formatter.string(from: date).utf8))
    }

    private static func length(_ value: Int) -> Data {
        if value < 128 { return Data([UInt8(value)]) }
        var bytes: [UInt8] = []
        var remaining = value
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}
