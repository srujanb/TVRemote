import Foundation
import Security

enum KeychainStore {
    private static let service = "com.sbarai.TVRemote"

    static func save(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw TVRemoteError.protocolFailure("Could not securely save pairing information (\(addStatus)).")
            }
        } else if status != errSecSuccess {
            throw TVRemoteError.protocolFailure("Could not update pairing information (\(status)).")
        }
    }

    static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum RecentDeviceStore {
    private static let key = "recentRemoteDevices"

    static func load() -> [RemoteDevice] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RemoteDevice].self, from: data)) ?? []
    }

    static func save(_ device: RemoteDevice) {
        var devices = load().filter { $0.id != device.id }
        devices.insert(device, at: 0)
        devices = Array(devices.prefix(8))
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func remove(_ device: RemoteDevice) {
        let devices = load().filter { $0.id != device.id }
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

enum ColorRelayStore {
    private static let key = "colorRelayDeviceMappings"

    static func relayDeviceID(for primaryDeviceID: String) -> String? {
        mappings()[primaryDeviceID]
    }

    static func save(primaryDeviceID: String, relayDeviceID: String) {
        var values = mappings()
        values[primaryDeviceID] = relayDeviceID
        UserDefaults.standard.set(values, forKey: key)
    }

    static func remove(primaryDeviceID: String) {
        var values = mappings()
        values.removeValue(forKey: primaryDeviceID)
        UserDefaults.standard.set(values, forKey: key)
    }

    static func removeReferences(to deviceID: String) {
        let values = mappings().filter { primaryID, relayID in
            primaryID != deviceID && relayID != deviceID
        }
        UserDefaults.standard.set(values, forKey: key)
    }

    private static func mappings() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
