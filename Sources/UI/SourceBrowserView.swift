import SwiftUI

struct SourceBrowserView: View {
    @EnvironmentObject private var sourceStore: MediaSourceStore
    @State private var addingProtocol: MediaProtocolType?
    @State private var editingSource: MediaSourceConfig?
    @State private var discoveredPrefill: DiscoveredLANService?
    @State private var showQRConfigSheet = false
    @State private var showLANDiscoverySheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                AetherAmbientBackdrop(accent: Color(red: 0.16, green: 0.68, blue: 1.0))

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 44) {
                        // 1. 顶部快捷添加方式（双大号图标卡：手机扫码 & 自动发现）
                        VStack(alignment: .leading, spacing: 20) {
                            AetherSectionHeader(
                                title: "媒体源中心",
                                subtitle: "支持手机扫码、自动发现与 7 大局域网协议",
                                icon: "server.rack"
                            )

                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 28), GridItem(.flexible(), spacing: 28)], spacing: 28) {
                                Button {
                                    AppleTVSoundEffects.playSelect()
                                    showQRConfigSheet = true
                                } label: {
                                    HStack(spacing: 24) {
                                        AetherIconMedallion(
                                            systemName: "qrcode.viewfinder",
                                            colors: [Color(red: 0.08, green: 0.60, blue: 0.68), Color(red: 0.22, green: 0.88, blue: 0.86)],
                                            size: 76
                                        )
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("手机扫码 / 网页快速添加")
                                                .font(.system(size: 27, weight: .bold))
                                                .foregroundStyle(Color.white)
                                            Text("无需遥控器打字，手机扫一扫即可填写 SMB、WebDAV、Emby、Plex 等配置")
                                                .font(.system(size: 18))
                                                .foregroundStyle(Color.white.opacity(0.68))
                                                .lineLimit(2)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(28)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(AetherSpotlightCardStyle(accent: Color(red: 0.16, green: 0.86, blue: 0.84), cornerRadius: 24))

                                Button {
                                    AppleTVSoundEffects.playSelect()
                                    showLANDiscoverySheet = true
                                } label: {
                                    HStack(spacing: 24) {
                                        AetherIconMedallion(
                                            systemName: "dot.radiowaves.left.and.right",
                                            colors: [Color(red: 0.48, green: 0.28, blue: 0.96), Color(red: 0.24, green: 0.72, blue: 1.0)],
                                            size: 76
                                        )
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("自动扫描局域网设备")
                                                .font(.system(size: 27, weight: .bold))
                                                .foregroundStyle(Color.white)
                                            Text("Bonjour + SSDP 自动发现内网 NAS、SMB 共享、WebDAV、Emby、Plex 与 DLNA")
                                                .font(.system(size: 18))
                                                .foregroundStyle(Color.white.opacity(0.68))
                                                .lineLimit(2)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(28)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(AetherSpotlightCardStyle(accent: Color(red: 0.54, green: 0.42, blue: 1.0), cornerRadius: 24))
                            }
                        }

                        // 2. 按协议图标添加（SMB 置于首位，大号渐变图标卡片，告别纯文字下拉列表）
                        VStack(alignment: .leading, spacing: 20) {
                            AetherSectionHeader(
                                title: "选择协议添加媒体源",
                                subtitle: "点按图标直接配置",
                                icon: "plus.circle.fill"
                            )

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 340, maximum: 420), spacing: 26)],
                                spacing: 26
                            ) {
                                ForEach(MediaProtocolType.allCases) { proto in
                                    Button {
                                        AppleTVSoundEffects.playSelect()
                                        addingProtocol = proto
                                    } label: {
                                        HStack(spacing: 20) {
                                            AetherIconMedallion(
                                                systemName: proto.cardSymbolName,
                                                colors: proto.gradientColors,
                                                size: 64
                                            )
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(proto.displayName)
                                                    .font(.system(size: 25, weight: .bold))
                                                    .foregroundStyle(Color.white)
                                                Text(proto.shortTagline)
                                                    .font(.system(size: 17))
                                                    .foregroundStyle(Color.white.opacity(0.65))
                                                    .lineLimit(2)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(22)
                                        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
                                    }
                                    .buttonStyle(AetherSpotlightCardStyle(accent: proto.accentColor, cornerRadius: 22))
                                }
                            }
                        }

                        // 3. 已保存的媒体源
                        if !sourceStore.sources.isEmpty {
                            VStack(alignment: .leading, spacing: 20) {
                                AetherSectionHeader(
                                    title: "已保存的媒体源",
                                    subtitle: "长按确认键可编辑或删除",
                                    icon: "externaldrive.connected.to.line.below"
                                )

                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 460, maximum: 580), spacing: 28)],
                                    spacing: 26
                                ) {
                                    ForEach(sourceStore.sources) { source in
                                        NavigationLink {
                                            SourceDirectoryView(
                                                source: source,
                                                currentPath: source.protocolType == .dlna ? "0" : "/"
                                            )
                                        } label: {
                                            HStack(spacing: 22) {
                                                AetherIconMedallion(
                                                    systemName: source.protocolType.cardSymbolName,
                                                    colors: source.protocolType.gradientColors,
                                                    size: 68
                                                )
                                                VStack(alignment: .leading, spacing: 6) {
                                                    HStack(spacing: 10) {
                                                        Text(source.name)
                                                            .font(.system(size: 26, weight: .bold))
                                                            .foregroundStyle(Color.white)
                                                            .lineLimit(1)
                                                        Text(source.protocolType.rawValue)
                                                            .font(.system(size: 14, weight: .bold))
                                                            .foregroundStyle(Color.white)
                                                            .padding(.horizontal, 10)
                                                            .padding(.vertical, 3)
                                                            .background(source.protocolType.accentColor.opacity(0.32), in: Capsule())
                                                    }
                                                    Text(source.baseURLString)
                                                        .font(.system(size: 18))
                                                        .foregroundStyle(Color.white.opacity(0.64))
                                                        .lineLimit(1)
                                                    if source.limitSingleConnection || source.holdSourceConnection {
                                                        HStack(spacing: 8) {
                                                            if source.limitSingleConnection {
                                                                tagPill("单连接限流", color: .orange)
                                                            }
                                                            if source.holdSourceConnection {
                                                                tagPill("保持长连接", color: .cyan)
                                                            }
                                                        }
                                                    }
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 20, weight: .bold))
                                                    .foregroundStyle(Color.white.opacity(0.5))
                                            }
                                            .padding(24)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(AetherSpotlightCardStyle(accent: source.protocolType.accentColor, cornerRadius: 22))
                                        .contextMenu {
                                            Button("编辑此媒体源") {
                                                editingSource = source
                                            }
                                            Button("删除此媒体源", role: .destructive) {
                                                sourceStore.remove(id: source.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 32)
                }
            }
            .sheet(item: $addingProtocol) { proto in
                AddMediaSourceView(initialProtocol: proto) { newSource in
                    sourceStore.add(newSource)
                }
            }
            .sheet(item: $editingSource) { source in
                AddMediaSourceView(editing: source) { updated in
                    sourceStore.update(updated)
                }
            }
            .sheet(item: $discoveredPrefill) { service in
                AddMediaSourceView(discoveredService: service) { newSource in
                    sourceStore.add(newSource)
                }
            }
            .sheet(isPresented: $showQRConfigSheet) {
                QuickConfigQRView { imported in
                    sourceStore.add(imported)
                }
            }
            .sheet(isPresented: $showLANDiscoverySheet) {
                LANDiscoverySheetView { service in
                    discoveredPrefill = service
                }
            }
        }
    }

    private func tagPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.30), in: Capsule())
    }
}

// MARK: - 媒体源目录浏览（精美玻璃卡片网格，杜绝纯文字白底白字列表）

struct SourceDirectoryView: View {
    let source: MediaSourceConfig
    let currentPath: String
    /// 由上一级传入的显示名：Emby / Plex / DLNA 的 remotePath 是服务器内部 ID，
    /// 直接拿来当标题会显示成数字 ID，所以标题由导航方带上。
    var displayTitle: String? = nil

    @EnvironmentObject private var settings: PlayerSettingsStore
    @EnvironmentObject private var historyStore: WatchHistoryStore

    @State private var items: [MediaItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var playingItem: MediaItem?

    private var playableItems: [MediaItem] {
        items.filter { !$0.isDirectory }
    }

    private var navigationTitle: String {
        if let displayTitle, !displayTitle.isEmpty { return displayTitle }
        if currentPath == "/" || currentPath == "0" || currentPath.isEmpty { return source.name }
        return (currentPath as NSString).lastPathComponent
    }

    var body: some View {
        ZStack {
            AetherAmbientBackdrop(accent: source.protocolType.accentColor)

            if source.protocolType == .directURL {
                directURLPlayView
            } else if isLoading {
                VStack(spacing: 22) {
                    ProgressView()
                        .scaleEffect(1.4)
                    Text("正在读取 \(source.name)…")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            } else if let errorMessage {
                VStack(spacing: 22) {
                    AetherIconMedallion(
                        systemName: "wifi.exclamationmark",
                        colors: [Color(red: 0.90, green: 0.42, blue: 0.14), Color(red: 0.98, green: 0.68, blue: 0.22)],
                        size: 82
                    )
                    Text(errorMessage)
                        .font(.system(size: 24))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 820)
                    Button("重新加载") {
                        AppleTVSoundEffects.playSelect()
                        Task { await loadDirectory() }
                    }
                    .buttonStyle(AetherPillButtonStyle(accent: source.protocolType.accentColor, prominent: true))
                }
                .padding(48)
            } else if items.isEmpty {
                VStack(spacing: 18) {
                    AetherIconMedallion(
                        systemName: "folder",
                        colors: [Color(white: 0.24), Color(white: 0.16)],
                        size: 76
                    )
                    Text("此目录下没有可播放的视频文件")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.70))
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 460, maximum: 580), spacing: 26)],
                        spacing: 24
                    ) {
                        ForEach(items) { item in
                            if item.isDirectory {
                                NavigationLink {
                                    SourceDirectoryView(source: source, currentPath: item.remotePath, displayTitle: item.title)
                                } label: {
                                    HStack(spacing: 20) {
                                        AetherIconMedallion(
                                            systemName: "folder.fill",
                                            colors: [Color(red: 0.18, green: 0.50, blue: 0.96), Color(red: 0.24, green: 0.78, blue: 0.98)],
                                            size: 60
                                        )
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.title)
                                                .font(.system(size: 24, weight: .bold))
                                                .foregroundStyle(Color.white)
                                                .lineLimit(1)
                                            Text(item.subtitle ?? "文件夹")
                                                .font(.system(size: 17))
                                                .foregroundStyle(Color.white.opacity(0.58))
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(Color.white.opacity(0.45))
                                    }
                                    .padding(20)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(AetherSpotlightCardStyle(accent: source.protocolType.accentColor, cornerRadius: 20))
                            } else {
                                Button {
                                    AppleTVSoundEffects.playSelect()
                                    playingItem = item
                                } label: {
                                    HStack(spacing: 20) {
                                        if item.posterURL != nil {
                                            AuthenticatedPosterImage(url: item.posterURL, sourceId: item.sourceId) {
                                                AetherIconMedallion(
                                                    systemName: "play.fill",
                                                    colors: source.protocolType.gradientColors,
                                                    size: 60
                                                )
                                            }
                                            .frame(width: 96, height: 64)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        } else {
                                            AetherIconMedallion(
                                                systemName: "play.fill",
                                                colors: source.protocolType.gradientColors,
                                                size: 60
                                            )
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(item.title)
                                                .font(.system(size: 23, weight: .bold))
                                                .foregroundStyle(Color.white)
                                                .lineLimit(1)

                                            HStack(spacing: 12) {
                                                if let size = item.formattedFileSize {
                                                    Text(size)
                                                        .foregroundStyle(Color.white.opacity(0.68))
                                                }
                                                if !item.externalSubtitles.isEmpty {
                                                    Label("\(item.externalSubtitles.count) 字幕", systemImage: "captions.bubble.fill")
                                                        .foregroundStyle(Color(red: 0.42, green: 0.88, blue: 1.0))
                                                } else if let sub = item.subtitle {
                                                    Text(sub)
                                                        .foregroundStyle(Color.white.opacity(0.64))
                                                        .lineLimit(1)
                                                }
                                                if let pos = historyStore.savedPosition(for: item.id) {
                                                    Text("续播 \(BottomAppleProgressBar.formatTimestamp(pos))")
                                                        .foregroundStyle(Color.green)
                                                }
                                            }
                                            .font(.system(size: 16, weight: .medium))
                                        }

                                        Spacer(minLength: 8)

                                        if historyStore.isFavorite(item) {
                                            Image(systemName: "star.fill")
                                                .font(.system(size: 22))
                                                .foregroundStyle(Color.yellow)
                                        }
                                    }
                                    .padding(20)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(AetherSpotlightCardStyle(accent: source.protocolType.accentColor, cornerRadius: 20))
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
                    .padding(.horizontal, 60)
                    .padding(.vertical, 32)
                }
            }
        }
        .navigationTitle(navigationTitle)
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
        VStack(spacing: 28) {
            AetherIconMedallion(
                systemName: MediaProtocolType.directURL.cardSymbolName,
                colors: MediaProtocolType.directURL.gradientColors,
                size: 88
            )
            Text(source.baseURLString)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.85))
            Button {
                AppleTVSoundEffects.playSelect()
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
            } label: {
                Label("立即播放直链", systemImage: "play.fill")
                    .font(.system(size: 24, weight: .bold))
            }
            .buttonStyle(AetherPillButtonStyle(accent: MediaProtocolType.directURL.accentColor, prominent: true, horizontalPadding: 36, verticalPadding: 16))
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
                guard let path = source.dlnaControlPath else {
                    throw MediaServerError.missingControlURL
                }
                guard let url = URL(string: source.hostWithScheme + path) else {
                    throw MediaServerError.invalidURL
                }
                let client = DLNADiscoveryClient(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
                items = try await client.browse(controlURL: url, objectId: currentPath, sourceId: source.id)
            case .smb:
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

// MARK: - 添加 / 编辑媒体源（图标协议条 + 标准通用占位示例 + 高对比度表单，无白底白字）

struct AddMediaSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: PlayerSettingsStore

    private let editingId: UUID?
    let onSave: (MediaSourceConfig) -> Void

    @State private var name: String
    @State private var protocolType: MediaProtocolType
    @State private var host: String
    @State private var portText: String
    @State private var useHTTPS: Bool
    @State private var basePath: String
    @State private var shareName: String
    @State private var username: String
    @State private var password: String
    @State private var apiToken: String
    @State private var userId: String
    @State private var limitSingleConnection: Bool
    @State private var holdSourceConnection: Bool

    @State private var isTesting = false
    @State private var testSucceeded = false
    @State private var testMessage: String?

    @State private var isAuthenticating = false
    @State private var authFeedback: String?
    @State private var discoveredUsers: [EmbyUserSummary] = []

    @State private var showQRConfigSheet = false
    @State private var showLANDiscoverySheet = false

    init(
        editing: MediaSourceConfig? = nil,
        initialProtocol: MediaProtocolType = .smb,
        discoveredService: DiscoveredLANService? = nil,
        onSave: @escaping (MediaSourceConfig) -> Void
    ) {
        self.editingId = editing?.id
        self.onSave = onSave

        if let editing {
            _name = State(initialValue: editing.name)
            _protocolType = State(initialValue: editing.protocolType)
            _host = State(initialValue: editing.host)
            _portText = State(initialValue: String(editing.port))
            _useHTTPS = State(initialValue: editing.useHTTPS)
            _basePath = State(initialValue: editing.basePath)
            _shareName = State(initialValue: editing.shareName)
            _username = State(initialValue: editing.username)
            _password = State(initialValue: editing.password)
            _apiToken = State(initialValue: editing.apiToken)
            _userId = State(initialValue: editing.userId)
            _limitSingleConnection = State(initialValue: editing.limitSingleConnection)
            _holdSourceConnection = State(initialValue: editing.holdSourceConnection)
        } else if let service = discoveredService {
            _name = State(initialValue: service.name)
            _protocolType = State(initialValue: service.protocolType)
            _host = State(initialValue: service.host)
            _portText = State(initialValue: String(service.port))
            _useHTTPS = State(initialValue: service.useHTTPS)
            _basePath = State(initialValue: service.dlnaControlPath ?? "/")
            _shareName = State(initialValue: "")
            _username = State(initialValue: "")
            _password = State(initialValue: "")
            _apiToken = State(initialValue: "")
            _userId = State(initialValue: "")
            _limitSingleConnection = State(initialValue: false)
            _holdSourceConnection = State(initialValue: false)
        } else {
            // 新建时全部使用空白字段 + 标准通用占位提示，不预填个人隐私信息
            _name = State(initialValue: "")
            _protocolType = State(initialValue: initialProtocol)
            _host = State(initialValue: "")
            _portText = State(initialValue: String(initialProtocol.defaultPort))
            _useHTTPS = State(initialValue: false)
            _basePath = State(initialValue: initialProtocol == .dlna ? "/ctl/ContentDir" : "/")
            _shareName = State(initialValue: "")
            _username = State(initialValue: "")
            _password = State(initialValue: "")
            _apiToken = State(initialValue: "")
            _userId = State(initialValue: "")
            _limitSingleConnection = State(initialValue: false)
            _holdSourceConnection = State(initialValue: false)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AetherAmbientBackdrop(accent: protocolType.accentColor)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 34) {
                        // 顶部标题与快捷工具按钮
                        HStack(alignment: .center, spacing: 20) {
                            AetherIconMedallion(
                                systemName: protocolType.cardSymbolName,
                                colors: protocolType.gradientColors,
                                size: 68
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(editingId == nil ? "添加 \(protocolType.displayName)" : "编辑 \(protocolType.displayName)")
                                    .font(.system(size: 38, weight: .bold))
                                    .foregroundStyle(Color.white)
                                Text(protocolType.shortTagline)
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.white.opacity(0.65))
                            }
                            Spacer()
                            Button {
                                AppleTVSoundEffects.playSelect()
                                showQRConfigSheet = true
                            } label: {
                                Label("手机扫码填写", systemImage: "qrcode.viewfinder")
                                    .font(.system(size: 20, weight: .semibold))
                            }
                            .buttonStyle(AetherPillButtonStyle(accent: .cyan))

                            Button {
                                AppleTVSoundEffects.playSelect()
                                showLANDiscoverySheet = true
                            } label: {
                                Label("扫描局域网", systemImage: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 20, weight: .semibold))
                            }
                            .buttonStyle(AetherPillButtonStyle(accent: .purple))
                        }

                        // 协议图标切换栏（SMB 排第一，全部可视化图标按钮，不再藏进文字 Picker）
                        VStack(alignment: .leading, spacing: 14) {
                            Text("协议类型")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.80))

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(MediaProtocolType.allCases) { type in
                                        Button {
                                            AppleTVSoundEffects.playSelect()
                                            switchProtocol(to: type)
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: type.cardSymbolName)
                                                    .font(.system(size: 20, weight: .bold))
                                                Text(type.displayName)
                                                    .font(.system(size: 21, weight: .semibold))
                                            }
                                        }
                                        .buttonStyle(AetherPillButtonStyle(
                                            accent: type.accentColor,
                                            isSelected: protocolType == type,
                                            cornerRadius: 16,
                                            horizontalPadding: 22,
                                            verticalPadding: 13
                                        ))
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                            }
                        }

                        // 基本连接信息卡片
                        glassGroupBox(title: "连接地址", icon: "network") {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)], spacing: 20) {
                                inputField(title: "显示名称（可留空）", placeholder: "例如：家庭 NAS", text: $name)
                                inputField(title: "服务器 IP 或主机名", placeholder: "例如：192.168.1.100 或 nas.local", text: $host)
                                inputField(title: "端口（0 表示默认端口）", placeholder: String(protocolType.defaultPort), text: $portText)

                                if protocolType == .smb {
                                    inputField(title: "SMB 共享文件夹名（Share Name）", placeholder: "例如：media 或 share", text: $shareName)
                                } else if protocolType == .dlna {
                                    inputField(title: "DLNA ContentDirectory Control 路径", placeholder: "例如：/ctl/ContentDir", text: $basePath)
                                } else {
                                    inputField(title: "基础路径（可留空）", placeholder: "例如：/dav 或 /", text: $basePath)
                                }
                            }

                            if protocolType != .smb && protocolType != .dlna {
                                AetherToggleCard(
                                    icon: "lock.fill",
                                    colors: protocolType.gradientColors,
                                    title: "启用 HTTPS 加密连接",
                                    subtitle: "若服务器使用自签名证书，请在「设置 → 局域网与缓冲」保持信任开启",
                                    isOn: $useHTTPS
                                )
                            }
                        }

                        // 身份认证卡片
                        if protocolType != .dlna {
                            glassGroupBox(title: "身份认证（密码与 Token 经 Keychain 加密保存）", icon: "key.fill") {
                                if protocolType == .emby || protocolType == .jellyfin {
                                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)], spacing: 20) {
                                        inputField(title: "API Key / AccessToken", placeholder: "粘贴 Token 或下方用账号登录获取", text: $apiToken)
                                        inputField(title: "用户 ID（可留空或点击下方选择）", placeholder: "留空将自动识别当前用户", text: $userId)
                                        inputField(title: "用户名（用于登录换取 Token，可选）", placeholder: "例如：admin", text: $username)
                                        secureInputField(title: "密码（用于登录换取 Token，可选）", placeholder: "输入密码", text: $password)
                                    }

                                    HStack(spacing: 18) {
                                        Button {
                                            AppleTVSoundEffects.playSelect()
                                            Task { await authenticateEmbyAccount() }
                                        } label: {
                                            HStack(spacing: 10) {
                                                if isAuthenticating { ProgressView() }
                                                Label(isAuthenticating ? "正在登录…" : "账号登录获取 Token", systemImage: "person.badge.key.fill")
                                                    .font(.system(size: 20, weight: .semibold))
                                            }
                                        }
                                        .buttonStyle(AetherPillButtonStyle(accent: protocolType.accentColor))
                                        .disabled(isAuthenticating || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                        Button {
                                            AppleTVSoundEffects.playSelect()
                                            Task { await loadEmbyUsers() }
                                        } label: {
                                            Label("获取服务器用户列表", systemImage: "person.2.fill")
                                                .font(.system(size: 20, weight: .semibold))
                                        }
                                        .buttonStyle(AetherPillButtonStyle(accent: .cyan))
                                        .disabled(isAuthenticating || apiToken.isEmpty)
                                    }

                                    if !discoveredUsers.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 14) {
                                                ForEach(discoveredUsers) { user in
                                                    Button {
                                                        AppleTVSoundEffects.playSelect()
                                                        userId = user.id
                                                        authFeedback = "已选择用户：\(user.name)"
                                                    } label: {
                                                        HStack(spacing: 8) {
                                                            if userId == user.id {
                                                                Image(systemName: "checkmark.circle.fill")
                                                                    .foregroundStyle(Color.green)
                                                            }
                                                            Text(user.isAdmin ? "\(user.name) (管理员)" : user.name)
                                                                .font(.system(size: 20, weight: .semibold))
                                                        }
                                                    }
                                                    .buttonStyle(AetherPillButtonStyle(accent: protocolType.accentColor, isSelected: userId == user.id))
                                                }
                                            }
                                            .padding(.vertical, 6)
                                        }
                                    }

                                    if let authFeedback {
                                        Text(authFeedback)
                                            .font(.system(size: 19, weight: .medium))
                                            .foregroundStyle(Color.cyan)
                                    }
                                } else if protocolType == .plex {
                                    inputField(title: "X-Plex-Token", placeholder: "输入 Plex 访问令牌", text: $apiToken)
                                } else {
                                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)], spacing: 20) {
                                        inputField(title: "用户名（访客访问可留空）", placeholder: "例如：admin", text: $username)
                                        secureInputField(title: "密码（访客访问可留空）", placeholder: "输入密码", text: $password)
                                    }
                                }
                            }
                        }

                        // 局域网/网盘避坑选项
                        if protocolType == .webdav || protocolType == .directURL {
                            glassGroupBox(title: "网盘反代与高码率避坑", icon: "shield.lefthalf.filled") {
                                AetherToggleCard(
                                    icon: "1.circle.fill",
                                    colors: [Color(red: 0.90, green: 0.50, blue: 0.12), Color(red: 0.98, green: 0.74, blue: 0.22)],
                                    title: "单连接限流模式（Alist / OpenList / 网盘反代）",
                                    subtitle: "限制并发请求数为 1，避免触发 403/429 风控限流",
                                    isOn: $limitSingleConnection
                                )
                                AetherToggleCard(
                                    icon: "bolt.horizontal.fill",
                                    colors: [Color(red: 0.12, green: 0.62, blue: 0.90), Color(red: 0.22, green: 0.84, blue: 0.96)],
                                    title: "保持长连接拉流",
                                    subtitle: "避免频繁 Range 断连导致的卡顿与二次限速",
                                    isOn: $holdSourceConnection
                                )
                            }
                        }

                        // 测试反馈与操作栏
                        if let testMessage {
                            HStack(spacing: 14) {
                                Image(systemName: testSucceeded ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(testSucceeded ? Color.green : Color.orange)
                                Text(testMessage)
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundStyle(testSucceeded ? Color.green : Color.orange)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background((testSucceeded ? Color.green : Color.orange).opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }

                        HStack(spacing: 22) {
                            Button {
                                AppleTVSoundEffects.playSelect()
                                onSave(draftConfig)
                                dismiss()
                            } label: {
                                Label(editingId == nil ? "保存媒体源" : "保存修改", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 24, weight: .bold))
                            }
                            .buttonStyle(AetherPillButtonStyle(
                                accent: protocolType.accentColor,
                                prominent: true,
                                cornerRadius: 18,
                                horizontalPadding: 38,
                                verticalPadding: 17
                            ))
                            .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button {
                                AppleTVSoundEffects.playSelect()
                                Task { await testConnection() }
                            } label: {
                                HStack(spacing: 10) {
                                    if isTesting { ProgressView() }
                                    Label(isTesting ? "正在测试…" : "测试连接（读取根目录）", systemImage: "bolt.fill")
                                        .font(.system(size: 22, weight: .semibold))
                                }
                            }
                            .buttonStyle(AetherPillButtonStyle(accent: .cyan, cornerRadius: 18, horizontalPadding: 28, verticalPadding: 17))
                            .disabled(isTesting || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Spacer()

                            Button {
                                AppleTVSoundEffects.playBack()
                                dismiss()
                            } label: {
                                Label("取消", systemImage: "xmark")
                                    .font(.system(size: 22, weight: .semibold))
                            }
                            .buttonStyle(AetherPillButtonStyle(accent: .white, cornerRadius: 18, horizontalPadding: 26, verticalPadding: 17))
                        }
                        .padding(.bottom, 40)
                    }
                    .padding(.horizontal, 64)
                    .padding(.vertical, 36)
                }
            }
            .sheet(isPresented: $showQRConfigSheet) {
                QuickConfigQRView { imported in
                    applyConfig(imported)
                    testMessage = "已通过手机扫码填入配置，请检查或测试后保存"
                    testSucceeded = true
                }
            }
            .sheet(isPresented: $showLANDiscoverySheet) {
                LANDiscoverySheetView { service in
                    applyDiscoveredService(service)
                    testMessage = "已填入发现的设备「\(service.name)」，请补充认证信息或测试连接"
                    testSucceeded = true
                }
            }
        }
    }

    private func switchProtocol(to newType: MediaProtocolType) {
        protocolType = newType
        portText = String(newType.defaultPort)
        if newType == .dlna && (basePath.isEmpty || basePath == "/") {
            basePath = "/ctl/ContentDir"
        } else if newType != .dlna && basePath == "/ctl/ContentDir" {
            basePath = "/"
        }
        testMessage = nil
        authFeedback = nil
        discoveredUsers = []
    }

    private func glassGroupBox<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(protocolType.accentColor)
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            content()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.08, green: 0.10, blue: 0.17).opacity(0.84), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1.1)
        )
    }

    private func inputField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.76))
            TextField(placeholder, text: text)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func secureInputField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.76))
            SecureField(placeholder, text: text)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var draftConfig: MediaSourceConfig {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return MediaSourceConfig(
            id: editingId ?? UUID(),
            name: trimmedName.isEmpty ? (trimmedHost.isEmpty ? protocolType.displayName : trimmedHost) : trimmedName,
            protocolType: protocolType,
            host: trimmedHost,
            port: Int(portText) ?? protocolType.defaultPort,
            useHTTPS: useHTTPS,
            basePath: basePath,
            username: username,
            password: password,
            apiToken: apiToken,
            userId: userId,
            shareName: shareName,
            limitSingleConnection: limitSingleConnection,
            holdSourceConnection: holdSourceConnection
        )
    }

    private func applyConfig(_ imported: MediaSourceConfig) {
        name = imported.name
        protocolType = imported.protocolType
        host = imported.host
        portText = String(imported.port)
        useHTTPS = imported.useHTTPS
        basePath = imported.basePath
        shareName = imported.shareName
        username = imported.username
        password = imported.password
        apiToken = imported.apiToken
        userId = imported.userId
        limitSingleConnection = imported.limitSingleConnection
        holdSourceConnection = imported.holdSourceConnection
    }

    private func applyDiscoveredService(_ service: DiscoveredLANService) {
        name = service.name
        protocolType = service.protocolType
        host = service.host
        portText = String(service.port)
        useHTTPS = service.useHTTPS
        if let path = service.dlnaControlPath {
            basePath = path
        }
    }

    private func authenticateEmbyAccount() async {
        isAuthenticating = true
        authFeedback = nil
        defer { isAuthenticating = false }
        do {
            let result = try await MediaServerClients(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
                .authenticateEmby(source: draftConfig, username: username, password: password)
            apiToken = result.accessToken
            userId = result.userId
            authFeedback = "登录成功，已获取「\(result.userName)」的 AccessToken 与用户 ID"
        } catch {
            authFeedback = error.localizedDescription
        }
    }

    private func loadEmbyUsers() async {
        isAuthenticating = true
        authFeedback = nil
        defer { isAuthenticating = false }
        do {
            let users = try await MediaServerClients(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
                .fetchEmbyUsers(source: draftConfig)
            discoveredUsers = users
            authFeedback = users.isEmpty ? "服务器未返回用户" : "共获取 \(users.count) 个用户，请在上方点击选择"
        } catch {
            authFeedback = error.localizedDescription
        }
    }

    private func testConnection() async {
        let config = draftConfig
        isTesting = true
        testMessage = nil
        defer { isTesting = false }

        do {
            if config.protocolType == .directURL {
                guard URL(string: config.baseURLString) != nil else { throw MediaServerError.invalidURL }
                testSucceeded = true
                testMessage = "直链格式有效，保存后可直接播放"
                return
            }
            let count: Int
            switch config.protocolType {
            case .webdav:
                count = try await WebDAVClient(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
                    .listDirectory(source: config, path: "/").count
            case .emby, .jellyfin, .plex:
                count = try await MediaServerClients(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
                    .browse(source: config, parentId: nil).count
            case .dlna:
                guard let path = config.dlnaControlPath else { throw MediaServerError.missingControlURL }
                guard let url = URL(string: config.hostWithScheme + path) else { throw MediaServerError.invalidURL }
                count = try await DLNADiscoveryClient(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
                    .browse(controlURL: url, objectId: "0", sourceId: config.id).count
            case .smb:
                count = try await SMBSourceClient().listDirectory(source: config, path: "/").count
            case .directURL:
                count = 0
            }
            testSucceeded = true
            testMessage = "连接成功，根目录共读取到 \(count) 项内容"
        } catch {
            testSucceeded = false
            testMessage = error.localizedDescription
        }
    }
}

// MARK: - 手机扫码配置浮层

struct QuickConfigQRView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var server = QuickConfigWebServer()
    let onReceived: (MediaSourceConfig) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AetherAmbientBackdrop(accent: Color(red: 0.14, green: 0.84, blue: 0.86))

                VStack(spacing: 30) {
                    if let qrImage = server.qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 310, height: 310)
                            .padding(20)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: Color.cyan.opacity(0.35), radius: 28, x: 0, y: 12)
                    } else {
                        ProgressView()
                            .scaleEffect(1.5)
                            .frame(width: 310, height: 310)
                    }

                    Text(server.statusMessage)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 820)

                    if let url = server.accessURLString {
                        Text(url)
                            .font(.system(size: 22, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(red: 0.44, green: 0.92, blue: 1.0))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.10), in: Capsule())
                    }

                    Button {
                        AppleTVSoundEffects.playBack()
                        dismiss()
                    } label: {
                        Label("关闭", systemImage: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                    }
                    .buttonStyle(AetherPillButtonStyle(accent: .cyan, horizontalPadding: 34, verticalPadding: 15))
                }
                .padding(48)
            }
            .onAppear {
                AppleTVSoundEffects.playPanelOpen()
                server.start()
            }
            .onDisappear {
                server.stop()
            }
            .onChange(of: server.receivedConfig) { _, config in
                if let config {
                    AppleTVSoundEffects.playSelect()
                    onReceived(config)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - 局域网自动发现浮层（Bonjour + SSDP，高对比度图标卡）

struct LANDiscoverySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: PlayerSettingsStore
    @StateObject private var browser = LANServiceBrowser()
    let onSelect: (DiscoveredLANService) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AetherAmbientBackdrop(accent: Color(red: 0.50, green: 0.36, blue: 1.0))

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        HStack(spacing: 20) {
                            AetherIconMedallion(
                                systemName: "dot.radiowaves.left.and.right",
                                colors: [Color(red: 0.48, green: 0.28, blue: 0.96), Color(red: 0.24, green: 0.72, blue: 1.0)],
                                size: 64
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text("发现局域网设备")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundStyle(Color.white)
                                Text(browser.isScanning ? "正在扫描 Bonjour（SMB / WebDAV / Emby / Plex）与 DLNA 设备…" : "点击任意设备即可自动填入地址与端口")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.white.opacity(0.68))
                            }
                            Spacer()
                            Button {
                                AppleTVSoundEffects.playSelect()
                                browser.start(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
                            } label: {
                                Label("重新扫描", systemImage: "arrow.clockwise")
                                    .font(.system(size: 20, weight: .semibold))
                            }
                            .buttonStyle(AetherPillButtonStyle(accent: .purple))

                            Button {
                                AppleTVSoundEffects.playBack()
                                dismiss()
                            } label: {
                                Label("关闭", systemImage: "xmark")
                                    .font(.system(size: 20, weight: .semibold))
                            }
                            .buttonStyle(AetherPillButtonStyle(accent: .white))
                        }

                        if browser.dlnaMulticastBlocked {
                            HStack(spacing: 14) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.orange)
                                Text("当前自签名证书未授予多播受限权限，DLNA SSDP 自动发现已被系统拦截；SMB / WebDAV / Emby / Jellyfin / Plex 的 Bonjour 扫描不受影响，DLNA 可手动填入 Control 路径。")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.white.opacity(0.86))
                            }
                            .padding(20)
                            .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }

                        if browser.isScanning && browser.discoveredServices.isEmpty {
                            HStack(spacing: 16) {
                                ProgressView()
                                Text("正在等待局域网设备响应…")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.white.opacity(0.74))
                            }
                            .padding(.vertical, 40)
                        } else if browser.discoveredServices.isEmpty {
                            Text("暂未发现支持广播的局域网媒体服务，可点击右上角重新扫描，或返回使用手机扫码 / 手动添加。")
                                .font(.system(size: 22))
                                .foregroundStyle(Color.white.opacity(0.68))
                                .padding(.vertical, 32)
                        } else {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 460, maximum: 600), spacing: 24)],
                                spacing: 24
                            ) {
                                ForEach(browser.discoveredServices) { service in
                                    Button {
                                        AppleTVSoundEffects.playSelect()
                                        onSelect(service)
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 20) {
                                            AetherIconMedallion(
                                                systemName: service.protocolType.cardSymbolName,
                                                colors: service.protocolType.gradientColors,
                                                size: 62
                                            )
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(service.name)
                                                    .font(.system(size: 24, weight: .bold))
                                                    .foregroundStyle(Color.white)
                                                    .lineLimit(1)
                                                Text("\(service.protocolType.displayName) · \(service.host):\(service.port)\(service.dlnaControlPath ?? "")")
                                                    .font(.system(size: 17))
                                                    .foregroundStyle(Color.white.opacity(0.65))
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Text("填入")
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundStyle(service.protocolType.accentColor)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(service.protocolType.accentColor.opacity(0.20), in: Capsule())
                                        }
                                        .padding(22)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(AetherSpotlightCardStyle(accent: service.protocolType.accentColor, cornerRadius: 22))
                                }
                            }
                        }
                    }
                    .padding(60)
                }
            }
            .onAppear {
                AppleTVSoundEffects.playPanelOpen()
                browser.start(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
            }
            .onDisappear {
                browser.stop()
            }
        }
    }
}
