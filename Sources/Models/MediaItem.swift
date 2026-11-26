import Foundation

struct ExternalSubtitleReference: Identifiable, Codable, Hashable, Sendable {
    var id: String { url.absoluteString }
    let title: String
    let language: String?
    let url: URL
    let formatHint: String?
    let httpHeaders: [String: String]
}

struct MediaItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let isDirectory: Bool
    let streamURL: URL?
    let posterURL: URL?
    let fileSize: Int64?
    let durationSeconds: Double?
    let sourceId: UUID?
    let protocolType: MediaProtocolType
    let remotePath: String
    let httpHeaders: [String: String]
    let externalSubtitles: [ExternalSubtitleReference]
    /// 媒体服务器原始条目 ID（用于 Emby/Jellyfin/Plex 进度回传）
    let serverItemId: String?
    /// 若来自 SMB，记录共享内相对路径，便于 AetherEngineSMB 构造读取器
    let smbRelativePath: String?

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        isDirectory: Bool,
        streamURL: URL? = nil,
        posterURL: URL? = nil,
        fileSize: Int64? = nil,
        durationSeconds: Double? = nil,
        sourceId: UUID? = nil,
        protocolType: MediaProtocolType,
        remotePath: String,
        httpHeaders: [String: String] = [:],
        externalSubtitles: [ExternalSubtitleReference] = [],
        serverItemId: String? = nil,
        smbRelativePath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.isDirectory = isDirectory
        self.streamURL = streamURL
        self.posterURL = posterURL
        self.fileSize = fileSize
        self.durationSeconds = durationSeconds
        self.sourceId = sourceId
        self.protocolType = protocolType
        self.remotePath = remotePath
        self.httpHeaders = httpHeaders
        self.externalSubtitles = externalSubtitles
        self.serverItemId = serverItemId
        self.smbRelativePath = smbRelativePath
    }

    var formattedFileSize: String? {
        guard let fileSize, fileSize > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    static let supportedVideoExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "mov", "avi", "ts", "m2ts", "mts",
        "webm", "flv", "wmv", "asf", "rm", "rmvb", "vob", "mpg",
        "mpeg", "iso", "img", "3gp", "ogv", "m3u8", "mpd"
    ]

    static let supportedSubtitleExtensions: Set<String> = [
        "srt", "ass", "ssa", "vtt", "sup", "sub", "idx"
    ]

    static let discImageExtensions: Set<String> = ["iso", "img"]

    static func isVideoFile(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return supportedVideoExtensions.contains(ext)
    }

    static func isSubtitleFile(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return supportedSubtitleExtensions.contains(ext)
    }

    /// 光盘镜像（ISO / IMG）。经 SMB 读取时要保留引擎的 ISO/UDF 签名探测，普通文件则跳过。
    var isDiscImage: Bool {
        guard let streamURL else { return false }
        return Self.discImageExtensions.contains(streamURL.pathExtension.lowercased())
    }
}
