import Foundation
import AVFoundation

/// AetherTV 定制苹果风空间交互音效引擎（基于预加载 AVAudioPlayer 缓冲池）
/// 相比在 tvOS 上常常静默的 iOS SystemSoundID，使用随包打包的 48kHz 微声效 WAV + 多实例轮询池，
/// 既保证 Apple TV 真机上高频焦点滑动清脆不丢帧，又不篡改 AVAudioSession 类别，确保 AetherEngine 全权掌管 HDMI/eARC 音频路由。
@MainActor
enum AppleTVSoundEffects {
    enum Cue: String, CaseIterable {
        case focus = "aether_focus"
        case select = "aether_select"
        case panel = "aether_panel"
        case back = "aether_back"
        case scrub = "aether_scrub"

        var volume: Float {
            switch self {
            case .focus: return 0.55
            case .select: return 0.72
            case .panel: return 0.65
            case .back: return 0.58
            case .scrub: return 0.45
            }
        }
    }

    private static var pools: [Cue: [AVAudioPlayer]] = [:]
    private static var cursors: [Cue: Int] = [:]
    private static var didPrepare = false
    private static var lastFocusTime: TimeInterval = 0
    private static var lastTickTime: TimeInterval = 0

    static func bundleURL(for cue: Cue) -> URL? {
        Bundle.main.url(forResource: cue.rawValue, withExtension: "wav")
            ?? Bundle.main.url(forResource: cue.rawValue, withExtension: "wav", subdirectory: "Sounds")
    }

    /// 预热音效池（不修改 AVAudioSession，避免干扰 AetherEngine 的原生 HDMI / Atmos 音频会话协商）
    static func prepareIfNeeded() {
        guard !didPrepare else { return }
        didPrepare = true

        for cue in Cue.allCases {
            guard let url = bundleURL(for: cue) else { continue }
            var players: [AVAudioPlayer] = []
            for _ in 0..<3 {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.volume = cue.volume
                    player.prepareToPlay()
                    players.append(player)
                }
            }
            if !players.isEmpty {
                pools[cue] = players
                cursors[cue] = 0
            }
        }
    }

    static func playFocusTick() {
        guard PlayerSettingsStore.shared.enableSystemSoundEffects else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFocusTime >= 0.045 else { return }
        lastFocusTime = now
        play(.focus)
    }

    static func playSelect() {
        guard PlayerSettingsStore.shared.enableSystemSoundEffects else { return }
        play(.select)
    }

    static func playPanelOpen() {
        guard PlayerSettingsStore.shared.enableSystemSoundEffects else { return }
        play(.panel)
    }

    static func playBack() {
        guard PlayerSettingsStore.shared.enableSystemSoundEffects else { return }
        play(.back)
    }

    static func playScrubNotch(speedMultiplier: Double) {
        guard PlayerSettingsStore.shared.enableSystemSoundEffects else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // 速度越快，刻度音效间隔越短，但限制最高频率避免刺耳
        let minInterval = max(0.085, 0.26 / max(1.0, log2(speedMultiplier + 1.0)))
        guard now - lastTickTime >= minInterval else { return }
        lastTickTime = now
        play(.scrub)
    }

    private static func play(_ cue: Cue) {
        prepareIfNeeded()
        guard let players = pools[cue], !players.isEmpty else { return }
        let idx = cursors[cue, default: 0] % players.count
        cursors[cue] = (idx + 1) % players.count
        let player = players[idx]
        player.currentTime = 0
        player.play()
    }
}
