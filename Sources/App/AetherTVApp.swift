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
                    // 冒烟测试构建里才有 runner；正常构建里什么也不会发生
                    if SmokeTest.isRequested, let runner = SmokeTest.runner {
                        await runner()
                    }
                }
        }
    }
}
