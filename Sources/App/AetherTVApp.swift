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
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appSettings)
                .environmentObject(sourceStore)
                .environmentObject(historyStore)
                .preferredColorScheme(.dark)
                .task {
                    // 冒烟测试构建里才会真的跑起来；正常构建里 runIfRequested 是空函数
                    if SmokeTest.isRequested {
                        await SmokeTest.runIfRequested()
                    }
                }
        }
    }
}
