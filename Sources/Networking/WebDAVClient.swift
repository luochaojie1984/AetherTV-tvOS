import Foundation

enum WebDAVError: LocalizedError {
    case invalidURL
    case httpError(Int, String)
    case unauthorized
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "WebDAV 地址格式无效，请检查主机名、端口与路径。"
        case .unauthorized:
            return "WebDAV 鉴权失败（401），请检查用户名或密码。"
        case .httpError(let code, let detail):
            return "WebDAV 请求失败（HTTP \(code)）：\(detail)"
        case .parseFailed:
            return "无法解析 WebDAV 服务器返回的目录列表。"
        }
    }
}

/// 兼容群晖 / 威联通 / 飞牛 / 极空间 / OpenList / AList / Nextcloud 的 WebDAV 客户端
final class WebDAVClient: Sendable {
    private let allowSelfSignedLAN: Bool

    init(allowSelfSignedLAN: Bool = true) {
        self.allowSelfSignedLAN = allowSelfSignedLAN
    }

    func listDirectory(source: MediaSourceConfig, path: String) async throws -> [MediaItem] {
        let dirPath = path.hasSuffix("/") ? path : path + "/"
        guard let url = NetworkPitfallGuards.safeEncodedURL(base: source.baseURLString, relativePath: dirPath) else {
            throw WebDAVError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        for (k, v) in NetworkPitfallGuards.standardHTTPHeaders(for: source) {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.httpBody = """
        <?xml version="1.0" encoding="utf-8" ?>
        <D:propfind xmlns:D="DAV:">
          <D:prop>
            <D:displayname/>
            <D:resourcetype/>
            <D:getcontentlength/>
            <D:getcontenttype/>
          </D:prop>
        </D:propfind>
        """.data(using: .utf8)

        let session = NetworkPitfallGuards.makeResilientSession(allowSelfSignedLAN: allowSelfSignedLAN)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.parseFailed
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw WebDAVError.unauthorized
        }
        guard (200...299).contains(http.statusCode) || http.statusCode == 207 else {
            throw WebDAVError.httpError(http.statusCode, HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }

        let rawEntries = WebDAVXMLParser.parse(data: data)
        let requestedPathNormalized = normalizeComparePath(url.path)

        // 先分离目录、视频与同目录外挂字幕
        var directories: [WebDAVEntry] = []
        var videos: [WebDAVEntry] = []
        var subtitles: [WebDAVEntry] = []

        for entry in rawEntries {
            let entryPath = extractPath(from: entry.href)
            if normalizeComparePath(entryPath) == requestedPathNormalized {
                continue
            }
            if entry.isCollection {
                directories.append(entry)
            } else {
                let filename = resolvedFilename(entry: entry, path: entryPath)
                if MediaItem.isVideoFile(filename) {
                    videos.append(entry)
                } else if MediaItem.isSubtitleFile(filename) {
                    subtitles.append(entry)
                }
            }
        }

        let headers = NetworkPitfallGuards.standardHTTPHeaders(for: source)
        let origin = originString(from: url)

        var items: [MediaItem] = []

        for dir in directories.sorted(by: { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }) {
            let entryPath = extractPath(from: dir.href)
            let name = resolvedFilename(entry: dir, path: entryPath)
            let relative = stripBasePath(entryPath, basePath: source.basePath)
            items.append(MediaItem(
                id: "webdav:\(source.id.uuidString):\(entryPath)",
                title: name,
                subtitle: "文件夹",
                isDirectory: true,
                streamURL: nil,
                protocolType: .webdav,
                remotePath: relative,
                httpHeaders: headers
            ))
        }

        for vid in videos.sorted(by: { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }) {
            let entryPath = extractPath(from: vid.href)
            let filename = resolvedFilename(entry: vid, path: entryPath)
            let stem = (filename as NSString).deletingPathExtension.lowercased()
            let fileURL = resolveAbsoluteURL(origin: origin, href: vid.href)
            let relative = stripBasePath(entryPath, basePath: source.basePath)

            // 自动匹配同目录下前缀一致的外挂字幕（如 Movie.mkv -> Movie.zh.ass / Movie.chs.srt）
            let matchedSubs: [ExternalSubtitleReference] = subtitles.compactMap { sub in
                let subPath = extractPath(from: sub.href)
                let subName = resolvedFilename(entry: sub, path: subPath)
                let subLower = subName.lowercased()
                guard subLower.hasPrefix(stem),
                      let subURL = resolveAbsoluteURL(origin: origin, href: sub.href) else {
                    return nil
                }
                let ext = (subName as NSString).pathExtension.lowercased()
                return ExternalSubtitleReference(
                    title: subName,
                    language: inferLanguageCode(from: subName),
                    url: subURL,
                    formatHint: ext,
                    httpHeaders: headers
                )
            }

            items.append(MediaItem(
                id: "webdav:\(source.id.uuidString):\(entryPath)",
                title: filename,
                subtitle: matchedSubs.isEmpty ? nil : "含 \(matchedSubs.count) 条同目录外挂字幕",
                isDirectory: false,
                streamURL: fileURL,
                fileSize: vid.contentLength,
                sourceId: source.id,
                protocolType: .webdav,
                remotePath: relative,
                httpHeaders: headers,
                externalSubtitles: matchedSubs
            ))
        }

        return items
    }

    private func originString(from url: URL) -> String {
        let scheme = url.scheme ?? "http"
        let host = url.host ?? ""
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private func extractPath(from href: String) -> String {
        if let u = URL(string: href), u.scheme != nil {
            return u.path
        }
        return href.removingPercentEncoding ?? href
    }

    private func resolveAbsoluteURL(origin: String, href: String) -> URL? {
        if let u = URL(string: href), u.scheme != nil {
            return u
        }
        return NetworkPitfallGuards.safeEncodedURL(base: origin, relativePath: href)
    }

    private func resolvedFilename(entry: WebDAVEntry, path: String) -> String {
        let cleaned = entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            return cleaned.removingPercentEncoding ?? cleaned
        }
        let last = (path as NSString).lastPathComponent
        return last.removingPercentEncoding ?? last
    }

    private func normalizeComparePath(_ path: String) -> String {
        let decoded = (path.removingPercentEncoding ?? path).precomposedStringWithCanonicalMapping
        return decoded.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    private func stripBasePath(_ fullPath: String, basePath: String) -> String {
        let normBase = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var normFull = (fullPath.removingPercentEncoding ?? fullPath).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !normBase.isEmpty && normFull.hasPrefix(normBase) {
            normFull = String(normFull.dropFirst(normBase.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return "/" + normFull
    }

    private func inferLanguageCode(from filename: String) -> String? {
        let lower = filename.lowercased()
        if lower.contains("chs") || lower.contains("sc") || lower.contains("zh-cn") || lower.contains("简") {
            return "zh-Hans"
        }
        if lower.contains("cht") || lower.contains("tc") || lower.contains("zh-tw") || lower.contains("繁") {
            return "zh-Hant"
        }
        if lower.contains(".zh.") || lower.contains(".chi.") { return "zh" }
        if lower.contains(".en.") || lower.contains(".eng.") { return "en" }
        if lower.contains(".ja.") || lower.contains(".jpn.") { return "ja" }
        return nil
    }
}

private struct WebDAVEntry {
    var href: String = ""
    var displayName: String = ""
    var isCollection: Bool = false
    var contentLength: Int64?
}

private final class WebDAVXMLParser: NSObject, XMLParserDelegate {
    private var entries: [WebDAVEntry] = []
    private var currentEntry: WebDAVEntry?
    private var currentElement: String = ""
    private var buffer: String = ""

    static func parse(data: Data) -> [WebDAVEntry] {
        let delegate = WebDAVXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.parse()
        return delegate.entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let local = stripNamespace(elementName)
        currentElement = local
        buffer = ""
        if local == "response" {
            currentEntry = WebDAVEntry()
        } else if local == "collection" {
            currentEntry?.isCollection = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let local = stripNamespace(elementName)
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch local {
        case "href":
            if !value.isEmpty { currentEntry?.href = value }
        case "displayname":
            if !value.isEmpty { currentEntry?.displayName = value }
        case "getcontentlength":
            if let len = NetworkPitfallGuards.parseContentLength(value) {
                currentEntry?.contentLength = len
            }
        case "response":
            if let entry = currentEntry, !entry.href.isEmpty {
                entries.append(entry)
            }
            currentEntry = nil
        default:
            break
        }
        buffer = ""
    }

    private func stripNamespace(_ name: String) -> String {
        if let idx = name.lastIndex(of: ":") {
            return String(name[name.index(after: idx)...]).lowercased()
        }
        return name.lowercased()
    }
}
