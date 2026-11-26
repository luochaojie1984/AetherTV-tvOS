import Foundation
import AetherEngine

/// 局域网 SMB / WebDAV / 媒体服常见网络坑位防护工具集
enum NetworkPitfallGuards {
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

    /// 构造带避坑默认项的请求头（UA、Basic Auth、Keep-Alive）
    static func standardHTTPHeaders(for source: MediaSourceConfig) -> [String: String] {
        var headers: [String: String] = [
            "User-Agent": source.customUserAgent.isEmpty ? "AetherTV/1.0" : source.customUserAgent,
            "Accept": "*/*"
        ]
        if let auth = basicAuthHeader(username: source.username, password: source.password) {
            headers["Authorization"] = auth
        }
        if !source.apiToken.isEmpty {
            switch source.protocolType {
            case .emby, .jellyfin:
                headers["X-Emby-Token"] = source.apiToken
            case .plex:
                headers["X-Plex-Token"] = source.apiToken
            default:
                break
            }
        }
        return headers
    }

    /// 安全解析 64 位大文件长度（避免 >4GB 4K Remux 溢出）
    static func parseContentLength(_ raw: String?) -> Int64? {
        guard let raw else { return nil }
        return Int64(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 创建支持局域网自签名证书且在同源重定向时保留 Authorization 的 URLSession
    static func makeResilientSession(
        allowSelfSignedLAN: Bool = true,
        timeoutInterval: TimeInterval = 20
    ) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutInterval
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

    /// 解决 iOS/tvOS URLSession 在 301/302/307/308 重定向时默认丢弃 Authorization Header 的经典坑
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var mutable = request
        if let original = task.originalRequest,
           let origHost = original.url?.host?.lowercased(),
           let newHost = request.url?.host?.lowercased(),
           origHost == newHost {
            if let auth = original.value(forHTTPHeaderField: "Authorization"),
               mutable.value(forHTTPHeaderField: "Authorization") == nil {
                mutable.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            if let embyToken = original.value(forHTTPHeaderField: "X-Emby-Token"),
               mutable.value(forHTTPHeaderField: "X-Emby-Token") == nil {
                mutable.setValue(embyToken, forHTTPHeaderField: "X-Emby-Token")
            }
            if let plexToken = original.value(forHTTPHeaderField: "X-Plex-Token"),
               mutable.value(forHTTPHeaderField: "X-Plex-Token") == nil {
                mutable.setValue(plexToken, forHTTPHeaderField: "X-Plex-Token")
            }
        }
        completionHandler(mutable)
    }
}
