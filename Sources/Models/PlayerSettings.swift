import Foundation
import SwiftUI

enum DecodePreference: String, Codable, CaseIterable, Identifiable {
    case automatic = "自动（优先硬解）"
    case software = "强制软解（兼容模式）"
    var id: String { rawValue }
}

enum VideoAspectMode: String, Codable, CaseIterable, Identifiable {
    case aspectFit = "原始比例"
    case aspectFill = "铺满屏幕"
    var id: String { rawValue }
}

enum DolbyVisionMode: String, Codable, CaseIterable, Identifiable {
    case automatic = "自动（原生杜比视界）"
    case baseLayerOnly = "仅 HDR10/HLG 基础层（防绿紫偏色）"
    var id: String { rawValue }
}

enum AudioBridgePreference: String, Codable, CaseIterable, Identifiable {
    case surroundCompat = "环绕声兼容（ARC / 回音壁）"
    case lossless = "无损多声道 LPCM（eARC / 功放）"
    var id: String { rawValue }
}

enum SubtitleColorPreset: String, Codable, CaseIterable, Identifiable {
    case white = "纯白"
    case warmWhite = "暖白"
    case yellow = "明黄"
    case cyan = "青蓝"
    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .white: return .white
        case .warmWhite: return Color(red: 0.98, green: 0.95, blue: 0.88)
        case .yellow: return Color(red: 1.0, green: 0.88, blue: 0.25)
        case .cyan: return Color(red: 0.45, green: 0.90, blue: 1.0)
        }
    }
}

enum SleepTimerOption: Int, CaseIterable, Identifiable {
    case off = 0
    case min15 = 15
    case min30 = 30
    case min45 = 45
    case min60 = 60
    case min90 = 90

    var id: Int { rawValue }
    var label: String {
        rawValue == 0 ? "关闭" : "\(rawValue) 分钟"
    }
}

@MainActor
final class PlayerSettingsStore: ObservableObject {
    static let shared = PlayerSettingsStore()

    // MARK: - 字幕设置
    @Published var subtitleFontSize: Double = 46 { didSet { persist() } }
    /// 距离屏幕底部的偏移像素（支持微调，默认 48pt，贴近屏幕底部不遮挡主体）
    @Published var subtitleBottomOffset: Double = 48 { didSet { persist() } }
    @Published var subtitleColor: SubtitleColorPreset = .white { didSet { persist() } }
    @Published var subtitleBackgroundOpacity: Double = 0.0 { didSet { persist() } }
    @Published var subtitleStrokeEnabled: Bool = true { didSet { persist() } }
    @Published var subtitleShadowEnabled: Bool = true { didSet { persist() } }
    /// 字幕时间偏移（秒），正值延后，负值提前
    @Published var subtitleDelaySeconds: Double = 0.0 { didSet { persist() } }
    /// 保留 ASS 特效样式（位置、颜色、粗斜体等）
    @Published var preserveASSStyling: Bool = true { didSet { persist() } }
    /// 副字幕垂直位置（双语模式下显示在顶部或主字幕上方）
    @Published var secondarySubtitleAtTop: Bool = false { didSet { persist() } }

    // MARK: - 音画与解码设置
    @Published var decodePreference: DecodePreference = .automatic { didSet { persist() } }
    @Published var aspectMode: VideoAspectMode = .aspectFit { didSet { persist() } }
    @Published var dolbyVisionMode: DolbyVisionMode = .automatic { didSet { persist() } }
    @Published var audioBridgePreference: AudioBridgePreference = .surroundCompat { didSet { persist() } }
    @Published var matchContentEnabled: Bool = true { didSet { persist() } }
    @Published var upscaleLowResSDR: Bool = false { didSet { persist() } }
    @Published var audioDelaySeconds: Double = 0.0 { didSet { persist() } }
    @Published var dialogueLiftDB: Double = 0.0 { didSet { persist() } }
    @Published var nightModeEnabled: Bool = false { didSet { persist() } }
    @Published var loudnessNormalizeEnabled: Bool = false { didSet { persist() } }

    // MARK: - 播放体验设置
    @Published var preferredAudioLanguage: String = "zh,en" { didSet { persist() } }
    @Published var preferredSubtitleLanguage: String = "zh-Hans,zh,en" { didSet { persist() } }
    @Published var autoResumePlayback: Bool = true { didSet { persist() } }
    @Published var autoPlayNextEpisode: Bool = true { didSet { persist() } }
    @Published var skipIntroSeconds: Int = 90 { didSet { persist() } }
    @Published var skipOutroSeconds: Int = 90 { didSet { persist() } }
    @Published var enableSystemSoundEffects: Bool = true { didSet { persist() } }
    @Published var showStatsHUD: Bool = false { didSet { persist() } }

    // MARK: - 局域网避坑设置
    @Published var allowSelfSignedCertificates: Bool = true {
        didSet {
            NetworkPitfallGuards.configureEngineTLS(allowSelfSignedLAN: allowSelfSignedCertificates)
            persist()
        }
    }
    @Published var forwardBufferSegments: Int = 12 { didSet { persist() } }

    private struct Snapshot: Codable {
        var subtitleFontSize: Double
        var subtitleBottomOffset: Double
        var subtitleColor: SubtitleColorPreset
        var subtitleBackgroundOpacity: Double
        var subtitleStrokeEnabled: Bool
        var subtitleShadowEnabled: Bool
        var subtitleDelaySeconds: Double
        var preserveASSStyling: Bool
        var secondarySubtitleAtTop: Bool
        var decodePreference: DecodePreference
        var aspectMode: VideoAspectMode
        var dolbyVisionMode: DolbyVisionMode
        var audioBridgePreference: AudioBridgePreference
        var matchContentEnabled: Bool
        var upscaleLowResSDR: Bool
        var audioDelaySeconds: Double
        var dialogueLiftDB: Double
        var nightModeEnabled: Bool
        var loudnessNormalizeEnabled: Bool
        var preferredAudioLanguage: String
        var preferredSubtitleLanguage: String
        var autoResumePlayback: Bool
        var autoPlayNextEpisode: Bool
        var skipIntroSeconds: Int
        var skipOutroSeconds: Int
        var enableSystemSoundEffects: Bool
        var showStatsHUD: Bool
        var allowSelfSignedCertificates: Bool
        var forwardBufferSegments: Int
    }

    private let key = "AetherTV.PlayerSettings.v1"

    private init() {
        restore()
    }

    var parsedAudioLanguages: [String] {
        preferredAudioLanguage
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var parsedSubtitleLanguages: [String] {
        preferredSubtitleLanguage
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func persist() {
        let snap = Snapshot(
            subtitleFontSize: subtitleFontSize,
            subtitleBottomOffset: subtitleBottomOffset,
            subtitleColor: subtitleColor,
            subtitleBackgroundOpacity: subtitleBackgroundOpacity,
            subtitleStrokeEnabled: subtitleStrokeEnabled,
            subtitleShadowEnabled: subtitleShadowEnabled,
            subtitleDelaySeconds: subtitleDelaySeconds,
            preserveASSStyling: preserveASSStyling,
            secondarySubtitleAtTop: secondarySubtitleAtTop,
            decodePreference: decodePreference,
            aspectMode: aspectMode,
            dolbyVisionMode: dolbyVisionMode,
            audioBridgePreference: audioBridgePreference,
            matchContentEnabled: matchContentEnabled,
            upscaleLowResSDR: upscaleLowResSDR,
            audioDelaySeconds: audioDelaySeconds,
            dialogueLiftDB: dialogueLiftDB,
            nightModeEnabled: nightModeEnabled,
            loudnessNormalizeEnabled: loudnessNormalizeEnabled,
            preferredAudioLanguage: preferredAudioLanguage,
            preferredSubtitleLanguage: preferredSubtitleLanguage,
            autoResumePlayback: autoResumePlayback,
            autoPlayNextEpisode: autoPlayNextEpisode,
            skipIntroSeconds: skipIntroSeconds,
            skipOutroSeconds: skipOutroSeconds,
            enableSystemSoundEffects: enableSystemSoundEffects,
            showStatsHUD: showStatsHUD,
            allowSelfSignedCertificates: allowSelfSignedCertificates,
            forwardBufferSegments: forwardBufferSegments
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        subtitleFontSize = snap.subtitleFontSize
        subtitleBottomOffset = snap.subtitleBottomOffset
        subtitleColor = snap.subtitleColor
        subtitleBackgroundOpacity = snap.subtitleBackgroundOpacity
        subtitleStrokeEnabled = snap.subtitleStrokeEnabled
        subtitleShadowEnabled = snap.subtitleShadowEnabled
        subtitleDelaySeconds = snap.subtitleDelaySeconds
        preserveASSStyling = snap.preserveASSStyling
        secondarySubtitleAtTop = snap.secondarySubtitleAtTop
        decodePreference = snap.decodePreference
        aspectMode = snap.aspectMode
        dolbyVisionMode = snap.dolbyVisionMode
        audioBridgePreference = snap.audioBridgePreference
        matchContentEnabled = snap.matchContentEnabled
        upscaleLowResSDR = snap.upscaleLowResSDR
        audioDelaySeconds = snap.audioDelaySeconds
        dialogueLiftDB = snap.dialogueLiftDB
        nightModeEnabled = snap.nightModeEnabled
        loudnessNormalizeEnabled = snap.loudnessNormalizeEnabled
        preferredAudioLanguage = snap.preferredAudioLanguage
        preferredSubtitleLanguage = snap.preferredSubtitleLanguage
        autoResumePlayback = snap.autoResumePlayback
        autoPlayNextEpisode = snap.autoPlayNextEpisode
        skipIntroSeconds = snap.skipIntroSeconds
        skipOutroSeconds = snap.skipOutroSeconds
        enableSystemSoundEffects = snap.enableSystemSoundEffects
        showStatsHUD = snap.showStatsHUD
        allowSelfSignedCertificates = snap.allowSelfSignedCertificates
        forwardBufferSegments = snap.forwardBufferSegments
    }
}
