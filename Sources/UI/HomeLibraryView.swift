import SwiftUI

struct HomeLibraryView: View {
    var onOpenSourcesTab: () -> Void = {}

    @EnvironmentObject private var historyStore: WatchHistoryStore
    @EnvironmentObject private var sourceStore: MediaSourceStore

    @State private var playingItem: MediaItem?
    @State private var playingList: [MediaItem] = []
    @State private var quickAddProtocol: MediaProtocolType?
    @State private var showQRConfigSheet = false
    @State private var showLANDiscoverySheet = false
    @State private var prefillServiceForAdd: DiscoveredLANService?

    private var heroEntry: WatchHistoryEntry? {
        historyStore.continueWatching.first ?? historyStore.history.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AetherAmbientBackdrop(accent: heroEntry?.item.protocolType.accentColor ?? Color(red: 0.20, green: 0.72, blue: 1.0))

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 46) {
                        // 1. 影院级 Hero 主舞台（有观看记录则展示大片续播舞台，无记录则展示沉浸式功能快捷入口，不再堆砌无意义纯文字）
                        if let entry = heroEntry {
                            featuredPlaybackHero(entry: entry)
                                .padding(.horizontal, 60)
                                .padding(.top, 24)
                        } else {
                            cinematicLauncherHero
                                .padding(.horizontal, 60)
                                .padding(.top, 24)
                        }

                        // 2. 已添加的媒体源（精美图标卡片横排，直接一键浏览）
                        if !sourceStore.sources.isEmpty {
                            VStack(alignment: .leading, spacing: 18) {
                                AetherSectionHeader(
                                    title: "我的媒体源",
                                    subtitle: "\(sourceStore.sources.count) 个已连接",
                                    icon: "server.rack"
                                )
                                .padding(.horizontal, 60)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 28) {
                                        ForEach(sourceStore.sources) { source in
                                            NavigationLink {
                                                SourceDirectoryView(
                                                    source: source,
                                                    currentPath: source.protocolType == .dlna ? "0" : "/"
                                                )
                                            } label: {
                                                HomeSourceCardContent(source: source)
                                            }
                                            .buttonStyle(AetherSpotlightCardStyle(accent: source.protocolType.accentColor, cornerRadius: 22))
                                        }

                                        Button {
                                            AppleTVSoundEffects.playSelect()
                                            quickAddProtocol = .smb
                                        } label: {
                                            VStack(spacing: 12) {
                                                AetherIconMedallion(
                                                    systemName: "plus",
                                                    colors: [Color(red: 0.20, green: 0.54, blue: 0.96), Color(red: 0.14, green: 0.80, blue: 0.96)],
                                                    size: 54
                                                )
                                                Text("添加媒体源")
                                                    .font(.system(size: 20, weight: .semibold))
                                                    .foregroundStyle(Color.white)
                                            }
                                            .frame(width: 210, height: 152)
                                        }
                                        .buttonStyle(AetherSpotlightCardStyle(accent: .cyan, cornerRadius: 22))
                                    }
                                    .padding(.horizontal, 60)
                                    .padding(.vertical, 18)
                                }
                            }
                        }

                        // 3. 继续观看（Apple TV Up Next 宽屏影院卡片）
                        if !historyStore.continueWatching.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                AetherSectionHeader(
                                    title: "继续观看",
                                    subtitle: "无缝续播上次进度",
                                    icon: "play.circle.fill"
                                )
                                .padding(.horizontal, 60)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 34) {
                                        ForEach(historyStore.continueWatching) { entry in
                                            Button {
                                                AppleTVSoundEffects.playSelect()
                                                playingList = historyStore.continueWatching.map(\.item)
                                                playingItem = entry.item
                                            } label: {
                                                MediaPosterCard(item: entry.item, progress: entry.progress)
                                            }
                                            .buttonStyle(AetherPosterCardStyle(accent: entry.item.protocolType.accentColor))
                                            .contextMenu {
                                                Button("清除续播进度", role: .destructive) {
                                                    historyStore.clearProgress(for: entry.id)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 60)
                                    .padding(.vertical, 22)
                                }
                            }
                        }

                        // 4. 最近观看
                        if !historyStore.history.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                AetherSectionHeader(
                                    title: "最近观看",
                                    icon: "clock.arrow.circlepath"
                                )
                                .padding(.horizontal, 60)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 34) {
                                        ForEach(historyStore.history.prefix(15)) { entry in
                                            Button {
                                                AppleTVSoundEffects.playSelect()
                                                playingList = historyStore.history.map(\.item)
                                                playingItem = entry.item
                                            } label: {
                                                MediaPosterCard(item: entry.item, progress: entry.progress)
                                            }
                                            .buttonStyle(AetherPosterCardStyle(accent: entry.item.protocolType.accentColor))
                                        }
                                    }
                                    .padding(.horizontal, 60)
                                    .padding(.vertical, 22)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 70)
                }
            }
            .fullScreenCover(item: $playingItem) { item in
                let cfg = sourceStore.sources.first { $0.id == item.sourceId }
                PlayerScreenView(item: item, playlist: playingList, sourceConfig: cfg)
            }
            .sheet(item: $quickAddProtocol) { proto in
                AddMediaSourceView(initialProtocol: proto) { newSource in
                    sourceStore.add(newSource)
                }
            }
            .sheet(item: $prefillServiceForAdd) { service in
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
                    prefillServiceForAdd = service
                }
            }
        }
    }

    // MARK: - 沉浸式首屏舞台（无历史记录时：大片感视觉标志 + 4 大图标直达动作卡）

    private var cinematicLauncherHero: some View {
        VStack(alignment: .leading, spacing: 36) {
            ZStack(alignment: .leading) {
                // 影院玻璃大舞台底板
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.10, green: 0.15, blue: 0.30).opacity(0.92),
                                Color(red: 0.06, green: 0.08, blue: 0.17).opacity(0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RadialGradient(
                            colors: [Color(red: 0.18, green: 0.72, blue: 1.0).opacity(0.30), Color.clear],
                            center: UnitPoint(x: 0.86, y: 0.48),
                            startRadius: 20,
                            endRadius: 520
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.28), Color(red: 0.25, green: 0.75, blue: 1.0).opacity(0.22)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.3
                            )
                    )
                    .shadow(color: Color.black.opacity(0.50), radius: 34, x: 0, y: 16)

                HStack(spacing: 40) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            heroSpecBadge("4K HDR", accent: Color(red: 0.26, green: 0.80, blue: 1.0))
                            heroSpecBadge("Dolby Vision", accent: Color(red: 0.64, green: 0.46, blue: 1.0))
                            heroSpecBadge("Dolby Atmos", accent: Color(red: 0.24, green: 0.86, blue: 0.58))
                            heroSpecBadge("ASS / PGS 特效字幕", accent: Color(red: 0.98, green: 0.74, blue: 0.24))
                        }

                        Text("AetherTV")
                            .font(.system(size: 62, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.white, Color(red: 0.72, green: 0.92, blue: 1.0)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        Text("局域网原盘影院 · SMB / WebDAV / Emby / Jellyfin / Plex / DLNA")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.74))
                    }

                    Spacer()

                    // 右侧立体光学棱镜徽标视觉焦点
                    ZStack {
                        Circle()
                            .strokeBorder(Color(red: 0.34, green: 0.82, blue: 1.0).opacity(0.32), lineWidth: 2)
                            .frame(width: 210, height: 210)
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color(red: 0.20, green: 0.68, blue: 1.0).opacity(0.40), Color(red: 0.10, green: 0.14, blue: 0.28).opacity(0.85)],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: 120
                                )
                            )
                            .frame(width: 170, height: 170)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(colors: [Color.white.opacity(0.70), Color.cyan.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 2
                                    )
                            )
                        Image(systemName: "play.fill")
                            .font(.system(size: 68, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.white, Color(red: 0.45, green: 0.88, blue: 1.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .offset(x: 6)
                            .shadow(color: Color.cyan.opacity(0.65), radius: 18, x: 0, y: 6)
                    }
                    .padding(.trailing, 18)
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 42)
            }

            // 直接可交互的 4 大图标卡片（告别空洞文字引导）
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 28), count: 4),
                spacing: 28
            ) {
                homeQuickActionCard(
                    title: "添加 SMB 共享",
                    subtitle: "连接 NAS / 电脑共享文件夹",
                    symbol: MediaProtocolType.smb.cardSymbolName,
                    colors: MediaProtocolType.smb.gradientColors
                ) {
                    quickAddProtocol = .smb
                }

                homeQuickActionCard(
                    title: "手机扫码配置",
                    subtitle: "浏览器填写地址，秒传电视",
                    symbol: "qrcode.viewfinder",
                    colors: [Color(red: 0.08, green: 0.60, blue: 0.68), Color(red: 0.20, green: 0.88, blue: 0.86)]
                ) {
                    showQRConfigSheet = true
                }

                homeQuickActionCard(
                    title: "扫描局域网设备",
                    subtitle: "Bonjour + DLNA 自动发现",
                    symbol: "dot.radiowaves.left.and.right",
                    colors: [Color(red: 0.48, green: 0.28, blue: 0.96), Color(red: 0.24, green: 0.72, blue: 1.0)]
                ) {
                    showLANDiscoverySheet = true
                }

                homeQuickActionCard(
                    title: "全部协议与媒体库",
                    subtitle: "WebDAV / Emby / Jellyfin / Plex",
                    symbol: "square.grid.2x2.fill",
                    colors: [Color(red: 0.90, green: 0.50, blue: 0.10), Color(red: 0.98, green: 0.76, blue: 0.24)]
                ) {
                    onOpenSourcesTab()
                }
            }
        }
    }

    // MARK: - 有观看记录时的大片级续播 Hero 舞台

    private func featuredPlaybackHero(entry: WatchHistoryEntry) -> some View {
        let item = entry.item
        let accent = item.protocolType.accentColor
        return ZStack(alignment: .bottomLeading) {
            // 背景海报与影院暗角过渡
            ZStack {
                AuthenticatedPosterImage(url: item.posterURL, sourceId: item.sourceId) {
                    LinearGradient(
                        colors: [
                            accent.opacity(0.34),
                            Color(red: 0.08, green: 0.11, blue: 0.22),
                            Color(red: 0.04, green: 0.05, blue: 0.10)
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                }
                .frame(height: 410)
                .clipped()

                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.05, blue: 0.10).opacity(0.96),
                        Color(red: 0.04, green: 0.05, blue: 0.10).opacity(0.72),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    colors: [Color.clear, Color(red: 0.04, green: 0.05, blue: 0.10).opacity(0.90)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: 410)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.26), accent.opacity(0.32)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.4
                    )
            )
            .shadow(color: Color.black.opacity(0.55), radius: 36, x: 0, y: 18)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    heroSpecBadge(item.protocolType.displayName, accent: accent)
                    if !entry.isFinished && entry.lastPositionSeconds > 10 {
                        heroSpecBadge("上次看到 \(BottomAppleProgressBar.formatTimestamp(entry.lastPositionSeconds))", accent: .white)
                    }
                    if let size = item.formattedFileSize {
                        heroSpecBadge(size, accent: Color.white.opacity(0.8))
                    }
                }

                Text(item.title)
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .frame(maxWidth: 920, alignment: .leading)

                if entry.progress > 0.01 && !entry.isFinished {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22)).frame(width: 440, height: 7)
                        Capsule()
                            .fill(LinearGradient(colors: [accent, Color.white], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 440 * entry.progress, height: 7)
                    }
                }

                HStack(spacing: 20) {
                    Button {
                        AppleTVSoundEffects.playSelect()
                        playingList = historyStore.continueWatching.isEmpty
                            ? historyStore.history.map(\.item)
                            : historyStore.continueWatching.map(\.item)
                        playingItem = item
                    } label: {
                        Label(entry.isFinished ? "重新播放" : "继续播放", systemImage: "play.fill")
                            .font(.system(size: 24, weight: .bold))
                    }
                    .buttonStyle(AetherPillButtonStyle(accent: accent, prominent: true, cornerRadius: 18, horizontalPadding: 34, verticalPadding: 16))

                    Button {
                        AppleTVSoundEffects.playSelect()
                        quickAddProtocol = .smb
                    } label: {
                        Label("添加 SMB / NAS", systemImage: "server.rack")
                            .font(.system(size: 22, weight: .semibold))
                    }
                    .buttonStyle(AetherPillButtonStyle(accent: MediaProtocolType.smb.accentColor, cornerRadius: 18, horizontalPadding: 26, verticalPadding: 16))

                    Button {
                        AppleTVSoundEffects.playSelect()
                        showQRConfigSheet = true
                    } label: {
                        Label("扫码添加", systemImage: "qrcode.viewfinder")
                            .font(.system(size: 22, weight: .semibold))
                    }
                    .buttonStyle(AetherPillButtonStyle(accent: .cyan, cornerRadius: 18, horizontalPadding: 24, verticalPadding: 16))
                }
                .padding(.top, 4)
            }
            .padding(44)
        }
    }

    private func homeQuickActionCard(
        title: String,
        subtitle: String,
        symbol: String,
        colors: [Color],
        action: @escaping () -> Void
    ) -> some View {
        Button {
            AppleTVSoundEffects.playSelect()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                AetherIconMedallion(systemName: symbol, colors: colors, size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white.opacity(0.66))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(26)
            .frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading)
        }
        .buttonStyle(AetherSpotlightCardStyle(accent: colors.first ?? .cyan, cornerRadius: 24))
    }

    private func heroSpecBadge(_ text: String, accent: Color) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(accent.opacity(0.24), in: Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(0.65), lineWidth: 1))
    }
}

private struct HomeSourceCardContent: View {
    let source: MediaSourceConfig

    var body: some View {
        HStack(spacing: 18) {
            AetherIconMedallion(
                systemName: source.protocolType.cardSymbolName,
                colors: source.protocolType.gradientColors,
                size: 62
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(source.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(source.protocolType.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(source.protocolType.accentColor)
                Text(source.baseURLString)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 380, height: 152, alignment: .leading)
    }
}

struct MediaPosterCard: View {
    let item: MediaItem
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                AuthenticatedPosterImage(url: item.posterURL, sourceId: item.sourceId) {
                    placeholderArtwork
                }

                // 柔和底角暗影
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.65)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                // 左上角协议彩色微标
                VStack {
                    HStack {
                        Text(item.protocolType.rawValue)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(item.protocolType.accentColor.opacity(0.85), in: Capsule())
                        Spacer()
                    }
                    Spacer()
                }
                .padding(14)

                // 底部发光续播进度条
                if let progress, progress > 0.01 {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.28)).frame(height: 6)
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [item.protocolType.accentColor, Color.white],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * progress, height: 6)
                            }
                        }
                    }
                }
            }
            .frame(width: 396, height: 222)
            .clipped()

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    if let sub = item.subtitle {
                        Text(sub)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.68))
                            .lineLimit(1)
                    } else if let size = item.formattedFileSize {
                        Text(size)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.68))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(width: 396, alignment: .leading)
            .background(Color(red: 0.08, green: 0.10, blue: 0.17))
        }
    }

    private var placeholderArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [
                    item.protocolType.gradientColors.first?.opacity(0.45) ?? Color(white: 0.16),
                    Color(red: 0.07, green: 0.09, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(item.protocolType.accentColor.opacity(0.18))
                .frame(width: 120, height: 120)
            Image(systemName: item.isDirectory ? "folder.fill" : "play.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .offset(x: item.isDirectory ? 0 : 4)
        }
    }
}
