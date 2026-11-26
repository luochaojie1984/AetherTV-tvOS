import SwiftUI

struct SourceBrowserView: View {
    @EnvironmentObject private var sourceStore: MediaSourceStore
    @State private var showAddSourceSheet = false
    @State private var quickPlayItem: MediaItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        AppleTVSoundEffects.playSelect()
                        showAddSourceSheet = true
                    } label: {
                        Label("添加局域网媒体源（SMB / WebDAV / Emby / Jellyfin / Plex / DLNA）", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                }

                if !sourceStore.sources.isEmpty {
                    Section("已保存的媒体源") {
                        ForEach(sourceStore.sources) { source in
                            NavigationLink {
                                SourceDirectoryView(source: source, currentPath: source.protocolType == .dlna ? "0" : "/")
                            } label: {
                                HStack(spacing: 18) {
                                    Image(systemName: source.protocolType.iconName)
                                        .font(.title2)
                                        .frame(width: 44)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(source.name)
                                            .font(.headline)
                                        Text("\(source.protocolType.rawValue) · \(source.baseURLString)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if source.limitSingleConnection {
                                        Text("单连接限流")
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.orange.opacity(0.25), in: Capsule())
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .contextMenu {
                                Button("删除此媒体源", role: .destructive) {
                                    sourceStore.remove(id: source.id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("媒体源")
            .sheet(isPresented: $showAddSourceSheet) {
                AddMediaSourceView { newSource in
                    sourceStore.add(newSource)
                }
            }
            .fullScreenCover(item: $quickPlayItem) { item in
                PlayerScreenView(item: item, playlist: [item], sourceConfig: nil)
            }
        }
    }
}

struct SourceDirectoryView: View {
    let source: MediaSourceConfig
    let currentPath: String

    @EnvironmentObject private var settings: PlayerSettingsStore
    @EnvironmentObject private var historyStore: WatchHistoryStore

    @State private var items: [MediaItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var playingItem: MediaItem?

    private var playableItems: [MediaItem] {
        items.filter { !$0.isDirectory }
    }

    var body: some View {
        Group {
            if source.protocolType == .directURL {
                directURLPlayView
            } else if isLoading {
                VStack(spacing: 18) {
                    ProgressView()
                    Text("正在读取 \(source.name)…")
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                VStack(spacing: 18) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 760)
                    Button("重新加载") {
                        Task { await loadDirectory() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                    Text("此目录下没有可播放的视频文件")
                        .foregroundStyle(.secondary)
                }
            } else {
                List {
                    ForEach(items) { item in
                        if item.isDirectory {
                            NavigationLink {
                                SourceDirectoryView(source: source, currentPath: item.remotePath)
                            } label: {
                                Label(item.title, systemImage: "folder.fill")
                                    .font(.headline)
                            }
                        } else {
                            Button {
                                AppleTVSoundEffects.playSelect()
                                playingItem = item
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.headline)
                                            .lineLimit(1)
                                        HStack(spacing: 12) {
                                            if let size = item.formattedFileSize {
                                                Text(size)
                                            }
                                            if let sub = item.subtitle {
                                                Text(sub)
                                            }
                                            if let pos = historyStore.savedPosition(for: item.id) {
                                                Text("上次看到 \(BottomAppleProgressBar.formatTimestamp(pos))")
                                                    .foregroundStyle(.cyan)
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if historyStore.isFavorite(item) {
                                        Image(systemName: "star.fill")
                                            .foregroundStyle(.yellow)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .contextMenu {
                                Button(historyStore.isFavorite(item) ? "取消收藏" : "加入收藏") {
                                    historyStore.toggleFavorite(item)
                                }
                                Button("从头播放") {
                                    historyStore.clearProgress(for: item.id)
                                    playingItem = item
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(currentPath == "/" || currentPath == "0" ? source.name : (currentPath as NSString).lastPathComponent)
        .task {
            if source.protocolType != .directURL {
                await loadDirectory()
            }
        }
        .fullScreenCover(item: $playingItem) { item in
            PlayerScreenView(item: item, playlist: playableItems.isEmpty ? [item] : playableItems, sourceConfig: source)
        }
    }

    private var directURLPlayView: some View {
        VStack(spacing: 24) {
            Text(source.baseURLString)
                .font(.headline)
            Button("立即播放直链") {
                if let url = URL(string: source.baseURLString) {
                    playingItem = MediaItem(
                        id: "direct:\(source.id.uuidString)",
                        title: source.name,
                        isDirectory: false,
                        streamURL: url,
                        sourceId: source.id,
                        protocolType: .directURL,
                        remotePath: "/",
                        httpHeaders: NetworkPitfallGuards.standardHTTPHeaders(for: source)
                    )
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func loadDirectory() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            switch source.protocolType {
            case .webdav:
                let client = WebDAVClient(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
                items = try await client.listDirectory(source: source, path: currentPath)
            case .emby, .jellyfin, .plex:
                let client = MediaServerClients(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
                let parent = (currentPath == "/" || currentPath.isEmpty) ? nil : currentPath
                items = try await client.browse(source: source, parentId: parent)
            case .dlna:
                guard let url = URL(string: source.baseURLString) else {
                    throw MediaServerError.invalidURL
                }
                let client = DLNADiscoveryClient()
                items = try await client.browse(controlURL: url, objectId: currentPath, sourceId: source.id)
            case .smb:
                // 每次列举都会登录、连接共享、断开；共享名与账号来自媒体源配置
                let client = SMBSourceClient()
                items = try await client.listDirectory(source: source, path: currentPath)
            case .directURL:
                items = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AddMediaSourceView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (MediaSourceConfig) -> Void

    @State private var name = "客厅 NAS"
    @State private var protocolType: MediaProtocolType = .webdav
    @State private var host = "192.168.1.10"
    @State private var portText = "5005"
    @State private var useHTTPS = false
    @State private var basePath = "/"
    @State private var shareName = "video"
    @State private var username = ""
    @State private var password = ""
    @State private var apiToken = ""
    @State private var limitSingleConnection = false
    @State private var holdSourceConnection = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基本连接") {
                    TextField("名称", text: $name)
                    Picker("协议类型", selection: $protocolType) {
                        ForEach(MediaProtocolType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .onChange(of: protocolType) { _, newType in
                        portText = String(newType.defaultPort)
                    }
                    TextField("服务器 IP 或主机名", text: $host)
                    TextField("端口", text: $portText)
                    if protocolType != .smb {
                        Toggle("启用 HTTPS", isOn: $useHTTPS)
                        TextField("基础路径（如 /dav 或留空）", text: $basePath)
                    } else {
                        TextField("SMB 共享名（如 video / media）", text: $shareName)
                    }
                }

                Section("身份认证") {
                    if protocolType == .emby || protocolType == .jellyfin || protocolType == .plex {
                        TextField("API Key / X-Plex-Token", text: $apiToken)
                    } else if protocolType != .dlna {
                        TextField("用户名（访客可留空）", text: $username)
                        SecureField("密码", text: $password)
                    }
                }

                Section("局域网/网盘避坑选项") {
                    Toggle("单连接限流模式（适合 Alist/网盘反代）", isOn: $limitSingleConnection)
                    Toggle("保持长连接拉流（避免频繁 Range 断连）", isOn: $holdSourceConnection)
                }

                Section {
                    Button("保存媒体源") {
                        let config = MediaSourceConfig(
                            name: name.isEmpty ? host : name,
                            protocolType: protocolType,
                            host: host,
                            port: Int(portText) ?? protocolType.defaultPort,
                            useHTTPS: useHTTPS,
                            basePath: basePath,
                            username: username,
                            password: password,
                            apiToken: apiToken,
                            shareName: shareName,
                            limitSingleConnection: limitSingleConnection,
                            holdSourceConnection: holdSourceConnection
                        )
                        onSave(config)
                        dismiss()
                    }
                    .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("添加媒体源")
        }
    }
}
