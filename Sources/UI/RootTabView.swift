import SwiftUI

struct RootTabView: View {
    @State private var selectedTab = 0
    @State private var directoryPath: [SourceDirectoryRoute] = []

    var body: some View {
        // tvOS 关键导航架构：将唯一 NavigationStack 放在 TabView 外层。
        // 若把 NavigationStack 嵌在各个 Tab 内部，tvOS 按遥控器返回键会把焦点弹回顶部 TabBar 而非返回上一级，
        // 再按返回直接退回 Apple TV 桌面，且各个 Tab 会被永久卡在子页面。
        NavigationStack(path: $directoryPath) {
            TabView(selection: $selectedTab) {
                HomeLibraryView(
                    onOpenSourcesTab: { selectedTab = 1 },
                    onOpenSource: { openSourceRoot($0) }
                )
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
                .tag(0)

                SourceBrowserView(
                    onOpenSource: { openSourceRoot($0) }
                )
                .tabItem {
                    Label("媒体源", systemImage: "server.rack")
                }
                .tag(1)

                FavoritesShelfView(onOpenSourcesTab: { selectedTab = 1 })
                    .tabItem {
                        Label("收藏", systemImage: "star.fill")
                    }
                    .tag(2)

                AppSettingsView()
                    .tabItem {
                        Label("设置", systemImage: "gearshape.fill")
                    }
                    .tag(3)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: selectedTab) { _, _ in
                AppleTVSoundEffects.playFocusTick()
            }
            .navigationDestination(for: SourceDirectoryRoute.self) { route in
                SourceDirectoryView(
                    route: route,
                    onOpenSubdirectory: { subRoute in
                        directoryPath.append(subRoute)
                    },
                    onGoBack: {
                        // 仅弹出当前栈顶匹配的这一级，避免系统返回与 onExitCommand 叠加造成连退两级
                        if directoryPath.last == route {
                            directoryPath.removeLast()
                        }
                    },
                    onPopToRoot: {
                        directoryPath.removeAll()
                    }
                )
            }
        }
    }

    private func openSourceRoot(_ source: MediaSourceConfig) {
        let route = SourceDirectoryRoute(
            sourceId: source.id,
            currentPath: source.protocolType == .dlna ? "0" : "/",
            displayTitle: nil,
            fallbackSource: source
        )
        directoryPath.append(route)
    }
}

private struct FavoritesShelfView: View {
    var onOpenSourcesTab: () -> Void = {}

    @EnvironmentObject private var historyStore: WatchHistoryStore
    @EnvironmentObject private var sourceStore: MediaSourceStore
    @State private var playingItem: MediaItem?

    var body: some View {
        ZStack {
            AetherAmbientBackdrop(accent: Color(red: 0.96, green: 0.68, blue: 0.22))

            if historyStore.favorites.isEmpty {
                VStack(spacing: 28) {
                    AetherIconMedallion(
                        systemName: "star.fill",
                        colors: [Color(red: 0.94, green: 0.60, blue: 0.12), Color(red: 0.98, green: 0.80, blue: 0.28)],
                        size: 96
                    )
                    VStack(spacing: 10) {
                        Text("收藏夹尚无影片")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text("在媒体源影片上长按确认键，即可将常看影片加入收藏")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.white.opacity(0.65))
                    }
                    Button {
                        AppleTVSoundEffects.playSelect()
                        onOpenSourcesTab()
                    } label: {
                        Label("前往媒体源挑选影片", systemImage: "server.rack")
                            .font(.system(size: 23, weight: .semibold))
                    }
                    .buttonStyle(AetherPillButtonStyle(
                        accent: Color(red: 0.96, green: 0.72, blue: 0.20),
                        prominent: true,
                        horizontalPadding: 32,
                        verticalPadding: 16
                    ))
                }
                .padding(60)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 32) {
                        AetherSectionHeader(
                            title: "我的收藏",
                            subtitle: "\(historyStore.favorites.count) 部影片",
                            icon: "star.fill"
                        )
                        .padding(.horizontal, 60)
                        .padding(.top, 28)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 380, maximum: 440), spacing: 36)],
                            spacing: 36
                        ) {
                            ForEach(historyStore.favorites) { item in
                                Button {
                                    AppleTVSoundEffects.playSelect()
                                    playingItem = item
                                } label: {
                                    MediaPosterCard(item: item, progress: nil)
                                }
                                .buttonStyle(AetherPosterCardStyle(accent: item.protocolType.accentColor))
                                .contextMenu {
                                    Button("取消收藏", role: .destructive) {
                                        historyStore.toggleFavorite(item)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.bottom, 64)
                    }
                }
            }
        }
        .fullScreenCover(item: $playingItem) { item in
            let cfg = sourceStore.sources.first { $0.id == item.sourceId }
            PlayerScreenView(item: item, playlist: historyStore.favorites, sourceConfig: cfg)
        }
    }
}
