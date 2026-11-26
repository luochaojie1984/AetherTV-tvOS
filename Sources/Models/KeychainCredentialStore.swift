import Foundation
import Security

struct SourceCredentials: Codable, Equatable, Sendable {
    var password: String
    var apiToken: String
}

/// 基于 Apple Keychain（Security.framework）的敏感凭据存储。
/// - 不指定 `kSecAttrAccessGroup`，兼容路由器等无特定 Team Entitlement 的自签部署环境。
/// - 若在无签名模拟器构建（`CODE_SIGNING_ALLOWED=NO`）下遇到 `errSecMissingEntitlement`（-34018），
///   仅回退至当前进程内内存缓存，绝不降级写入 `UserDefaults`。
final class KeychainCredentialStore: @unchecked Sendable {
    static let shared = KeychainCredentialStore()

    private let service = "com.aethertv.player.credentials"
    private let lock = NSLock()
    private var memoryFallback: [String: SourceCredentials] = [:]

    private(set) var lastStatus: OSStatus = errSecSuccess

    var isUsingMemoryFallback: Bool {
        lock.lock()
        defer { lock.unlock() }
        return lastStatus == errSecMissingEntitlement
    }

    private init() {}

    func save(_ credentials: SourceCredentials, for sourceId: UUID) {
        if credentials.password.isEmpty && credentials.apiToken.isEmpty {
            delete(for: sourceId)
            return
        }
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        let account = sourceId.uuidString

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        lock.lock()
        defer { lock.unlock() }

        let deleteStatus = SecItemDelete(baseQuery as CFDictionary)
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        lastStatus = addStatus

        if addStatus == errSecSuccess {
            memoryFallback.removeValue(forKey: account)
        } else if addStatus == errSecMissingEntitlement || deleteStatus == errSecMissingEntitlement {
            memoryFallback[account] = credentials
        }
    }

    func load(for sourceId: UUID) -> SourceCredentials? {
        let account = sourceId.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        lock.lock()
        defer { lock.unlock() }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        lastStatus = status

        if status == errSecSuccess,
           let data = result as? Data,
           let decoded = try? JSONDecoder().decode(SourceCredentials.self, from: data) {
            return decoded
        }

        if status == errSecMissingEntitlement {
            return memoryFallback[account]
        }
        return nil
    }

    func delete(for sourceId: UUID) {
        let account = sourceId.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        lock.lock()
        defer { lock.unlock() }

        let status = SecItemDelete(query as CFDictionary)
        lastStatus = status
        memoryFallback.removeValue(forKey: account)
    }
}
