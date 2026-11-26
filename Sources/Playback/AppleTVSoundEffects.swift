import Foundation
import AudioToolbox

/// 苹果 tvOS 原生交互音效封装（导航、确认、快进刻度反馈）
@MainActor
enum AppleTVSoundEffects {
    private static var lastTickTime: TimeInterval = 0

    static func playFocusTick() {
        guard PlayerSettingsStore.shared.enableSystemSoundEffects else { return }
        AudioServicesPlaySystemSound(1104)
    }

    static func playSelect() {
        guard PlayerSettingsStore.shared.enableSystemSoundEffects else { return }
        AudioServicesPlaySystemSound(1123)
    }

    static func playScrubNotch(speedMultiplier: Double) {
        guard PlayerSettingsStore.shared.enableSystemSoundEffects else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // 速度越快，刻度音效间隔越短，但限制最高频率避免刺耳
        let minInterval = max(0.09, 0.28 / max(1.0, log2(speedMultiplier + 1.0)))
        guard now - lastTickTime >= minInterval else { return }
        lastTickTime = now
        AudioServicesPlaySystemSound(1157)
    }
}
