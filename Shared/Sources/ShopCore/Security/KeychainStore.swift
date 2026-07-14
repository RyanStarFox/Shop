import Foundation
import Security

public enum KeychainError: Error, Equatable, Sendable {
    case unexpectedStatus(OSStatus)
    case invalidPasswordData
}

public struct KeychainStore: Sendable {
    public static let service = "com.shop.webdav"

    public init() {}

    public func setPassword(_ password: String, username: String, serverURL: String) throws {
        let query = itemQuery(username: username, serverURL: serverURL)
        let valueData = Data(password.utf8)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: valueData] as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var newItem = query
            newItem[kSecValueData as String] = valueData
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    public func password(username: String, serverURL: String) throws -> String? {
        var query = itemQuery(username: username, serverURL: serverURL)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let password = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidPasswordData
            }
            return password
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func deletePassword(username: String, serverURL: String) throws {
        let status = SecItemDelete(itemQuery(username: username, serverURL: serverURL) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public static func account(username: String, serverURL: String) -> String {
        "\(username)@\(serverURL)"
    }

    private func itemQuery(username: String, serverURL: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account(username: username, serverURL: serverURL)
        ]
    }
}
