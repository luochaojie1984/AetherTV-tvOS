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
            return "请填写服务器 API Token（或使用账号密码登录获取）。"
        case .missingControlURL:
            return "DLNA 需要填写内容目录的 Control 地址路径（社区常见值：MiniDLNA 为 /ctl/ContentDir，Windows 媒体共享为 /ContentDirectory/Control）。"
        case .serverError(let msg):
            return "媒体服务器返回错误：\(msg)"
        }
    }
}

struct EmbyUserSummary: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isAdmin: Bool
}

struct EmbyAuthResult: Sendable {
    let accessToken: String
    let userId: String
    let userName: String
}

enum PlaybackSyncEvent: Sendable {
    case started
    case playing
    case paused
    case stopped
}

/// 统一支持 Emby / Jellyfin / Plex 的局域网直连（Direct Play）与进度双向同步客户端
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

    // MARK: - Emby / Jellyfin 账号登录与用户查询

    /// 使用用户名和密码向 Emby / Jellyfin `/Users/AuthenticateByName` 登录并换取 AccessToken 与 UserId
    func authenticateEmby(source: MediaSourceConfig, username: String, password: String) async throws -> EmbyAuthResult {
        guard let url = URL(string: "\(source.baseURLString)/Users/AuthenticateByName") else {
            throw MediaServerError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(NetworkPitfallGuards.embyAuthorizationHeader(), forHTTPHeaderField: "X-Emby-Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "Username": username,
            "Pw": password
        ])

        let session = NetworkPitfallGuards.sharedSession(allowSelfSignedLAN: allowSelfSignedLAN)
        let (data, resp) = try await session.data(for: request)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw MediaServerError.serverError("登录失败（HTTP \(code)），请检查用户名或密码")
        }

        let decoded = try JSONDecoder().decode(EmbyAuthResponseDTO.self, from: data)
        return EmbyAuthResult(
            accessToken: decoded.AccessToken,
            userId: decoded.User.Id,
            userName: decoded.User.Name ?? username
        )
    }

    /// 列出 Emby / Jellyfin 用户列表，供用户显式挑选目标账户
    func fetchEmbyUsers(source: MediaSourceConfig) async throws -> [EmbyUserSummary] {
        guard !source.apiToken.isEmpty else { throw MediaServerError.missingCredentials }
        guard let url = URL(string: "\(source.baseURLString)/Users") else {
            throw MediaServerError.invalidURL
        }
        var request = URLRequest(url: url)
        for (key, value) in NetworkPitfallGuards.standardHTTPHeaders(for: source) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let session = NetworkPitfallGuards.sharedSession(allowSelfSignedLAN: allowSelfSignedLAN)
        let (data, resp) = try await session.data(for: request)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MediaServerError.serverError("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let users = try JSONDecoder().decode([EmbyUserDTO].self, from: data)
        return users.map {
            EmbyUserSummary(
                id: $0.Id,
                name: $0.Name ?? $0.Id,
                isAdmin: $0.Policy?.IsAdministrator ?? false
            )
        }
    }

    // MARK: - Emby / Jellyfin 目录浏览

    /// Emby / Jellyfin 用户 ID 解析：
    /// 1. 优先使用媒体源配置里指定的 `userId`
    /// 2. 请求 `/Users/Me`（适用于用户级 Token）
    /// 3. 回退请求 `/Users`，按服务器返回顺序取首个未禁用用户（不再硬编码优先管理员）
    private func resolvedEmbyUserId(
        source: MediaSourceConfig,
        session: URLSession,
        headers: [String: String]
    ) async -> String? {
        if !source.userId.isEmpty { return source.userId }

        if let meURL = URL(string: "\(source.baseURLString)/Users/Me") {
            var meReq = URLRequest(url: meURL)
            for (key, value) in headers { meReq.setValue(value, forHTTPHeaderField: key) }
            if let (data, response) = try? await session.data(for: meReq),
               let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let me = try? JSONDecoder().decode(EmbyUserDTO.self, from: data) {
                return me.Id
            }
        }

        guard let url = URL(string: "\(source.baseURLString)/Users") else { return nil }
        var request = URLRequest(url: url)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let users = try? JSONDecoder().decode([EmbyUserDTO].self, from: data) else { return nil }
        return users.first(where: { $0.Policy?.IsDisabled != true })?.Id ?? users.first?.Id
    }

    private func browseEmbyOrJellyfin(source: MediaSourceConfig, parentId: String?) async throws -> [MediaItem] {
        guard !source.apiToken.isEmpty else { throw MediaServerError.missingCredentials }
        let session = NetworkPitfallGuards.sharedSession(allowSelfSignedLAN: allowSelfSignedLAN)
        let headers = NetworkPitfallGuards.standardHTTPHeaders(for: source)

        let endpoint: String
        let userId = await resolvedEmbyUserId(source: source, session: session, headers: headers)
        if let parentId, !parentId.isEmpty {
            let itemsBase = userId.map { "\(source.baseURLString)/Users/\($0)/Items" } ?? "\(source.baseURLString)/Items"
            endpoint = "\(itemsBase)?ParentId=\(parentId)&Fields=MediaSources,Overview,RunTimeTicks,UserData&SortBy=SortName&SortOrder=Ascending"
        } else if let userId {
            endpoint = "\(source.baseURLString)/Users/\(userId)/Views"
        } else {
            endpoint = "\(source.baseURLString)/Items?Recursive=false&Fields=MediaSources,Overview,RunTimeTicks,UserData"
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
            let serverResume = item.UserData?.PlaybackPositionTicks.flatMap { ticks -> Double? in
                let sec = Double(ticks) / 10_000_000.0
                return sec > 8 ? sec : nil
            }
            // 不再把 api_key 写入 URL Query，全部由请求头（X-Emby-Token / X-Emby-Authorization）鉴权
            let streamURL: URL? = isDir ? nil : URL(
                string: "\(source.baseURLString)/Videos/\(item.Id)/stream?Static=true"
            )
            let posterURL = URL(
                string: "\(source.baseURLString)/Items/\(item.Id)/Images/Primary?maxWidth=480"
            )

            // 提取服务器声明的外挂字幕直链
            let extSubs: [ExternalSubtitleReference] = (item.MediaSources?.first?.MediaStreams ?? [])
                .filter { $0.Type == "Subtitle" && ($0.IsExternal ?? false) }
                .compactMap { stream in
                    guard let idx = stream.Index,
                          let mediaSourceId = item.MediaSources?.first?.Id else { return nil }
                    let codec = (stream.Codec ?? "srt").lowercased()
                    let subURLStr = "\(source.baseURLString)/Videos/\(item.Id)/\(mediaSourceId)/Subtitles/\(idx)/Stream.\(codec)"
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
                serverItemId: item.Id,
                serverResumeSeconds: serverResume
            )
        }
    }

    // MARK: - Plex

    private func browsePlex(source: MediaSourceConfig, keyPath: String?) async throws -> [MediaItem] {
        guard !source.apiToken.isEmpty else { throw MediaServerError.missingCredentials }
        let session = NetworkPitfallGuards.sharedSession(allowSelfSignedLAN: allowSelfSignedLAN)
        var headers = NetworkPitfallGuards.standardHTTPHeaders(for: source)
        headers["Accept"] = "application/json"

        let path = (keyPath == nil || keyPath!.isEmpty) ? "/library/sections" : keyPath!
        guard let url = URL(string: "\(source.baseURLString)\(path)") else {
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
                posterURL: dir.thumb.flatMap { URL(string: "\(source.baseURLString)\($0)") },
                sourceId: source.id,
                protocolType: .plex,
                remotePath: nextPath,
                httpHeaders: headers
            ))
        }

        for meta in decoded.MediaContainer.Metadata ?? [] {
            let isContainer = (meta.type == "show" || meta.type == "season")
            let partKey = meta.Media?.first?.Part?.first?.key
            let streamURL = partKey.flatMap { URL(string: "\(source.baseURLString)\($0)") }
            let posterURL = meta.thumb.flatMap { URL(string: "\(source.baseURLString)\($0)") }
            let durationSec = meta.duration.map { Double($0) / 1000.0 }
            let serverResume = meta.viewOffset.flatMap { offset -> Double? in
                let sec = Double(offset) / 1000.0
                return sec > 8 ? sec : nil
            }

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
                serverItemId: meta.ratingKey,
                serverResumeSeconds: serverResume
            ))
        }
        return results
    }

    // MARK: - Emby / Jellyfin / Plex 播放进度同步回传

    func reportProgress(
        source: MediaSourceConfig,
        item: MediaItem,
        positionSeconds: Double,
        durationSeconds: Double,
        event: PlaybackSyncEvent
    ) async {
        guard !source.apiToken.isEmpty,
              let itemId = item.serverItemId, !itemId.isEmpty,
              positionSeconds.isFinite else {
            return
        }

        let session = NetworkPitfallGuards.sharedSession(allowSelfSignedLAN: allowSelfSignedLAN)
        let headers = NetworkPitfallGuards.standardHTTPHeaders(for: source)

        switch source.protocolType {
        case .emby, .jellyfin:
            let path: String
            switch event {
            case .started: path = "/Sessions/Playing"
            case .playing, .paused: path = "/Sessions/Playing/Progress"
            case .stopped: path = "/Sessions/Playing/Stopped"
            }
            guard let url = URL(string: "\(source.baseURLString)\(path)") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

            let ticks = Int64(max(0, positionSeconds) * 10_000_000)
            let body: [String: Any] = [
                "ItemId": itemId,
                "PositionTicks": ticks,
                "IsPaused": event == .paused,
                "CanSeek": true,
                "PlayMethod": "DirectPlay",
                "EventName": event == .paused ? "Pause" : (event == .stopped ? "Stop" : "TimeUpdate")
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await session.data(for: req)

        case .plex:
            let state: String
            switch event {
            case .started, .playing: state = "playing"
            case .paused: state = "paused"
            case .stopped: state = "stopped"
            }
            guard var components = URLComponents(string: "\(source.baseURLString)/:/timeline") else { return }
            let timeMs = Int64(max(0, positionSeconds) * 1000)
            let durMs = Int64(max(0, durationSeconds) * 1000)
            components.queryItems = [
                URLQueryItem(name: "ratingKey", value: itemId),
                URLQueryItem(name: "key", value: "/library/metadata/\(itemId)"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "time", value: String(timeMs)),
                URLQueryItem(name: "duration", value: String(durMs))
            ]
            guard let url = components.url else { return }
            var req = URLRequest(url: url)
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            _ = try? await session.data(for: req)

        default:
            break
        }
    }
}

// MARK: - Emby / Jellyfin DTOs

private struct EmbyAuthResponseDTO: Decodable {
    let AccessToken: String
    let User: EmbyUserDTO
}

private struct EmbyUserDTO: Decodable {
    let Id: String
    let Name: String?
    let Policy: Policy?

    struct Policy: Decodable {
        let IsAdministrator: Bool?
        let IsDisabled: Bool?
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
    let UserData: EmbyUserDataDTO?
    let MediaSources: [EmbyMediaSourceDTO]?
}

private struct EmbyUserDataDTO: Decodable {
    let PlaybackPositionTicks: Int64?
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
    let viewOffset: Int64?
    let Media: [PlexMediaDTO]?
}

private struct PlexMediaDTO: Decodable {
    let Part: [PlexPartDTO]?
}

private struct PlexPartDTO: Decodable {
    let key: String
}
