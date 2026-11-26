import SwiftUI

struct HomeLibraryView: View {
    @EnvironmentObject private var historyStore: WatchHistoryStore
    @EnvironmentObject private var sourceStore: MediaSourceStore
    @State private var playingItem: MediaItem?
    @State private var playingList: [MediaItem] = []

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 48) {
                    // 顶部 Apple TV 风格欢迎横幅
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AetherTV")
                                .font(.system(size: 52, weight: .bold))
                            Text("原生 HDR / 杜比视界 / 全景声 · 局域网全协议播放器")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, 24)

                    // 1. 继续观看（Apple TV Up Next 风格）
                    if !historyStore.continueWatching.isEmpty {
                        shelfSection(title: "继续观看") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 36) {
                                    ForEach(historyStore.continueWatching) { entry in
                                        Button {
                                            AppleTVSoundEffects.playSelect()
                                            playingList = historyStore.continueWatching.map(\.item)
                                            playingItem = entry.item
                                        } label: {
                                            MediaPosterCard(item: entry.item, progress: entry.progress)
                                        }
                                        .buttonStyle(.card)
                                        .contextMenu {
                                            Button("清除续播进度", role: .destructive) {
                                                historyStore.clearProgress(for: entry.id)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 60)
                                .padding(.vertical, 20)
                            }
                        }
                    }

                    // 2. 媒体源入口只保留在「媒体源」标签页，首页不再重复同一批卡片；
                    //    一条观看记录都没有时给一条轻量指路，避免首页空荡
                    if historyStore.continueWatching.isEmpty && historyStore.history.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: sourceStore.sources.isEmpty ? "externaldrive.badge.wifi" : "play.rectangle.on.rectangle")
                                .font(.system(size: 64))
                                .foregroundStyle(.secondary)
                            Text(sourceStore.sources.isEmpty ? "还没有添加局域网媒体源" : "从媒体源里挑一部片子开始")
                                .font(.title2.bold())
                            Text(sourceStore.sources.isEmpty
                                 ? "请切换到顶部的「媒体源」标签页，添加您的 SMB、WebDAV、Emby、Jellyfin、Plex 或 DLNA 服务器。"
                                 : "打开顶部的「媒体源」标签页浏览 NAS 目录；播放过的内容会出现在这里的「继续观看」。")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 760)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                    }

                    // 3. 最近观看记录
                    if !historyStore.history.isEmpty {
                        shelfSection(title: "最近观看") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 36) {
                                    ForEach(historyStore.history.prefix(15)) { entry in
                                        Button {
                                            AppleTVSoundEffects.playSelect()
                                            playingList = historyStore.history.map(\.item)
                                            playingItem = entry.item
                                        } label: {
                                            MediaPosterCard(item: entry.item, progress: entry.progress)
                                        }
                                        .buttonStyle(.card)
                                    }
                                }
                                .padding(.horizontal, 60)
                                .padding(.vertical, 20)
                            }
                        }
                    }
                }
                .padding(.bottom, 60)
            }
            .fullScreenCover(item: $playingItem) { item in
                let cfg = sourceStore.sources.first { $0.id == item.sourceId }
                PlayerScreenView(item: item, playlist: playingList, sourceConfig: cfg)
            }
        }
    }

    private func shelfSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.bold())
                .padding(.horizontal, 60)
            content()
        }
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

                // 底部续播进度条
                if let progress, progress > 0.01 {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.28)).frame(height: 5)
                                Rectangle().fill(Color.white).frame(width: geo.size.width * progress, height: 5)
                            }
                        }
                    }
                }
            }
            .frame(width: 360, height: 202)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(item.protocolType.rawValue)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                    if let sub = item.subtitle {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let size = item.formattedFileSize {
                        Text(size)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .frame(width: 360, alignment: .leading)
            .background(Color.white.opacity(0.06))
        }
    }

    private var placeholderArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.16), Color(white: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: item.isDirectory ? "folder.fill" : "film.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}
