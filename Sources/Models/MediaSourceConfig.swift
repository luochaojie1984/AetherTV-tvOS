import Foundation

enum MediaProtocolType: String, Codable, CaseIterable, Identifiable, Sendable {
    case smb = "SMB"
    case webdav = "WebDAV"
    case emby = "Emby"
    case jellyfin = "Jellyfin"
    case plex = "Plex"
    case dlna = "DLNA"
    case directURL = "HTTP 直链"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .smb: return "externaldrive.connected.to.line.below"
        case .webdav: return "network"
        case .emby: return "play.tv"
        case .jellyfin: return "sparkles.tv"
        case .plex: return "film.stack"
        case .dlna: return "dot.radiowaves.left.and.right"
        case .directURL: return "link"
        }
    }

    var defaultPort: Int {
        switch self {
        case .smb: return 445
        case .webdav: return 5005
        case .emby: return 8096
        case .jellyfin: return 8096
        case .plex: return 32400
        case .dlna: return 0
        case .directURL: return 80
        }
    }
}

struct MediaSourceConfig: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var protocolType: MediaProtocolType
    var host: String
    var port: Int
    var useHTTPS: Bool = false
    var basePath: String = "/"
    var username: String = ""
    var password: String = ""
    var apiToken: String = ""
    var userId: String = ""
    var shareName: String = ""
    /// 单连接限流模式（部分 Alist / 网盘 WebDAV 反代限制单连接时开启）
    var limitSingleConnection: Bool = false
    /// 保持长连接拉流（针对频繁 Range 断开会限速的网盘/NAS 反代）
    var holdSourceConnection: Bool = false
    /// 自定义 User-Agent（部分 WebDAV/媒体服反代校验 UA）
    var customUserAgent: String = "AetherTV/1.0"

    var baseURLString: String {
        if protocolType == .smb {
            let portPart = (port > 0 && port != 445) ? ":\(port)" : ""
            return "smb://\(cleanedHost)\(portPart)"
        }
        return hostWithScheme + normalizedPath
    }

    /// 只含协议、主机与非默认端口的地址（不含路径）。DLNA 的 Control URL 需要单独拼路径。
    var hostWithScheme: String {
        let scheme = useHTTPS ? "https" : "http"
        let defaultPort = useHTTPS ? 443 : 80
        let portPart = (port > 0 && port != defaultPort) ? ":\(port)" : ""
        return "\(scheme)://\(cleanedHost)\(portPart)"
    }

    /// DLNA 内容目录 Control 的路径；`basePath` 为空或 "/" 表示没有填写
    var dlnaControlPath: String? {
        let trimmed = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return trimmed.isEmpty ? nil : "/" + trimmed
    }

    /// 大小写不敏感剥离用户误填的协议头（兼容 tvOS 软键盘首字母自动大写如 `Http://` / `Smb://`）
    var cleanedHost: String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["https://", "http://", "smb://"]
        var stripped = true
        while stripped {
            stripped = false
            for prefix in prefixes {
                if let range = value.range(of: prefix, options: [.caseInsensitive, .anchored]) {
                    value.removeSubrange(range)
                    stripped = true
                }
            }
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }

    private var normalizedPath: String {
        let trimmed = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "" : "/" + trimmed
    }

    /// 生成剥离敏感凭据后的持久化副本（密码与 Token 只进 Keychain）
    func strippedForPersistence() -> MediaSourceConfig {
        var copy = self
        copy.password = ""
        copy.apiToken = ""
        return copy
    }
}

@MainActor
final class MediaSourceStore: ObservableObject {
    static let shared = MediaSourceStore()

    @Published var sources: [MediaSourceConfig] = [] {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }

    private let storageKey = "AetherTV.MediaSources.v1"
    private var isLoading = false

    private init() {
        load()
    }

    func add(_ source: MediaSourceConfig) {
        sources.append(source)
    }

    func update(_ source: MediaSourceConfig) {
        if let idx = sources.firstIndex(where: { $0.id == source.id }) {
            sources[idx] = source
        }
    }

    func remove(id: UUID) {
        KeychainCredentialStore.shared.delete(for: id)
        sources.removeAll { $0.id == id }
    }

    /// 重新从持久化存储与 Keychain 加载（用于测试与迁移验证）
    func reloadFromStorage() {
        load()
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }

        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([MediaSourceConfig].self, from: data) else {
            return
        }

        var needsMigrationRewrite = false
        var hydrated: [MediaSourceConfig] = []
        hydrated.reserveCapacity(decoded.count)

        for var item in decoded {
            if !item.password.isEmpty || !item.apiToken.isEmpty {
                // 向后兼容迁移：将旧版本明文落盘的敏感字段迁入 Keychain 并清理 UserDefaults
                KeychainCredentialStore.shared.save(
                    SourceCredentials(password: item.password, apiToken: item.apiToken),
                    for: item.id
                )
                needsMigrationRewrite = true
            } else if let creds = KeychainCredentialStore.shared.load(for: item.id) {
                item.password = creds.password
                item.apiToken = creds.apiToken
            }
            hydrated.append(item)
        }

        sources = hydrated
        if needsMigrationRewrite {
            persistMetadataOnly(hydrated)
        }
    }

    private func save() {
        for source in sources {
            KeychainCredentialStore.shared.save(
                SourceCredentials(password: source.password, apiToken: source.apiToken),
                for: source.id
            )
        }
        persistMetadataOnly(sources)
    }

    private func persistMetadataOnly(_ list: [MediaSourceConfig]) {
        let sanitized = list.map { $0.strippedForPersistence() }
        if let encoded = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
