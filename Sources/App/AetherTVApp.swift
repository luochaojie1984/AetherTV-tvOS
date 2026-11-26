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
        }
    }
}
