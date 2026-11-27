import Foundation
import AetherEngine
import AetherEngineSMB
import SMBClient

enum SMBClientError: LocalizedError {
    case missingShareName
    case invalidURL
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingShareName:
            return "请先在 SMB 媒体源配置中填写共享文件夹名称（Share Name），或从服务器共享列表进入。"
        case .invalidURL:
            return "SMB 地址无效，请检查服务器地址与端口。"
        case .connectionFailed(let msg):
            return "SMB 连接失败：\(msg)。提示：AetherEngineSMB 使用 SMB 2.0.2/2.1（NTLMv2/访客），请在 NAS 中允许 SMB2，且不要强制开启 SMB3 加密或签名。"
        }
    }
}

/// SMB 媒体源客户端：
/// - 支持在未填写 `shareName` 时直接连接服务器并列出全部可用 SMB 共享文件夹
/// - 目录浏览与外挂字幕拉取：直接使用 AetherEngineSMB 底层的 SMBClient
/// - 播放：由 PlaybackController 经 AetherEngineSMB 的 SMBIOReader 接入引擎，这里只负责生成不含凭据的 smb:// 地址
///
/// 避坑：
/// 1. 路径一律使用服务器返回的原样文件名，不做 NFC/NFD 规范化——部分 NAS 按字节匹配文件名，规范化后会找不到文件
/// 2. 凭据不进 URL：smb:// 地址会随观看记录/收藏落盘，账号密码只在播放时按媒体源 ID 回查
final class SMBSourceClient: Sendable {

    private struct Endpoint: Sendable {
        let host: String
        let port: Int
        let username: String
        let password: String
    }

    /// 匹配同目录外挂字幕，同时严格保留服务器返回的原始字幕文件名字节（不做 NFC/NFD 改写）
    static func matchSubtitles(videoName: String, subtitleFiles: [String]) -> [String] {
        subtitleFiles.filter { subName in
            NetworkPitfallGuards.subtitleMatchesVideo(subtitleFilename: subName, videoFilename: videoName)
        }
    }

    /// 生成不含凭据的 smb:// 地址（`share` 为共享名，`relativePath` 为共享内相对路径）
    func buildSMBURL(source: MediaSourceConfig, share: String, relativePath: String) throws -> URL {
        let target = try endpoint(for: source)
        let cleanShare = share.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        guard !cleanShare.isEmpty else {
            throw SMBClientError.missingShareName
        }

        var components = URLComponents()
        components.scheme = "smb"
        components.host = target.host
        if target.port > 0 && target.port != 445 {
            components.port = target.port
        }

        let cleanRel = relativePath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        components.path = cleanRel.isEmpty ? "/\(cleanShare)" : "/\(cleanShare)/\(cleanRel)"

        guard let url = components.url else {
            throw SMBClientError.invalidURL
        }
        return url
    }

    /// 列出 SMB 服务器共享（当 `shareName` 为空且处于根目录 `/` 时）或共享内某个目录。
    /// 目录在前、视频在后，各自按自然顺序排列。
    func listDirectory(source: MediaSourceConfig, path: String) async throws -> [MediaItem] {
        let resolved = resolveShareAndSubpath(source: source, path: path)

        // 未指定共享名且在根目录：自动枚举服务器上所有非系统隐藏共享
        guard let shareName = resolved.share else {
            let shares = try await withSession(for: source, share: nil) { client in
                try await client.listShares()
            }
            let visibleShares = shares
                .filter { share in
                    let trimmed = share.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty || trimmed.hasSuffix("$") { return false }
                    if share.type.contains(.ipc) || share.type.contains(.printQueue) { return false }
                    return true
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            return visibleShares.map { share in
                MediaItem(
                    id: "smb:\(source.id.uuidString):share:\(share.name)",
                    title: share.name,
                    subtitle: share.comment.isEmpty ? "SMB 共享文件夹" : share.comment,
                    isDirectory: true,
                    streamURL: nil,
                    fileSize: nil,
                    sourceId: source.id,
                    protocolType: .smb,
                    remotePath: "/\(share.name)"
                )
            }
        }

        let directoryPath = resolved.subPath
        let files = try await withSession(for: source, share: shareName) { client in
            try await client.listDirectory(path: directoryPath, pattern: "*")
        }

        let byName: (File, File) -> Bool = {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let visible = files.filter { !Self.isNoise($0) }
        let directories = visible
            .filter { $0.isDirectory }
            .sorted(by: byName)
        let videos = visible
            .filter { !$0.isDirectory && MediaItem.isVideoFile($0.name) }
            .sorted(by: byName)
        let subtitleFiles = visible
            .filter { !$0.isDirectory && MediaItem.isSubtitleFile($0.name) }
            .sorted(by: byName)
        let subtitleNames = subtitleFiles.map(\.name)

        let configuredShare = source.shareName.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        let remotePrefix = configuredShare.isEmpty ? "/\(shareName)/" : "/"
        let parent = directoryPath.isEmpty ? "" : directoryPath + "/"
        var items: [MediaItem] = []

        for file in directories {
            let relativePath = parent + file.name
            items.append(MediaItem(
                id: "smb:\(source.id.uuidString):\(shareName):/\(relativePath)",
                title: file.name,
                subtitle: "文件夹",
                isDirectory: true,
                streamURL: nil,
                fileSize: nil,
                sourceId: source.id,
                protocolType: .smb,
                remotePath: remotePrefix + relativePath,
                smbRelativePath: relativePath
            ))
        }

        for file in videos {
            let relativePath = parent + file.name
            guard let url = try? buildSMBURL(source: source, share: shareName, relativePath: relativePath) else {
                continue
            }

            let matchedNames = Self.matchSubtitles(videoName: file.name, subtitleFiles: subtitleNames)
            let matchedSubs: [ExternalSubtitleReference] = matchedNames.compactMap { subName in
                let subRelPath = parent + subName
                guard let subURL = try? buildSMBURL(source: source, share: shareName, relativePath: subRelPath) else {
                    return nil
                }
                let ext = (subName as NSString).pathExtension.lowercased()
                return ExternalSubtitleReference(
                    title: subName,
                    language: NetworkPitfallGuards.inferSubtitleLanguageCode(from: subName),
                    url: subURL,
                    formatHint: ext,
                    smbRelativePath: subRelPath
                )
            }

            items.append(MediaItem(
                id: "smb:\(source.id.uuidString):\(shareName):/\(relativePath)",
                title: file.name,
                subtitle: matchedSubs.isEmpty ? nil : "含 \(matchedSubs.count) 条同目录外挂字幕",
                isDirectory: false,
                streamURL: url,
                fileSize: Int64(clamping: file.size),
                sourceId: source.id,
                protocolType: .smb,
                remotePath: remotePrefix + relativePath,
                externalSubtitles: matchedSubs,
                smbRelativePath: relativePath
            ))
        }
        return items
    }

    /// 播放前将匹配到的 SMB 同目录外挂字幕通过单个共享会话下载到临时目录，转换为本地 `file://` URL 供引擎挂载
    func downloadSubtitles(
        source: MediaSourceConfig,
        subtitles: [ExternalSubtitleReference],
        destinationDirectory: URL
    ) async throws -> [ExternalSubtitleReference] {
        guard !subtitles.isEmpty else { return [] }
        let configuredShare = source.shareName.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        let fallbackShare = subtitles.compactMap { sub -> String? in
            guard sub.url.scheme?.lowercased() == "smb" else { return nil }
            return sub.url.path.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init)
        }.first
        let shareName = configuredShare.isEmpty ? (fallbackShare ?? "") : configuredShare
        guard !shareName.isEmpty else { return [] }

        let maxSubtitleBytes = 50 * 1024 * 1024
        let pairs: [(ExternalSubtitleReference, String)] = subtitles.compactMap { sub in
            if let rel = sub.smbRelativePath, !rel.isEmpty {
                return (sub, rel)
            }
            if sub.url.scheme?.lowercased() == "smb" {
                let rawPath = sub.url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let sharePrefix = shareName + "/"
                if rawPath.hasPrefix(sharePrefix) {
                    return (sub, String(rawPath.dropFirst(sharePrefix.count)))
                }
            }
            return nil
        }

        guard !pairs.isEmpty else { return [] }
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        return try await withSession(for: source, share: shareName) { client in
            var localRefs: [ExternalSubtitleReference] = []
            for (index, pair) in pairs.enumerated() {
                let (sub, relPath) = pair
                guard let data = try? await client.download(path: relPath),
                      !data.isEmpty,
                      data.count <= maxSubtitleBytes else {
                    continue
                }
                let rawName = (sub.title as NSString).lastPathComponent
                let safeName = rawName.isEmpty ? "subtitle_\(index).srt" : rawName
                let localURL = destinationDirectory.appendingPathComponent("\(index)_\(safeName)")
                try data.write(to: localURL, options: .atomic)
                localRefs.append(ExternalSubtitleReference(
                    title: sub.title,
                    language: sub.language,
                    url: localURL,
                    formatHint: sub.formatHint,
                    httpHeaders: [:],
                    smbRelativePath: sub.smbRelativePath
                ))
            }
            return localRefs
        }
    }

    // MARK: - Private

    private func resolveShareAndSubpath(source: MediaSourceConfig, path: String) -> (share: String?, subPath: String) {
        let configuredShare = source.shareName.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        let cleanPath = path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if !configuredShare.isEmpty {
            return (configuredShare, cleanPath)
        }
        guard !cleanPath.isEmpty else {
            return (nil, "")
        }
        let parts = cleanPath.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        let share = parts.first.map(String.init)
        let subPath = parts.count > 1 ? String(parts[1]) : ""
        return (share, subPath)
    }

    private func endpoint(for source: MediaSourceConfig) throws -> Endpoint {
        let cleanHost = source.cleanedHost
        guard !cleanHost.isEmpty else {
            throw SMBClientError.invalidURL
        }

        return Endpoint(
            host: cleanHost,
            port: source.port,
            username: source.username,
            password: source.password
        )
    }

    /// 登录 →（可选）连接共享 → 执行操作 → 断开。登录策略与 AetherEngineSMB 的 `SMBConnection.connect` 一致：
    /// 未填用户名时先按访客登录，被拒后再退到完全匿名的 NTLM 会话；填了用户名则登录失败即报错，不降级。
    private func withSession<T>(
        for source: MediaSourceConfig,
        share: String?,
        _ body: (SMBClient) async throws -> T
    ) async throws -> T {
        let target = try endpoint(for: source)
        let client = (target.port > 0 && target.port != 445)
            ? SMBClient(host: target.host, port: target.port)
            : SMBClient(host: target.host)
        let account = target.username.isEmpty ? nil : target.username
        let secret = target.password.isEmpty ? nil : target.password

        let result: T
        do {
            do {
                try await client.login(username: account ?? "guest", password: secret, domain: nil)
            } catch where account == nil {
                try await client.login(username: nil, password: nil)
            }
            if let share, !share.isEmpty {
                try await client.connectShare(share)
            }
            result = try await body(client)
        } catch {
            client.session.disconnect()
            throw SMBClientError.connectionFailed(error.localizedDescription)
        }

        if let share, !share.isEmpty {
            _ = try? await client.disconnectShare()
        }
        _ = try? await client.logoff()
        // logoff() 只结束 SMB 会话，底层 TCP 连接要一并断开，否则 socket 会挂到对象释放
        client.session.disconnect()
        return result
    }

    /// "." / ".."、以 "." 开头的隐藏项，以及群晖的 @eaDir / #recycle 等缩略图与回收站目录
    private static func isNoise(_ file: File) -> Bool {
        if file.name == "." || file.name == ".." { return true }
        if file.name.hasPrefix(".") || file.name.hasPrefix("@eaDir") || file.name == "#recycle" { return true }
        return false
    }
}
