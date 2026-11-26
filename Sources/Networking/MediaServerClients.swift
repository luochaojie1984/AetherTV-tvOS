import Foundation

enum MediaServerError: LocalizedError {
    case invalidURL
    case missingCredentials
    case missingControlURL
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "媒体服务器地址无效。"
        case .missingCredentials:
            return "请填写服务器 API Token（或用户名密码）。"
        case .missingControlURL:
            return "DLNA 需要填写内容目录的 Control 地址路径（社区常见值：MiniDLNA 为 /ctl/ContentDir，Windows 媒体共享为 /ContentDirectory/Control）。"
        case .serverError(let msg):
            return "媒体服务器返回错误：\(msg)"
        }
    }
}

/// 统一支持 Emby / Jellyfin / Plex 的局域网直连（Direct Play）客户端
final class MediaServerClients: Sendable {
    private let allowSelfSignedLAN: Bool

    init(allowSelfSignedLAN: Bool = true) {
        self.allowSelfSignedLAN = allowSelfSignedLAN
    }

    func browse(source: MediaSourceConfig, parentId: String? = nil) async throws -> [MediaItem] {
        switch source.protocolType {
        case .emby, .jellyfin:
            return try await browseEmbyOrJellyfin(source: source, parentId: parentId)
        case .plex:
            return try await browsePlex(source: source, keyPath: parentId)
        default:
            return []
        }
    }

    // MARK: - Emby / Jellyfin

    /// Emby / Jellyfin 的库列表要用户 ID：优先用配置里的，否则用 API Key 列出用户取第一个。
    /// 没有用户 ID 时 `/Items?Recursive=false` 在真实 Emby 上通常返回空列表。
    private func resolvedEmbyUserId(
        source: MediaSourceConfig,
        session: URLSession,
        headers: [String: String]
    ) async -> String? {
        if !source.userId.isEmpty { return source.userId }
        guard let url = URL(string: "\(source.baseURLString)/Users") else { return nil }
        var request = URLRequest(url: url)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let users = try? JSONDecoder().decode([EmbyUserDTO].self, from: data) else { return nil }
        return users.first(where: { $0.Policy?.IsAdministrator == true })?.Id ?? users.first?.Id
    }

    private func browseEmbyOrJellyfin(source: MediaSourceConfig, parentId: String?) async throws -> [MediaItem] {
        guard !source.apiToken.isEmpty else { throw MediaServerError.missingCredentials }
        let session = NetworkPitfallGuards.makeResilientSession(allowSelfSignedLAN: allowSelfSignedLAN)
        let headers = NetworkPitfallGuards.standardHTTPHeaders(for: source)

        let endpoint: String
        let userId = await resolvedEmbyUserId(source: source, session: session, headers: headers)
        if let parentId, !parentId.isEmpty {
            let itemsBase = userId.map { "\(source.baseURLString)/Users/\($0)/Items" } ?? "\(source.baseURLString)/Items"
            endpoint = "\(itemsBase)?ParentId=\(parentId)&Fields=MediaSources,Overview,RunTimeTicks&SortBy=SortName&SortOrder=Ascending"
        } else if let userId {
            endpoint = "\(source.baseURLString)/Users/\(userId)/Views"
        } else {
            endpoint = "\(source.baseURLString)/Items?Recursive=false&Fields=MediaSources,Overview,RunTimeTicks"
        }

        guard let url = URL(string: endpoint) else { throw MediaServerError.invalidURL }
        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MediaServerError.serverError("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        let decoded = try JSONDecoder().decode(EmbyItemsResponse.self, from: data)
        return decoded.Items.map { item in
            let isDir = item.IsFolder ?? (item.Type == "CollectionFolder" || item.Type == "Folder" || item.Type == "Series" || item.Type == "Season")
            let durationSec = item.RunTimeTicks.map { Double($0) / 10_000_000.0 }
            let streamURL: URL? = isDir ? nil : URL(
                string: "\(source.baseURLString)/Videos/\(item.Id)/stream?Static=true&api_key=\(source.apiToken)"
            )
            let posterURL = URL(
                string: "\(source.baseURLString)/Items/\(item.Id)/Images/Primary?maxWidth=480&api_key=\(source.apiToken)"
            )

            // 提取服务器声明的外挂字幕直链
            let extSubs: [ExternalSubtitleReference] = (item.MediaSources?.first?.MediaStreams ?? [])
                .filter { $0.Type == "Subtitle" && ($0.IsExternal ?? false) }
                .compactMap { stream in
                    guard let idx = stream.Index,
                          let mediaSourceId = item.MediaSources?.first?.Id else { return nil }
                    let codec = (stream.Codec ?? "srt").lowercased()
                    let subURLStr = "\(source.baseURLString)/Videos/\(item.Id)/\(mediaSourceId)/Subtitles/\(idx)/Stream.\(codec)?api_key=\(source.apiToken)"
                    guard let subURL = URL(string: subURLStr) else { return nil }
                    return ExternalSubtitleReference(
                        title: stream.DisplayTitle ?? stream.Language ?? "外挂字幕 #\(idx)",
                        language: stream.Language,
                        url: subURL,
                        formatHint: codec,
                        httpHeaders: headers
                    )
                }

            return MediaItem(
                id: "\(source.protocolType.rawValue.lowercased()):\(source.id.uuidString):\(item.Id)",
                title: item.Name,
                subtitle: item.SeriesName ?? item.Type,
                isDirectory: isDir,
                streamURL: streamURL,
                posterURL: posterURL,
                durationSeconds: durationSec,
                sourceId: source.id,
                protocolType: source.protocolType,
                remotePath: item.Id,
                httpHeaders: headers,
                externalSubtitles: extSubs,
                serverItemId: item.Id
            )
        }
    }

    // MARK: - Plex

    private func browsePlex(source: MediaSourceConfig, keyPath: String?) async throws -> [MediaItem] {
        guard !source.apiToken.isEmpty else { throw MediaServerError.missingCredentials }
        let session = NetworkPitfallGuards.makeResilientSession(allowSelfSignedLAN: allowSelfSignedLAN)
        var headers = NetworkPitfallGuards.standardHTTPHeaders(for: source)
        headers["Accept"] = "application/json"

        let path = (keyPath == nil || keyPath!.isEmpty) ? "/library/sections" : keyPath!
        let sep = path.contains("?") ? "&" : "?"
        guard let url = URL(string: "\(source.baseURLString)\(path)\(sep)X-Plex-Token=\(source.apiToken)") else {
            throw MediaServerError.invalidURL
        }
        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MediaServerError.serverError("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        let decoded = try JSONDecoder().decode(PlexResponse.self, from: data)
        var results: [MediaItem] = []

        for dir in decoded.MediaContainer.Directory ?? [] {
            let nextPath: String
            if dir.key.hasPrefix("/") {
                nextPath = dir.key
            } else {
                nextPath = "/library/sections/\(dir.key)/all"
            }
            results.append(MediaItem(
                id: "plex:\(source.id.uuidString):dir:\(nextPath)",
                title: dir.title,
                subtitle: dir.type?.capitalized ?? "媒体库",
                isDirectory: true,
                posterURL: dir.thumb.flatMap { URL(string: "\(source.baseURLString)\($0)?X-Plex-Token=\(source.apiToken)") },
                sourceId: source.id,
                protocolType: .plex,
                remotePath: nextPath,
                httpHeaders: headers
            ))
        }

        for meta in decoded.MediaContainer.Metadata ?? [] {
            let isContainer = (meta.type == "show" || meta.type == "season")
            let partKey = meta.Media?.first?.Part?.first?.key
            let streamURL = partKey.flatMap { URL(string: "\(source.baseURLString)\($0)?X-Plex-Token=\(source.apiToken)") }
            let posterURL = meta.thumb.flatMap { URL(string: "\(source.baseURLString)\($0)?X-Plex-Token=\(source.apiToken)") }
            let durationSec = meta.duration.map { Double($0) / 1000.0 }

            results.append(MediaItem(
                id: "plex:\(source.id.uuidString):\(meta.ratingKey ?? meta.key)",
                title: meta.title,
                subtitle: meta.parentTitle ?? meta.grandparentTitle,
                isDirectory: isContainer,
                streamURL: isContainer ? nil : streamURL,
                posterURL: posterURL,
                durationSeconds: durationSec,
                sourceId: source.id,
                protocolType: .plex,
                remotePath: meta.key,
                httpHeaders: headers,
                serverItemId: meta.ratingKey
            ))
        }
        return results
    }
}

// MARK: - Emby / Jellyfin DTOs

private struct EmbyUserDTO: Decodable {
    let Id: String
    let Name: String?
    let Policy: Policy?

    struct Policy: Decodable {
        let IsAdministrator: Bool?
    }
}

private struct EmbyItemsResponse: Decodable {
    let Items: [EmbyItemDTO]
}

private struct EmbyItemDTO: Decodable {
    let Id: String
    let Name: String
    let `Type`: String?
    let IsFolder: Bool?
    let SeriesName: String?
    let RunTimeTicks: Int64?
    let MediaSources: [EmbyMediaSourceDTO]?
}

private struct EmbyMediaSourceDTO: Decodable {
    let Id: String?
    let MediaStreams: [EmbyMediaStreamDTO]?
}

private struct EmbyMediaStreamDTO: Decodable {
    let Index: Int?
    let `Type`: String?
    let Codec: String?
    let Language: String?
    let DisplayTitle: String?
    let IsExternal: Bool?
}

// MARK: - Plex DTOs

private struct PlexResponse: Decodable {
    let MediaContainer: PlexContainerDTO
}

private struct PlexContainerDTO: Decodable {
    let Directory: [PlexDirectoryDTO]?
    let Metadata: [PlexMetadataDTO]?
}

private struct PlexDirectoryDTO: Decodable {
    let key: String
    let title: String
    let type: String?
    let thumb: String?
}

private struct PlexMetadataDTO: Decodable {
    let key: String
    let ratingKey: String?
    let title: String
    let type: String?
    let parentTitle: String?
    let grandparentTitle: String?
    let thumb: String?
    let duration: Int64?
    let Media: [PlexMediaDTO]?
}

private struct PlexMediaDTO: Decodable {
    let Part: [PlexPartDTO]?
}

private struct PlexPartDTO: Decodable {
    let key: String
}
