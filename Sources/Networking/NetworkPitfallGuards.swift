import Foundation
import AetherEngine

/// 局域网 SMB / WebDAV / 媒体服常见网络坑位防护工具集
enum NetworkPitfallGuards {
    private static let selfSignedLANSession: URLSession = buildResilientSession(allowSelfSignedLAN: true)
    private static let strictTLSSession: URLSession = buildResilientSession(allowSelfSignedLAN: false)

    private static let deviceIdStorageKey = "AetherTV.DeviceId.v1"

    /// 敏感鉴权请求头（小写键名，用于落盘脱敏）
    static let sensitiveHeaderKeys: Set<String> = [
        "authorization",
        "x-emby-token",
        "x-emby-authorization",
        "x-plex-token",
        "cookie"
    ]

    /// 统一配置 AetherEngine 的自签名证书信任策略
    static func configureEngineTLS(allowSelfSignedLAN: Bool) {
        if allowSelfSignedLAN {
            EngineTLS.serverTrustEvaluator = { protectionSpace in
                isPrivateLANHost(protectionSpace.host)
            }
        } else {
            EngineTLS.serverTrustEvaluator = nil
        }
    }

    /// 判断是否属于局域网私有地址或本地主机名（防止误放开公网 HTTPS 校验）
    static func isPrivateLANHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" || lower.hasSuffix(".local") || lower.hasSuffix(".lan") || lower.hasSuffix(".home") {
            return true
        }
        if lower.hasPrefix("192.168.") || lower.hasPrefix("10.") || lower.hasPrefix("127.") {
            return true
        }
        if lower.hasPrefix("172.") {
            let parts = lower.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        if lower.hasPrefix("fc") || lower.hasPrefix("fd") || lower.hasPrefix("fe80:") || lower == "::1" {
            return true
        }
        return false
    }

    /// 避免中文、空格、`#`、`?`、`[`、`]`、`+` 以及 macOS NFD/NFC 不一致导致的 404 或二次编码（%25）
    static func safeEncodedURL(base: String, relativePath: String) -> URL? {
        let normalizedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // 先尝试反解码一次（避免已编码路径被二次编码），再统一做 NFC 规范化
        let decoded = relativePath.removingPercentEncoding ?? relativePath
        let nfc = decoded.precomposedStringWithCanonicalMapping

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#[]@!$&'()*+,;=")

        let segments = nfc
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { seg -> String in
                String(seg).addingPercentEncoding(withAllowedCharacters: allowed) ?? String(seg)
            }

        let joinedPath = segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
        return URL(string: normalizedBase + joinedPath)
    }

    /// 构造标准 HTTP Basic 鉴权头（兼容含中文或特殊字符的密码）
    static func basicAuthHeader(username: String, password: String) -> String? {
        guard !username.isEmpty || !password.isEmpty else { return nil }
        let raw = "\(username):\(password)"
        guard let data = raw.data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }

    /// 稳定的设备标识（用于 Emby / Jellyfin / Plex 客户端认证头）
    static var clientDeviceId: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIdStorageKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: deviceIdStorageKey)
        return generated
    }

    /// 构造 Emby / Jellyfin 规范的 MediaBrowser 授权头
    static func embyAuthorizationHeader(token: String? = nil) -> String {
        var header = "MediaBrowser Client=\"AetherTV\", Device=\"Apple TV\", DeviceId=\"\(clientDeviceId)\", Version=\"1.0.0\""
        if let token, !token.isEmpty {
            header += ", Token=\"\(token)\""
        }
        return header
    }

    /// 构造带避坑默认项的请求头（UA、Basic Auth、Emby/Jellyfin/Plex Token）
    static func standardHTTPHeaders(for source: MediaSourceConfig) -> [String: String] {
        var headers: [String: String] = [
            "User-Agent": source.customUserAgent.isEmpty ? "AetherTV/1.0" : source.customUserAgent,
            "Accept": "*/*"
        ]
        if let auth = basicAuthHeader(username: source.username, password: source.password) {
            headers["Authorization"] = auth
        }
        switch source.protocolType {
        case .emby, .jellyfin:
            headers["X-Emby-Authorization"] = embyAuthorizationHeader(token: source.apiToken.isEmpty ? nil : source.apiToken)
            if !source.apiToken.isEmpty {
                headers["X-Emby-Token"] = source.apiToken
            }
        case .plex:
            headers["X-Plex-Client-Identifier"] = clientDeviceId
            headers["X-Plex-Product"] = "AetherTV"
            headers["X-Plex-Device"] = "Apple TV"
            headers["X-Plex-Platform"] = "tvOS"
            if !source.apiToken.isEmpty {
                headers["X-Plex-Token"] = source.apiToken
            }
        default:
            break
        }
        return headers
    }

    /// 剥离请求头中的敏感鉴权字段（供 WatchHistoryStore 持久化前调用）
    static func stripSensitiveHeaders(_ headers: [String: String]) -> [String: String] {
        headers.filter { !sensitiveHeaderKeys.contains($0.key.lowercased()) }
    }

    /// 剥离 URL 查询参数中的 `api_key` 与 `X-Plex-Token`
    static func stripSensitiveQueryItems(from url: URL?) -> URL? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        guard let items = components.queryItems, !items.isEmpty else {
            return url
        }
        let filtered = items.filter { item in
            let lower = item.name.lowercased()
            return lower != "api_key" && lower != "x-plex-token"
        }
        components.queryItems = filtered.isEmpty ? nil : filtered
        return components.url ?? url
    }

    /// 同目录外挂字幕匹配：匹配与视频主文件名一致，或主文件名后紧跟分隔符的字幕（防止 `Ep1.mkv` 误匹配 `Ep10.srt`）
    static func subtitleMatchesVideo(subtitleFilename: String, videoFilename: String) -> Bool {
        let videoStem = (videoFilename as NSString).deletingPathExtension
            .precomposedStringWithCanonicalMapping
            .lowercased()
        let subBase = (subtitleFilename as NSString).deletingPathExtension
            .precomposedStringWithCanonicalMapping
            .lowercased()
        guard !videoStem.isEmpty, subBase.hasPrefix(videoStem) else { return false }
        if subBase == videoStem { return true }
        let nextIndex = subBase.index(subBase.startIndex, offsetBy: videoStem.count)
        let boundaryChars: Set<Character> = [".", "_", "-", " ", "[", "(", "]", ")"]
        return boundaryChars.contains(subBase[nextIndex])
    }

    /// 从外挂字幕文件名推断 BCP-47 语言代码
    static func inferSubtitleLanguageCode(from filename: String) -> String? {
        let lower = filename.lowercased()
        if lower.contains("chs") || lower.contains(".sc.") || lower.contains("_sc") || lower.contains("zh-cn") || lower.contains("简") {
            return "zh-Hans"
        }
        if lower.contains("cht") || lower.contains(".tc.") || lower.contains("_tc") || lower.contains("zh-tw") || lower.contains("繁") {
            return "zh-Hant"
        }
        if lower.contains(".zh.") || lower.contains(".chi.") { return "zh" }
        if lower.contains(".en.") || lower.contains(".eng.") { return "en" }
        if lower.contains(".ja.") || lower.contains(".jpn.") { return "ja" }
        return nil
    }

    /// 安全解析 64 位大文件长度（避免 >4GB 4K Remux 溢出）
    static func parseContentLength(_ raw: String?) -> Int64? {
        guard let raw else { return nil }
        return Int64(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 获取全局复用的共享 URLSession（复用连接池与 HTTP Keep-Alive，避免每次请求泄漏 Session）
    static func sharedSession(allowSelfSignedLAN: Bool = true) -> URLSession {
        allowSelfSignedLAN ? selfSignedLANSession : strictTLSSession
    }

    /// 兼容旧调用点：直接返回全局复用共享 Session
    static func makeResilientSession(
        allowSelfSignedLAN: Bool = true,
        timeoutInterval: TimeInterval = 20
    ) -> URLSession {
        _ = timeoutInterval
        return sharedSession(allowSelfSignedLAN: allowSelfSignedLAN)
    }

    private static func buildResilientSession(allowSelfSignedLAN: Bool) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let delegate = ResilientNetworkDelegate(allowSelfSignedLAN: allowSelfSignedLAN)
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
}

private final class ResilientNetworkDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let allowSelfSignedLAN: Bool

    init(allowSelfSignedLAN: Bool) {
        self.allowSelfSignedLAN = allowSelfSignedLAN
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust,
           allowSelfSignedLAN,
           NetworkPitfallGuards.isPrivateLANHost(challenge.protectionSpace.host) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    /// 解决 iOS/tvOS URLSession 在 301/302/307/308 同源重定向时默认丢弃鉴权头的经典坑
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var mutable = request
        if let original = task.originalRequest,
           let origURL = original.url,
           let newURL = request.url,
           let origHost = origURL.host?.lowercased(),
           let newHost = newURL.host?.lowercased(),
           origHost == newHost,
           effectivePort(for: origURL) == effectivePort(for: newURL),
           let origScheme = origURL.scheme?.lowercased(),
           let newScheme = newURL.scheme?.lowercased(),
           (origScheme == newScheme || newScheme == "https") {
            for headerName in ["Authorization", "X-Emby-Token", "X-Emby-Authorization", "X-Plex-Token"] {
                if let val = original.value(forHTTPHeaderField: headerName),
                   mutable.value(forHTTPHeaderField: headerName) == nil {
                    mutable.setValue(val, forHTTPHeaderField: headerName)
                }
            }
        }
        completionHandler(mutable)
    }

    private func effectivePort(for url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}
