import SwiftUI

/// 统一目录导航路由，挂在 RootTabView 外层的唯一 NavigationStack 上，彻底解决 tvOS 返回键误退桌面与 Tab 卡死问题
struct SourceDirectoryRoute: Hashable {
    let sourceId: UUID
    let currentPath: String
    let displayTitle: String?
    let fallbackSource: MediaSourceConfig
}

struct SourceBrowserView: View {
    var onOpenSource: (MediaSourceConfig) -> Void = { _ in }

    @EnvironmentObject private var sourceStore: MediaSourceStore
    @State private var addingProtocol: MediaProtocolType?
    @State private var editingSource: MediaSourceConfig?
    @State private var discoveredPrefill: DiscoveredLANService?
    @State private var showQRConfigSheet = false
    @State private var showLANDiscoverySheet = false

    var body: some View {
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
                                    Button {
                                        AppleTVSoundEffects.playSelect()
                                        onOpenSource(source)
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
                .padding(.horizontal, 72)
                .padding(.vertical, 40)
            }
        }
        .fullScreenCover(item: $addingProtocol) { proto in
            AddMediaSourceView(initialProtocol: proto) { newSource in
                sourceStore.add(newSource)
            }
        }
        .fullScreenCover(item: $editingSource) { source in
            AddMediaSourceView(editing: source) { updated in
                sourceStore.update(updated)
            }
        }
        .fullScreenCover(item: $discoveredPrefill) { service in
            AddMediaSourceView(discoveredService: service) { newSource in
                sourceStore.add(newSource)
            }
        }
        .fullScreenCover(isPresented: $showQRConfigSheet) {
            QuickConfigQRView { imported in
                sourceStore.add(imported)
            }
        }
        .fullScreenCover(isPresented: $showLANDiscoverySheet) {
            LANDiscoverySheetView { service in
                discoveredPrefill = service
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

// MARK: - 媒体源目录浏览（独立全屏导航层级，支持遥控器逐级返回、非破坏性重试与原地编辑）

struct SourceDirectoryView: View {
    let route: SourceDirectoryRoute
    var onOpenSubdirectory: (SourceDirectoryRoute) -> Void = { _ in }
    var onGoBack: () -> Void = {}
    var onPopToRoot: () -> Void = {}

    @EnvironmentObject private var sourceStore: MediaSourceStore
    @EnvironmentObject private var settings: PlayerSettingsStore
    @EnvironmentObject private var historyStore: WatchHistoryStore

    @State private var items: [MediaItem] = []
    @State private var isLoading = false
    @State private var hasLoadedSuccessfully = false
    @State private var errorMessage: String?
    @State private var retryCount = 0
    @State private var lastAttemptTimeText: String?
    @State private var loadRequestID = UUID()
    @State private var completedRequestID: UUID?
    @State private var playingItem: MediaItem?
    @State private var isEditingSource = false

    private enum DirectoryFocus: Hashable {
        case back
        case reload
        case edit
        case retry
        case cancelLoading
    }

    @FocusState private var focusedControl: DirectoryFocus?

    /// 始终读取 MediaSourceStore 中最新配置，编辑保存后立刻生效
    private var liveSource: MediaSourceConfig {
        sourceStore.sources.first(where: { $0.id == route.sourceId }) ?? route.fallbackSource
    }

    private var playableItems: [MediaItem] {
        items.filter { !$0.isDirectory }
    }

    private var isRootDirectory: Bool {
        route.currentPath == "/" || route.currentPath == "0" || route.currentPath.isEmpty
    }

    private var navigationTitle: String {
        if let displayTitle = route.displayTitle, !displayTitle.isEmpty { return displayTitle }
        if isRootDirectory { return liveSource.name }
        return (route.currentPath as NSString).lastPathComponent
    }

    private var breadcrumbText: String {
        if isRootDirectory {
            if liveSource.protocolType == .smb && !liveSource.shareName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(liveSource.baseURLString)/\(liveSource.shareName.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ ")))"
            }
            return liveSource.baseURLString
        }
        return "\(liveSource.name) · \(route.currentPath)"
    }

    var body: some View {
        ZStack {
            AetherAmbientBackdrop(accent: liveSource.protocolType.accentColor)

            VStack(spacing: 0) {
                topNavigationBar

                Divider()
                    .overlay(Color.white.opacity(0.12))
                    .padding(.horizontal, 60)

                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onExitCommand {
            guard !isEditingSource, playingItem == nil else { return }
            goBack()
        }
        .task(id: loadRequestID) {
            guard liveSource.protocolType != .directURL else { return }
            // 从子目录返回时若本级已加载成功且无主动刷新请求，保留当前目录避免无谓重载闪烁
            if hasLoadedSuccessfully && completedRequestID == loadRequestID {
                return
            }
            await loadDirectory(for: loadRequestID)
        }
        .fullScreenCover(item: $playingItem) { item in
            PlayerScreenView(
                item: item,
                playlist: playableItems.isEmpty ? [item] : playableItems,
                sourceConfig: liveSource
            )
        }
        .fullScreenCover(isPresented: $isEditingSource) {
            AddMediaSourceView(editing: liveSource) { updated in
                sourceStore.update(updated)
                triggerReload(resetError: true)
            }
        }
    }

    // MARK: - 顶部固定操作栏（永远可返回、可刷新、可编辑，杜绝任何页面卡死）

    private var topNavigationBar: some View {
        HStack(spacing: 22) {
            Button {
                goBack()
            } label: {
                Label("返回上一级", systemImage: "chevron.left")
                    .font(.system(size: 21, weight: .semibold))
            }
            .buttonStyle(AetherPillButtonStyle(
                accent: .white,
                cornerRadius: 16,
                horizontalPadding: 22,
                verticalPadding: 13
            ))
            .focused($focusedControl, equals: .back)

            AetherIconMedallion(
                systemName: liveSource.protocolType.cardSymbolName,
                colors: liveSource.protocolType.gradientColors,
                size: 54
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text(navigationTitle)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(liveSource.protocolType.rawValue)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(liveSource.protocolType.accentColor.opacity(0.32), in: Capsule())
                }
                Text(breadcrumbText)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            if liveSource.protocolType != .directURL {
                Button {
                    guard !isLoading else { return }
                    AppleTVSoundEffects.playSelect()
                    triggerReload(resetError: false)
                } label: {
                    HStack(spacing: 10) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.75)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 19, weight: .semibold))
                        }
                        Text(isLoading ? "读取中…" : "刷新")
                            .font(.system(size: 20, weight: .semibold))
                    }
                }
                .buttonStyle(AetherPillButtonStyle(
                    accent: liveSource.protocolType.accentColor,
                    cornerRadius: 16,
                    horizontalPadding: 22,
                    verticalPadding: 13
                ))
                .focused($focusedControl, equals: .reload)
            }

            Button {
                AppleTVSoundEffects.playSelect()
                isEditingSource = true
            } label: {
                Label("编辑媒体源", systemImage: "slider.horizontal.3")
                    .font(.system(size: 20, weight: .semibold))
            }
            .buttonStyle(AetherPillButtonStyle(
                accent: .cyan,
                cornerRadius: 16,
                horizontalPadding: 22,
                verticalPadding: 13
            ))
            .focused($focusedControl, equals: .edit)
        }
        .padding(.horizontal, 60)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .focusSection()
    }

    // MARK: - 内容主体（出错重载时不销毁按钮，焦点绝不丢失，快速失败也有清晰反馈）

    @ViewBuilder
    private var contentArea: some View {
        if liveSource.protocolType == .directURL {
            directURLPlayView
        } else if let errorMessage {
            errorStateView(message: errorMessage)
        } else if isLoading && items.isEmpty {
            initialLoadingView
        } else if items.isEmpty {
            emptyDirectoryView
        } else {
            directoryGridView
        }
    }

    private var initialLoadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.4)
            Text("正在连接 \(liveSource.name)…")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.86))
            Text(breadcrumbText)
                .font(.system(size: 19))
                .foregroundStyle(Color.white.opacity(0.56))
            Button {
                goBack()
            } label: {
                Label("取消并返回", systemImage: "chevron.left")
                    .font(.system(size: 21, weight: .semibold))
            }
            .buttonStyle(AetherPillButtonStyle(
                accent: .white,
                cornerRadius: 16,
                horizontalPadding: 28,
                verticalPadding: 14
            ))
            .focused($focusedControl, equals: .cancelLoading)
            .padding(.top, 8)
        }
        .padding(48)
        .onAppear {
            if focusedControl == nil {
                focusedControl = .cancelLoading
            }
        }
    }

    private func errorStateView(message: String) -> some View {
        VStack(spacing: 24) {
            AetherIconMedallion(
                systemName: "wifi.exclamationmark",
                colors: [Color(red: 0.90, green: 0.42, blue: 0.14), Color(red: 0.98, green: 0.68, blue: 0.22)],
                size: 82
            )

            Text("无法读取目录内容")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.white)

            Text(message)
                .font(.system(size: 22))
                .foregroundStyle(Color.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 960)

            if isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.85)
                    Text("正在重新连接 \(liveSource.baseURLString)…")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(red: 0.48, green: 0.90, blue: 1.0))
                }
                .padding(.top, 2)
            } else if let lastAttemptTimeText, retryCount > 0 {
                Text("上次重试：\(lastAttemptTimeText)（已重试 \(retryCount) 次）")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            HStack(spacing: 20) {
                // 不对聚焦中的按钮使用 .disabled(isLoading)，避免 tvOS 焦点引擎强行驱逐焦点
                Button {
                    guard !isLoading else { return }
                    AppleTVSoundEffects.playSelect()
                    triggerReload(resetError: false)
                } label: {
                    HStack(spacing: 10) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 20, weight: .bold))
                        }
                        Text(isLoading ? "正在重试…" : "重新加载")
                            .font(.system(size: 22, weight: .bold))
                    }
                }
                .buttonStyle(AetherPillButtonStyle(
                    accent: liveSource.protocolType.accentColor,
                    prominent: true,
                    cornerRadius: 18,
                    horizontalPadding: 32,
                    verticalPadding: 15
                ))
                .focused($focusedControl, equals: .retry)

                Button {
                    AppleTVSoundEffects.playSelect()
                    isEditingSource = true
                } label: {
                    Label("编辑媒体源", systemImage: "slider.horizontal.3")
                        .font(.system(size: 22, weight: .semibold))
                }
                .buttonStyle(AetherPillButtonStyle(
                    accent: .cyan,
                    cornerRadius: 18,
                    horizontalPadding: 28,
                    verticalPadding: 15
                ))

                Button {
                    goBack()
                } label: {
                    Label("返回上一级", systemImage: "chevron.left")
                        .font(.system(size: 22, weight: .semibold))
                }
                .buttonStyle(AetherPillButtonStyle(
                    accent: .white,
                    cornerRadius: 18,
                    horizontalPadding: 28,
                    verticalPadding: 15
                ))
            }
            .padding(.top, 8)
            .focusSection()
        }
        .padding(48)
        .background(Color(red: 0.08, green: 0.10, blue: 0.17).opacity(0.82), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1.2)
        )
        .padding(.horizontal, 60)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focusedControl = .retry
            }
        }
    }

    private var emptyDirectoryView: some View {
        let isSMBRootWithoutShare = liveSource.protocolType == .smb
            && liveSource.shareName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isRootDirectory

        return VStack(spacing: 22) {
            AetherIconMedallion(
                systemName: "folder",
                colors: [Color(white: 0.26), Color(white: 0.16)],
                size: 80
            )
            Text(isSMBRootWithoutShare
                 ? "已连接服务器，但未发现可见的 SMB 共享文件夹"
                 : "此目录下没有可播放的视频文件")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.88))
            if isSMBRootWithoutShare {
                Text("部分 NAS 会隐藏共享列表，可点击下方「编辑媒体源」手动填入共享文件夹名（如 media / video）")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 820)
            }
            HStack(spacing: 20) {
                Button {
                    guard !isLoading else { return }
                    AppleTVSoundEffects.playSelect()
                    triggerReload(resetError: false)
                } label: {
                    HStack(spacing: 10) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 19, weight: .bold))
                        }
                        Text(isLoading ? "正在重试…" : "重新加载")
                            .font(.system(size: 21, weight: .semibold))
                    }
                }
                .buttonStyle(AetherPillButtonStyle(accent: liveSource.protocolType.accentColor, prominent: true))
                .focused($focusedControl, equals: .retry)

                Button {
                    AppleTVSoundEffects.playSelect()
                    isEditingSource = true
                } label: {
                    Label("编辑媒体源", systemImage: "slider.horizontal.3")
                        .font(.system(size: 21, weight: .semibold))
                }
                .buttonStyle(AetherPillButtonStyle(accent: .cyan))

                Button {
                    goBack()
                } label: {
                    Label("返回上一级", systemImage: "chevron.left")
                        .font(.system(size: 21, weight: .semibold))
                }
                .buttonStyle(AetherPillButtonStyle(accent: .white))
            }
            .padding(.top, 6)
            .focusSection()
        }
        .padding(48)
    }

    private var directoryGridView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 460, maximum: 580), spacing: 26)],
                spacing: 24
            ) {
                ForEach(items) { item in
                    if item.isDirectory {
                        Button {
                            AppleTVSoundEffects.playSelect()
                            onOpenSubdirectory(SourceDirectoryRoute(
                                sourceId: liveSource.id,
                                currentPath: item.remotePath,
                                displayTitle: item.title,
                                fallbackSource: liveSource
                            ))
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
                        .buttonStyle(AetherSpotlightCardStyle(accent: liveSource.protocolType.accentColor, cornerRadius: 20))
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
                                            colors: liveSource.protocolType.gradientColors,
                                            size: 60
                                        )
                                    }
                                    .frame(width: 96, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                } else {
                                    AetherIconMedallion(
                                        systemName: "play.fill",
                                        colors: liveSource.protocolType.gradientColors,
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
                        .buttonStyle(AetherSpotlightCardStyle(accent: liveSource.protocolType.accentColor, cornerRadius: 20))
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
        .focusSection()
    }

    private var directURLPlayView: some View {
        VStack(spacing: 28) {
            AetherIconMedallion(
                systemName: MediaProtocolType.directURL.cardSymbolName,
                colors: MediaProtocolType.directURL.gradientColors,
                size: 88
            )
            Text(liveSource.baseURLString)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.85))
            Button {
                AppleTVSoundEffects.playSelect()
                if let url = URL(string: liveSource.baseURLString) {
                    playingItem = MediaItem(
                        id: "direct:\(liveSource.id.uuidString)",
                        title: liveSource.name,
                        isDirectory: false,
                        streamURL: url,
                        sourceId: liveSource.id,
                        protocolType: .directURL,
                        remotePath: "/",
                        httpHeaders: NetworkPitfallGuards.standardHTTPHeaders(for: liveSource)
                    )
                }
            } label: {
                Label("立即播放直链", systemImage: "play.fill")
                    .font(.system(size: 24, weight: .bold))
            }
            .buttonStyle(AetherPillButtonStyle(accent: MediaProtocolType.directURL.accentColor, prominent: true, horizontalPadding: 36, verticalPadding: 16))
        }
    }

    private func goBack() {
        AppleTVSoundEffects.playBack()
        onGoBack()
    }

    private func triggerReload(resetError: Bool) {
        retryCount += 1
        if resetError {
            errorMessage = nil
        }
        loadRequestID = UUID()
    }

    private func loadDirectory(for requestID: UUID) async {
        let source = liveSource
        let startedAt = Date()
        let isManualRetry = retryCount > 0
        isLoading = true
        defer {
            if loadRequestID == requestID {
                isLoading = false
            }
        }

        do {
            let fetched: [MediaItem]
            switch source.protocolType {
            case .webdav:
                let client = WebDAVClient(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
                fetched = try await client.listDirectory(source: source, path: route.currentPath)
            case .emby, .jellyfin, .plex:
                let client = MediaServerClients(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
                let parent = (route.currentPath == "/" || route.currentPath.isEmpty) ? nil : route.currentPath
                fetched = try await client.browse(source: source, parentId: parent)
            case .dlna:
                guard let path = source.dlnaControlPath else {
                    throw MediaServerError.missingControlURL
                }
                guard let url = URL(string: source.hostWithScheme + path) else {
                    throw MediaServerError.invalidURL
                }
                let client = DLNADiscoveryClient(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
                fetched = try await client.browse(controlURL: url, objectId: route.currentPath, sourceId: source.id)
            case .smb:
                let client = SMBSourceClient()
                fetched = try await client.listDirectory(source: source, path: route.currentPath)
            case .directURL:
                fetched = []
            }

            guard !Task.isCancelled, loadRequestID == requestID else { return }
            items = fetched
            errorMessage = nil
            hasLoadedSuccessfully = true
            completedRequestID = requestID
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, loadRequestID == requestID else { return }
            // 若手动点击“重新加载”后服务器瞬间拒连（<350ms），保留短促加载态反馈，让用户明确感知重试已执行
            if isManualRetry {
                let elapsed = Date().timeIntervalSince(startedAt)
                if elapsed < 0.35 {
                    try? await Task.sleep(nanoseconds: UInt64((0.35 - elapsed) * 1_000_000_000))
                }
            }
            guard !Task.isCancelled, loadRequestID == requestID else { return }
            errorMessage = error.localizedDescription
            lastAttemptTimeText = Self.attemptTimeFormatter.string(from: Date())
            if focusedControl == nil || focusedControl == .cancelLoading {
                focusedControl = .retry
            }
        }
    }

    private static let attemptTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
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
        ZStack {
            AetherAmbientBackdrop(accent: protocolType.accentColor)

            ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 34) {
                        // 顶部标题与快捷工具按钮
                        VStack(alignment: .leading, spacing: 20) {
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
                            }

                            HStack(spacing: 18) {
                                Button {
                                    AppleTVSoundEffects.playSelect()
                                    showQRConfigSheet = true
                                } label: {
                                    Label("手机扫码填写", systemImage: "qrcode.viewfinder")
                                        .font(.system(size: 21, weight: .semibold))
                                }
                                .buttonStyle(AetherPillButtonStyle(accent: .cyan))

                                Button {
                                    AppleTVSoundEffects.playSelect()
                                    showLANDiscoverySheet = true
                                } label: {
                                    Label("扫描局域网设备", systemImage: "dot.radiowaves.left.and.right")
                                        .font(.system(size: 21, weight: .semibold))
                                }
                                .buttonStyle(AetherPillButtonStyle(accent: .purple))
                            }
                            .padding(.horizontal, 6)
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
                                .padding(.vertical, 12)
                                .padding(.horizontal, 12)
                            }
                        }

                        // 基本连接信息卡片（单栏宽松排版，杜绝输入框太窄变形或文字截断）
                        glassGroupBox(title: "连接地址", icon: "network") {
                            VStack(spacing: 20) {
                                HStack(spacing: 24) {
                                    inputField(title: "显示名称（可留空）", placeholder: "例如：家庭 NAS", text: $name)
                                    inputField(title: "服务器 IP 或主机名", placeholder: "例如：192.168.1.100 或 nas.local", text: $host)
                                }
                                HStack(spacing: 24) {
                                    inputField(title: "端口（0 表示默认端口）", placeholder: String(protocolType.defaultPort), text: $portText)
                                        .frame(maxWidth: 360)

                                    if protocolType == .smb {
                                        inputField(title: "SMB 共享文件夹名（可留空，连接后自动列出全部共享）", placeholder: "留空则自动列出共享，或填如 media", text: $shareName)
                                    } else if protocolType == .dlna {
                                        inputField(title: "DLNA ContentDirectory Control 路径", placeholder: "例如：/ctl/ContentDir", text: $basePath)
                                    } else {
                                        inputField(title: "基础路径（可留空）", placeholder: "例如：/dav 或 /", text: $basePath)
                                    }
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
                                    VStack(spacing: 20) {
                                        HStack(spacing: 24) {
                                            inputField(title: "API Key / AccessToken", placeholder: "粘贴 Token 或下方用账号登录获取", text: $apiToken)
                                            inputField(title: "用户 ID（可留空或点击下方选择）", placeholder: "留空将自动识别当前用户", text: $userId)
                                        }
                                        HStack(spacing: 24) {
                                            inputField(title: "用户名（用于登录换取 Token，可选）", placeholder: "例如：admin", text: $username)
                                            secureInputField(title: "密码（用于登录换取 Token，可选）", placeholder: "输入密码", text: $password)
                                        }
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
                                    HStack(spacing: 24) {
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
                        .padding(.horizontal, 12)
                        .padding(.bottom, 48)
                    }
                    .frame(maxWidth: 1460)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 72)
                    .padding(.vertical, 44)
                }
            }
            .fullScreenCover(isPresented: $showQRConfigSheet) {
                QuickConfigQRView { imported in
                    applyConfig(imported)
                    testMessage = "已通过手机扫码填入配置，请检查或测试后保存"
                    testSucceeded = true
                }
            }
        .fullScreenCover(isPresented: $showLANDiscoverySheet) {
            LANDiscoverySheetView { service in
                applyDiscoveredService(service)
                testMessage = "已填入发现的设备「\(service.name)」，请补充认证信息或测试连接"
                testSucceeded = true
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
        .onExitCommand {
            AppleTVSoundEffects.playBack()
            dismiss()
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

// MARK: - 局域网自动发现浮层（Bonjour + SSDP，高对比度图标卡）

struct LANDiscoverySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: PlayerSettingsStore
    @StateObject private var browser = LANServiceBrowser()
    let onSelect: (DiscoveredLANService) -> Void

    var body: some View {
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
        .onExitCommand {
            AppleTVSoundEffects.playBack()
            dismiss()
        }
    }
}
