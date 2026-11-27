import Foundation
import AetherEngine
import AetherEngineSMB
import SMBClient

enum SMBClientError: LocalizedError {
    case missingShareName
    case invalidURL
    case timedOut(host: String, port: Int)
    case logonFailed(hasCredentials: Bool)
    case shareNotFound(share: String)
    case shareEnumerationDenied(detail: String)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingShareName:
            return "请先在 SMB 媒体源配置中填写共享文件夹名称（Share Name），或从服务器共享列表进入。"
        case .invalidURL:
            return "SMB 地址无效，请检查服务器 IP / 主机名与端口。"
        case .timedOut(let host, let port):
            return "连接 SMB 服务器 \(host):\(port) 超时（15 秒）。请检查 IP 与端口、电视与 NAS 是否在同一局域网，以及 Apple TV「设置 → 隐私 → 本地网络」权限是否已允许。"
        case .logonFailed(let hasCredentials):
            if hasCredentials {
                return "SMB 登录认证失败（Logon Failure）。请点击「编辑媒体源」核对用户名与密码（若 NAS 要求域账号可填 域\\用户名）。"
            }
            return "SMB 访客登录被服务器拒绝（Logon Failure）。请点击「编辑媒体源」填写 NAS 的 SMB 用户名与密码。"
        case .shareNotFound(let share):
            return "找不到 SMB 共享文件夹「\(share)」（Bad Network Name）。请点击「编辑媒体源」检查共享名拼写，或留空共享名以自动列出全部共享。"
        case .shareEnumerationDenied(let detail):
            return "服务器拒绝自动列出共享目录（\(detail)）。请点击「编辑媒体源」核对账号密码，或在「SMB 共享文件夹名」中直接填写共享名（例如 media / video）。"
        case .connectionFailed(let msg):
            return "SMB 连接失败：\(msg)。提示：AetherEngineSMB 使用 SMB 2.0.2/2.1（NTLMv2/访客），请在 NAS 中允许 SMB2，且不要强制开启 SMB3 加密或签名。"
        }
    }
}

private final class SMBAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func set() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}

private final class SMBActiveClientBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: SMBClient?

    func set(_ client: SMBClient?) {
        lock.lock()
        current = client
        lock.unlock()
    }

    func disconnectCurrent() {
        lock.lock()
        let client = current
        lock.unlock()
        client?.session.disconnect()
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

    /// 登录 →（可选）连接共享 → 执行操作 → 断开。
    /// - 未填用户名时先按访客登录，被拒后断开连接并用全新 SMBClient 退回完全匿名会话（避免在同一连接上二次 negotiate 被 NAS 直接踢断）；
    /// - 填了用户名支持 `域\用户名` 格式，登录失败即报错，不静默降级；
    /// - 全程带 15 秒连接/操作超时保护与 Task 取消即刻断连，杜绝不可达主机导致界面假死。
    private func withSession<T>(
        for source: MediaSourceConfig,
        share: String?,
        timeoutSeconds: UInt64 = 15,
        _ body: (SMBClient) async throws -> T
    ) async throws -> T {
        let target = try endpoint(for: source)
        let effectivePort = target.port > 0 ? target.port : 445
        let (parsedDomain, parsedUser) = Self.parseCredentials(username: target.username)
        let secret = target.password.isEmpty ? nil : target.password

        let didTimeout = SMBAtomicFlag()
        let activeClient = SMBActiveClientBox()

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            didTimeout.set()
            activeClient.disconnectCurrent()
        }
        defer {
            timeoutTask.cancel()
        }

        return try await withTaskCancellationHandler {
            let client: SMBClient
            do {
                if let user = parsedUser {
                    let c = Self.makeClient(host: target.host, port: effectivePort)
                    activeClient.set(c)
                    try await c.login(username: user, password: secret, domain: parsedDomain)
                    client = c
                } else {
                    let guestClient = Self.makeClient(host: target.host, port: effectivePort)
                    activeClient.set(guestClient)
                    do {
                        try await guestClient.login(username: "guest", password: nil, domain: nil)
                        client = guestClient
                    } catch {
                        guestClient.session.disconnect()
                        if Task.isCancelled { throw CancellationError() }
                        if didTimeout.get() {
                            throw SMBClientError.timedOut(host: target.host, port: effectivePort)
                        }
                        // 必须新建连接再尝试完全匿名登录；复旧连接二次 negotiate 违反 SMB2 协议必然失败
                        let anonClient = Self.makeClient(host: target.host, port: effectivePort)
                        activeClient.set(anonClient)
                        try await anonClient.login(username: nil, password: nil, domain: nil)
                        client = anonClient
                    }
                }

                if let share, !share.isEmpty {
                    try await client.connectShare(share)
                }

                let result = try await body(client)

                if let share, !share.isEmpty {
                    _ = try? await client.disconnectShare()
                }
                _ = try? await client.logoff()
                // logoff() 只结束 SMB 会话，底层 TCP 连接要一并断开，否则 socket 会挂到对象释放
                client.session.disconnect()
                activeClient.set(nil)
                return result
            } catch is CancellationError {
                activeClient.disconnectCurrent()
                activeClient.set(nil)
                throw CancellationError()
            } catch let smbError as SMBClientError {
                activeClient.disconnectCurrent()
                activeClient.set(nil)
                throw smbError
            } catch {
                activeClient.disconnectCurrent()
                activeClient.set(nil)
                if Task.isCancelled {
                    throw CancellationError()
                }
                if didTimeout.get() {
                    throw SMBClientError.timedOut(host: target.host, port: effectivePort)
                }
                throw Self.mapError(
                    error,
                    share: share,
                    hasCredentials: parsedUser != nil
                )
            }
        } onCancel: {
            activeClient.disconnectCurrent()
        }
    }

    private static func makeClient(host: String, port: Int) -> SMBClient {
        (port > 0 && port != 445) ? SMBClient(host: host, port: port) : SMBClient(host: host)
    }

    private static func parseCredentials(username: String) -> (domain: String?, user: String?) {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }
        if let slash = trimmed.firstIndex(of: "\\") {
            let domain = String(trimmed[..<slash]).trimmingCharacters(in: .whitespacesAndNewlines)
            let user = String(trimmed[trimmed.index(after: slash)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !user.isEmpty {
                return (domain.isEmpty ? nil : domain, user)
            }
        }
        return (nil, trimmed)
    }

    private static func mapError(_ error: Error, share: String?, hasCredentials: Bool) -> SMBClientError {
        if let response = error as? ErrorResponse {
            let status = response.header.status
            let detail = response.errorDescription ?? response.description
            switch status {
            case 0xC000006D: // STATUS_LOGON_FAILURE
                return .logonFailed(hasCredentials: hasCredentials)
            case 0xC00000CC: // STATUS_BAD_NETWORK_NAME
                if let share, !share.isEmpty {
                    return .shareNotFound(share: share)
                }
                return .shareEnumerationDenied(detail: detail)
            case 0xC0000022, // STATUS_ACCESS_DENIED
                 0xC00000BB, // STATUS_NOT_SUPPORTED
                 0xC0000034, // STATUS_OBJECT_NAME_NOT_FOUND
                 0xC0000002: // STATUS_NOT_IMPLEMENTED
                if share == nil || share?.isEmpty == true {
                    return .shareEnumerationDenied(detail: detail)
                }
                return .connectionFailed("访问被拒绝（\(detail)），请检查账号对该共享目录的读取权限")
            default:
                return .connectionFailed(detail)
            }
        }
        return .connectionFailed(error.localizedDescription)
    }

    /// "." / ".."、以 "." 开头的隐藏项，以及群晖的 @eaDir / #recycle 等缩略图与回收站目录
    private static func isNoise(_ file: File) -> Bool {
        if file.name == "." || file.name == ".." { return true }
        if file.name.hasPrefix(".") || file.name.hasPrefix("@eaDir") || file.name == "#recycle" { return true }
        return false
    }
}
