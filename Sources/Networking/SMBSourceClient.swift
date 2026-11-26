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
            return "请先在 SMB 媒体源配置中填写共享文件夹名称（Share Name），例如 video 或 media。"
        case .invalidURL:
            return "SMB 地址无效，请检查服务器地址、端口与共享名。"
        case .connectionFailed(let msg):
            return "SMB 连接失败：\(msg)。提示：AetherEngineSMB 使用 SMB 2.0.2/2.1（NTLMv2/访客），请在 NAS 中允许 SMB2，且不要强制开启 SMB3 加密或签名。"
        }
    }
}

/// SMB 媒体源客户端：
/// - 目录浏览：直接使用 AetherEngineSMB 底层的 SMBClient（AetherEngineSMB 自身只提供单文件字节读取，没有目录列举 API）
/// - 播放：由 PlaybackController 经 AetherEngineSMB 的 SMBIOReader 接入引擎，这里只负责生成不含凭据的 smb:// 地址
///
/// 避坑：
/// 1. 路径一律使用服务器返回的原样文件名，不做 NFC/NFD 规范化——部分 NAS 按字节匹配文件名，规范化后会找不到文件
/// 2. 凭据不进 URL：smb:// 地址会随观看记录/收藏落盘，账号密码只在播放时按媒体源 ID 回查
final class SMBSourceClient: Sendable {

    private struct Endpoint: Sendable {
        let host: String
        let port: Int
        let share: String
        let username: String
        let password: String
    }

    /// 生成不含凭据的 smb:// 地址（`relativePath` 为共享内相对路径）
    func buildSMBURL(source: MediaSourceConfig, relativePath: String) throws -> URL {
        let target = try endpoint(for: source)

        var components = URLComponents()
        components.scheme = "smb"
        components.host = target.host
        if target.port > 0 && target.port != 445 {
            components.port = target.port
        }

        let cleanRel = relativePath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        components.path = cleanRel.isEmpty ? "/\(target.share)" : "/\(target.share)/\(cleanRel)"

        guard let url = components.url else {
            throw SMBClientError.invalidURL
        }
        return url
    }

    /// 列出共享内某个目录（`path` 为以 "/" 开头的共享内相对路径，"/" 即共享根目录）下的子目录与视频文件。
    /// 目录在前、视频在后，各自按自然顺序排列。
    func listDirectory(source: MediaSourceConfig, path: String) async throws -> [MediaItem] {
        let directoryPath = path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let files = try await withSession(for: source) { client in
            try await client.listDirectory(path: directoryPath, pattern: "*")
        }

        let byName: (SMBClient.File, SMBClient.File) -> Bool = {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let visible = files.filter { !Self.isNoise($0) }
        let directories = visible
            .filter { $0.isDirectory }
            .sorted(by: byName)
        let videos = visible
            .filter { !$0.isDirectory && MediaItem.isVideoFile($0.name) }
            .sorted(by: byName)

        let parent = directoryPath.isEmpty ? "" : directoryPath + "/"
        var items: [MediaItem] = []
        for file in directories + videos {
            let relativePath = parent + file.name
            guard let url = try? buildSMBURL(source: source, relativePath: relativePath) else {
                continue
            }
            items.append(MediaItem(
                id: "smb:\(source.id.uuidString):/\(relativePath)",
                title: file.name,
                subtitle: file.isDirectory ? "文件夹" : nil,
                isDirectory: file.isDirectory,
                streamURL: file.isDirectory ? nil : url,
                fileSize: file.isDirectory ? nil : Int64(clamping: file.size),
                sourceId: source.id,
                protocolType: .smb,
                remotePath: "/" + relativePath,
                smbRelativePath: relativePath
            ))
        }
        return items
    }

    // MARK: - Private

    private func endpoint(for source: MediaSourceConfig) throws -> Endpoint {
        let share = source.shareName.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        guard !share.isEmpty else {
            throw SMBClientError.missingShareName
        }

        let cleanHost = source.host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "smb://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanHost.isEmpty else {
            throw SMBClientError.invalidURL
        }

        return Endpoint(
            host: cleanHost,
            port: source.port,
            share: share,
            username: source.username,
            password: source.password
        )
    }

    /// 登录 → 连接共享 → 执行操作 → 断开。登录策略与 AetherEngineSMB 的 `SMBConnection.connect` 一致：
    /// 未填用户名时先按访客登录，被拒后再退到完全匿名的 NTLM 会话；填了用户名则登录失败即报错，不降级。
    private func withSession<T>(
        for source: MediaSourceConfig,
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
            try await client.connectShare(target.share)
            result = try await body(client)
        } catch {
            client.session.disconnect()
            throw SMBClientError.connectionFailed(error.localizedDescription)
        }

        try? await client.disconnectShare()
        try? await client.logoff()
        // logoff() 只结束 SMB 会话，底层 TCP 连接要一并断开，否则 socket 会挂到对象释放
        client.session.disconnect()
        return result
    }

    /// "." / ".."、以 "." 开头的隐藏项，以及群晖的 @eaDir / #recycle 等缩略图与回收站目录
    private static func isNoise(_ file: SMBClient.File) -> Bool {
        if file.name == "." || file.name == ".." { return true }
        if file.name.hasPrefix(".") || file.name.hasPrefix("@eaDir") || file.name == "#recycle" { return true }
        return false
    }
}
