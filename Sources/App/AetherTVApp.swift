import SwiftUI
import AetherEngine

@main
struct AetherTVApp: App {
    @StateObject private var appSettings = PlayerSettingsStore.shared
    @StateObject private var sourceStore = MediaSourceStore.shared
    @StateObject private var historyStore = WatchHistoryStore.shared

    init() {
        NetworkPitfallGuards.configureEngineTLS(
            allowSelfSignedLAN: PlayerSettingsStore.shared.allowSelfSignedCertificates
        )
        // 冷启动时清理上次异常退出遗留的临时字幕缓存
        let subtitleCacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AetherTVSubtitles", isDirectory: true)
        try? FileManager.default.removeItem(at: subtitleCacheRoot)

        // 冒烟测试从这里启动，而不是 SwiftUI 的 .task：弹出全屏页面会让根视图“消失”，
        // SwiftUI 随之取消 .task，正在进行的网络请求会被一起取消。
        if SmokeTest.isRequested {
            Task { @MainActor in
                await SmokeTest.runIfRequested()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appSettings)
                .environmentObject(sourceStore)
                .environmentObject(historyStore)
                .preferredColorScheme(.dark)
        }
    }
}
