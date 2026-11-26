import SwiftUI

struct SourceBrowserView: View {
    @EnvironmentObject private var sourceStore: MediaSourceStore
    @State private var showAddSourceSheet = false
    @State private var editingSource: MediaSourceConfig?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        AppleTVSoundEffects.playSelect()
                        showAddSourceSheet = true
                    } label: {
                        Label("添加局域网媒体源（支持手机扫码 / 自动发现）", systemImage: "plus.circle.fill")
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
            .navigationTitle("媒体源")
            .sheet(isPresented: $showAddSourceSheet) {
                AddMediaSourceView { newSource in
                    sourceStore.add(newSource)
                }
            }
            .sheet(item: $editingSource) { source in
                AddMediaSourceView(editing: source) { updated in
                    sourceStore.update(updated)
                }
            }
        }
    }
}

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
                                SourceDirectoryView(source: source, currentPath: item.remotePath, displayTitle: item.title)
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
                                                    .foregroundStyle(Color.cyan)
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
                guard let path = source.dlnaControlPath else {
                    throw MediaServerError.missingControlURL
                }
                guard let url = URL(string: source.hostWithScheme + path) else {
                    throw MediaServerError.invalidURL
                }
                let client = DLNADiscoveryClient(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
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

    init(editing: MediaSourceConfig? = nil, onSave: @escaping (MediaSourceConfig) -> Void) {
        self.editingId = editing?.id
        self.onSave = onSave
        _name = State(initialValue: editing?.name ?? "客厅 NAS")
        _protocolType = State(initialValue: editing?.protocolType ?? .webdav)
        _host = State(initialValue: editing?.host ?? "192.168.1.10")
        _portText = State(initialValue: editing.map { String($0.port) } ?? "5005")
        _useHTTPS = State(initialValue: editing?.useHTTPS ?? false)
        _basePath = State(initialValue: editing?.basePath ?? "/")
        _shareName = State(initialValue: editing?.shareName ?? "video")
        _username = State(initialValue: editing?.username ?? "")
        _password = State(initialValue: editing?.password ?? "")
        _apiToken = State(initialValue: editing?.apiToken ?? "")
        _userId = State(initialValue: editing?.userId ?? "")
        _limitSingleConnection = State(initialValue: editing?.limitSingleConnection ?? false)
        _holdSourceConnection = State(initialValue: editing?.holdSourceConnection ?? false)
    }

    private var usesControlPath: Bool {
        protocolType == .dlna
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("快捷配置（免遥控器打字）") {
                    Button {
                        AppleTVSoundEffects.playSelect()
                        showQRConfigSheet = true
                    } label: {
                        Label("手机扫码 / 网页填写配置", systemImage: "qrcode.viewfinder")
                    }

                    Button {
                        AppleTVSoundEffects.playSelect()
                        showLANDiscoverySheet = true
                    } label: {
                        Label("扫描局域网设备（Bonjour / DLNA）", systemImage: "dot.radiowaves.left.and.right")
                    }
                }

                Section("基本连接") {
                    TextField("名称", text: $name)
                    Picker("协议类型", selection: $protocolType) {
                        ForEach(MediaProtocolType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .onChange(of: protocolType) { _, newType in
                        portText = String(newType.defaultPort)
                        if newType == .dlna && (basePath.isEmpty || basePath == "/") {
                            basePath = "/MediaServer/ContentDirectory/Control"
                        }
                        testMessage = nil
                        authFeedback = nil
                        discoveredUsers = []
                    }
                    TextField("服务器 IP 或主机名", text: $host)
                    TextField("端口（0 表示用默认端口）", text: $portText)
                    if usesControlPath {
                        TextField("DLNA Control 路径（如 /MediaServer/ContentDirectory/Control）", text: $basePath)
                        Text("可用上方「扫描局域网设备」自动探测支持多播的 DLNA 设备；若自签环境受限，请填写 ContentDirectory 的 Control 路径（如 MiniDLNA 为 /ctl/ContentDir）。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if protocolType == .smb {
                        TextField("SMB 共享名（如 video / media）", text: $shareName)
                    } else {
                        Toggle("启用 HTTPS", isOn: $useHTTPS)
                        TextField("基础路径（如 /dav 或留空）", text: $basePath)
                    }
                }

                Section("身份认证") {
                    if protocolType == .emby || protocolType == .jellyfin {
                        TextField("API Key / AccessToken（可用下方账号登录自动获取）", text: $apiToken)
                        TextField("用户名（用于账号登录，可留空）", text: $username)
                        SecureField("密码（用于账号登录，可留空）", text: $password)
                        Button {
                            Task { await authenticateEmbyAccount() }
                        } label: {
                            HStack(spacing: 12) {
                                if isAuthenticating { ProgressView() }
                                Text(isAuthenticating ? "正在登录…" : "用账号密码登录并获取 Token / 用户 ID")
                            }
                        }
                        .disabled(isAuthenticating || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        TextField("用户 ID（可留空，或从下方列表选择）", text: $userId)
                        Button("获取服务器用户列表") {
                            Task { await loadEmbyUsers() }
                        }
                        .disabled(isAuthenticating || apiToken.isEmpty)

                        if !discoveredUsers.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(discoveredUsers) { user in
                                        Button {
                                            AppleTVSoundEffects.playSelect()
                                            userId = user.id
                                            authFeedback = "已选择用户：\(user.name)"
                                        } label: {
                                            HStack(spacing: 6) {
                                                if userId == user.id {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(Color.green)
                                                }
                                                Text(user.isAdmin ? "\(user.name) (管理员)" : user.name)
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }

                        if let authFeedback {
                            Text(authFeedback)
                                .font(.footnote)
                                .foregroundStyle(Color.cyan)
                        }
                    } else if protocolType == .plex {
                        TextField("X-Plex-Token", text: $apiToken)
                    } else if protocolType != .dlna {
                        TextField("用户名（访客可留空）", text: $username)
                        SecureField("密码", text: $password)
                    }
                }

                Section("局域网/网盘避坑选项") {
                    Toggle("单连接限流模式（适合 Alist/网盘反代）", isOn: $limitSingleConnection)
                    Toggle("保持长连接拉流（避免频繁 Range 断连）", isOn: $holdSourceConnection)
                }

                Section("连接测试") {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack(spacing: 12) {
                            if isTesting { ProgressView() }
                            Text(isTesting ? "正在测试…" : "测试连接（读取根目录）")
                        }
                    }
                    .disabled(isTesting || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let testMessage {
                        Label(testMessage, systemImage: testSucceeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .font(.footnote)
                            .foregroundStyle(testSucceeded ? Color.green : Color.orange)
                    }
                }

                Section {
                    Button(editingId == nil ? "保存媒体源" : "保存修改") {
                        onSave(draftConfig)
                        dismiss()
                    }
                    .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle(editingId == nil ? "添加媒体源" : "编辑媒体源")
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
                    testMessage = "已选择局域网设备「\(service.name)」，请补充认证信息或测试连接"
                    testSucceeded = true
                }
            }
        }
    }

    private var draftConfig: MediaSourceConfig {
        MediaSourceConfig(
            id: editingId ?? UUID(),
            name: name.isEmpty ? host : name,
            protocolType: protocolType,
            host: host,
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

    /// 保存前先真读一次根目录：填错地址/账号时不用等保存后才发现
    private func testConnection() async {
        let config = draftConfig
        isTesting = true
        testMessage = nil
        defer { isTesting = false }

        do {
            if config.protocolType == .directURL {
                guard URL(string: config.baseURLString) != nil else { throw MediaServerError.invalidURL }
                testSucceeded = true
                testMessage = "直链无需测试，保存后可直接播放"
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
            testMessage = "连接成功，根目录 \(count) 项"
        } catch {
            testSucceeded = false
            testMessage = error.localizedDescription
        }
    }
}

// MARK: - 手机扫码配置浮层

private struct QuickConfigQRView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var server = QuickConfigWebServer()
    let onReceived: (MediaSourceConfig) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                if let qrImage = server.qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 300, height: 300)
                        .padding(18)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    ProgressView()
                        .scaleEffect(1.4)
                        .frame(width: 300, height: 300)
                }

                Text(server.statusMessage)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 780)

                if let url = server.accessURLString {
                    Text(url)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(Color.cyan)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }

                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(48)
            .navigationTitle("手机扫码快速配置")
            .onAppear {
                server.start()
            }
            .onDisappear {
                server.stop()
            }
            .onChange(of: server.receivedConfig) { _, config in
                if let config {
                    onReceived(config)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - 局域网自动发现浮层（Bonjour + SSDP）

private struct LANDiscoverySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: PlayerSettingsStore
    @StateObject private var browser = LANServiceBrowser()
    let onSelect: (DiscoveredLANService) -> Void

    var body: some View {
        NavigationStack {
            List {
                if browser.isScanning {
                    HStack(spacing: 14) {
                        ProgressView()
                        Text("正在扫描局域网 Bonjour 与 DLNA 设备…")
                            .foregroundStyle(.secondary)
                    }
                }

                if browser.dlnaMulticastBlocked {
                    Label(
                        "当前自签名环境未授予系统多播权限，DLNA SSDP 自动发现已被系统拦截；SMB / WebDAV / Emby / Jellyfin / Plex 的 Bonjour 扫描不受影响，DLNA 可回退手动填写 Control 路径。",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
                }

                if browser.discoveredServices.isEmpty && !browser.isScanning {
                    Text("暂未发现支持广播的局域网媒体服务，可点击右上角重新扫描或手动填写。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(browser.discoveredServices) { service in
                        Button {
                            AppleTVSoundEffects.playSelect()
                            onSelect(service)
                            dismiss()
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: service.protocolType.iconName)
                                    .font(.title2)
                                    .frame(width: 40)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(service.name)
                                        .font(.headline)
                                    Text("\(service.protocolType.rawValue) · \(service.host):\(service.port)\(service.dlnaControlPath ?? "")")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("填入")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.cyan)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle("发现的局域网设备")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("重新扫描") {
                        browser.start(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                browser.start(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
            }
            .onDisappear {
                browser.stop()
            }
        }
    }
}
