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
        case .dlna: return 1900
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
        let scheme: String
        switch protocolType {
        case .smb:
            scheme = "smb"
        case .webdav, .emby, .jellyfin, .plex, .dlna, .directURL:
            scheme = useHTTPS ? "https" : "http"
        }
        let cleanedHost = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "smb://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let defaultStandardPort = useHTTPS ? 443 : 80
        let portPart = (port > 0 && port != defaultStandardPort && protocolType != .smb)
            || (protocolType == .smb && port > 0 && port != 445)
            ? ":\(port)" : ""
        let normalizedPath: String
        if basePath.isEmpty || basePath == "/" {
            normalizedPath = ""
        } else {
            let trimmed = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            normalizedPath = "/\(trimmed)"
        }
        return "\(scheme)://\(cleanedHost)\(portPart)\(normalizedPath)"
    }
}

@MainActor
final class MediaSourceStore: ObservableObject {
    static let shared = MediaSourceStore()

    @Published var sources: [MediaSourceConfig] = [] {
        didSet { save() }
    }

    private let storageKey = "AetherTV.MediaSources.v1"

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
        sources.removeAll { $0.id == id }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([MediaSourceConfig].self, from: data) else {
            return
        }
        sources = decoded
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(sources) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
