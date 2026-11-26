import SwiftUI

struct RootTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeLibraryView()
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
                .tag(0)

            SourceBrowserView()
                .tabItem {
                    Label("媒体源", systemImage: "externaldrive.badge.wifi")
                }
                .tag(1)

            FavoritesShelfView()
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
    }
}

private struct FavoritesShelfView: View {
    @EnvironmentObject private var historyStore: WatchHistoryStore
    @EnvironmentObject private var sourceStore: MediaSourceStore
    @State private var playingItem: MediaItem?

    var body: some View {
        NavigationStack {
            Group {
                if historyStore.favorites.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "star.slash")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                        Text("暂无收藏影片")
                            .font(.title2.bold())
                        Text("在媒体源列表中选择影片即可添加收藏，方便在客厅快速打开。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 36)], spacing: 36) {
                            ForEach(historyStore.favorites) { item in
                                Button {
                                    AppleTVSoundEffects.playSelect()
                                    playingItem = item
                                } label: {
                                    MediaPosterCard(item: item, progress: nil)
                                }
                                .buttonStyle(.card)
                            }
                        }
                        .padding(48)
                    }
                }
            }
            .navigationTitle("我的收藏")
            .fullScreenCover(item: $playingItem) { item in
                let cfg = sourceStore.sources.first { $0.id == item.sourceId }
                PlayerScreenView(item: item, playlist: historyStore.favorites, sourceConfig: cfg)
            }
        }
    }
}
