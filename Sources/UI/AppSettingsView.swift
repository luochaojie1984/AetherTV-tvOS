import SwiftUI
import AetherEngine

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case video = "视频与 HDR"
    case audio = "音频与声道"
    case subtitles = "字幕默认偏好"
    case playback = "播放与音效"
    case network = "局域网与缓冲"
    case diagnostics = "设备与引擎诊断"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .video: return "sparkles.tv.fill"
        case .audio: return "hifispeaker.2.fill"
        case .subtitles: return "captions.bubble.fill"
        case .playback: return "wand.and.stars"
        case .network: return "network"
        case .diagnostics: return "cpu.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .video: return [Color(red: 0.14, green: 0.48, blue: 0.98), Color(red: 0.16, green: 0.80, blue: 0.98)]
        case .audio: return [Color(red: 0.08, green: 0.64, blue: 0.48), Color(red: 0.22, green: 0.86, blue: 0.68)]
        case .subtitles: return [Color(red: 0.48, green: 0.28, blue: 0.96), Color(red: 0.28, green: 0.72, blue: 1.0)]
        case .playback: return [Color(red: 0.90, green: 0.50, blue: 0.12), Color(red: 0.98, green: 0.76, blue: 0.24)]
        case .network: return [Color(red: 0.10, green: 0.60, blue: 0.74), Color(red: 0.22, green: 0.84, blue: 0.92)]
        case .diagnostics: return [Color(red: 0.34, green: 0.40, blue: 0.62), Color(red: 0.48, green: 0.64, blue: 0.92)]
        }
    }

    var subtitle: String {
        switch self {
        case .video: return "解码通道、杜比视界与帧率匹配"
        case .audio: return "eARC / ARC 桥接、夜间模式与响度"
        case .subtitles: return "默认语言、ASS 特效与双语排版"
        case .playback: return "自动续播、连播、HUD 与空间音效"
        case .network: return "局域网自签名证书与前向缓冲"
        case .diagnostics: return "Apple TV HDR 能力与引擎版本"
        }
    }
}

struct AppSettingsView: View {
    @EnvironmentObject private var settings: PlayerSettingsStore
    @State private var selectedCategory: SettingsCategory = .video

    private let bufferChoices = Array(stride(from: 4, through: 40, by: 4))

    var body: some View {
        ZStack {
            AetherAmbientBackdrop(accent: selectedCategory.colors.first ?? .cyan)

            HStack(alignment: .top, spacing: 42) {
                // 左侧：图标化分类侧边栏（杜绝原生 Form 聚焦白底白字）
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        AetherSectionHeader(title: "设置", icon: "gearshape.fill")
                            .padding(.bottom, 8)

                        ForEach(SettingsCategory.allCases) { cat in
                            Button {
                                AppleTVSoundEffects.playSelect()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedCategory = cat
                                }
                            } label: {
                                HStack(spacing: 18) {
                                    AetherIconMedallion(systemName: cat.icon, colors: cat.colors, size: 52)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(cat.rawValue)
                                            .font(.system(size: 24, weight: .semibold))
                                            .foregroundStyle(Color.white)
                                        Text(cat.subtitle)
                                            .font(.system(size: 16))
                                            .foregroundStyle(Color.white.opacity(0.60))
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if selectedCategory == cat {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(cat.colors.first ?? Color.cyan)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(AetherSpotlightCardStyle(
                                accent: cat.colors.first ?? .cyan,
                                isSelected: selectedCategory == cat,
                                cornerRadius: 20
                            ))
                        }
                    }
                    .padding(.vertical, 32)
                    .padding(.horizontal, 22)
                }
                .frame(width: 490)

                // 右侧：高对比度玻璃设置卡片区
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 16) {
                            AetherIconMedallion(systemName: selectedCategory.icon, colors: selectedCategory.colors, size: 58)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedCategory.rawValue)
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundStyle(Color.white)
                                Text(selectedCategory.subtitle)
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.white.opacity(0.62))
                            }
                        }
                        .padding(.bottom, 8)

                        switch selectedCategory {
                        case .video:
                            videoSection
                        case .audio:
                            audioSection
                        case .subtitles:
                            subtitleSection
                        case .playback:
                            playbackSection
                        case .network:
                            networkSection
                        case .diagnostics:
                            diagnosticsSection
                        }
                    }
                    .padding(.vertical, 32)
                    .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 52)
        }
    }

    // MARK: - 各分类设置卡片

    @ViewBuilder
    private var videoSection: some View {
        AetherCycleOptionCard(
            icon: "cpu",
            colors: SettingsCategory.video.colors,
            title: "默认解码方式",
            valueText: settings.decodePreference.rawValue,
            subtitle: "点按切换硬解优先或兼容软解通道"
        ) {
            settings.decodePreference = nextCase(settings.decodePreference)
        }

        AetherCycleOptionCard(
            icon: "aspectratio.fill",
            colors: SettingsCategory.video.colors,
            title: "默认画面比例",
            valueText: settings.aspectMode.rawValue,
            subtitle: "单部影片在播放面板中的调整将独立记忆"
        ) {
            settings.aspectMode = nextCase(settings.aspectMode)
        }

        AetherCycleOptionCard(
            icon: "sun.max.fill",
            colors: [Color(red: 0.44, green: 0.28, blue: 0.96), Color(red: 0.22, green: 0.76, blue: 1.0)],
            title: "杜比视界策略",
            valueText: settings.dolbyVisionMode.rawValue,
            subtitle: "老旧或非杜比电视遇偏色时可切至仅基础层"
        ) {
            settings.dolbyVisionMode = nextCase(settings.dolbyVisionMode)
        }

        AetherToggleCard(
            icon: "tv.and.mediabox",
            colors: SettingsCategory.video.colors,
            title: "匹配动态范围与帧率",
            subtitle: "播放 24p / HDR / 杜比视界片源时自动匹配电视输出模式",
            isOn: $settings.matchContentEnabled
        )

        AetherToggleCard(
            icon: "sparkles",
            colors: SettingsCategory.video.colors,
            title: "低清 SDR 视频超分放大",
            subtitle: "对 720p 及以下低码率 SDR 影片开启 MetalFX 画质增强",
            isOn: $settings.upscaleLowResSDR
        )
    }

    @ViewBuilder
    private var audioSection: some View {
        AetherCycleOptionCard(
            icon: "hifispeaker.2.fill",
            colors: SettingsCategory.audio.colors,
            title: "多声道桥接模式",
            valueText: settings.audioBridgePreference.rawValue,
            subtitle: "回音壁选环绕兼容，eARC 功放选无损多声道 LPCM"
        ) {
            settings.audioBridgePreference = nextCase(settings.audioBridgePreference)
        }

        AetherToggleCard(
            icon: "moon.stars.fill",
            colors: SettingsCategory.audio.colors,
            title: "夜间模式（压缩大动态音量）",
            subtitle: "压低爆炸等超大声效并提升微弱环境细节",
            isOn: $settings.nightModeEnabled
        )

        AetherToggleCard(
            icon: "waveform.path.ecg",
            colors: SettingsCategory.audio.colors,
            title: "响度均衡 (-20 LUFS)",
            subtitle: "自动平衡不同片源音量落差，拉升偏小声影片",
            isOn: $settings.loudnessNormalizeEnabled
        )
    }

    @ViewBuilder
    private var subtitleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("首选音轨语言（逗号分隔，如 zh,en）")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.82))
            TextField("zh,en", text: $settings.preferredAudioLanguage)
                .padding(14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(20)
        .background(Color(red: 0.08, green: 0.10, blue: 0.17).opacity(0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))

        VStack(alignment: .leading, spacing: 12) {
            Text("首选字幕语言（逗号分隔，如 zh-Hans,zh,en）")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.82))
            TextField("zh-Hans,zh,en", text: $settings.preferredSubtitleLanguage)
                .padding(14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(20)
        .background(Color(red: 0.08, green: 0.10, blue: 0.17).opacity(0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))

        AetherToggleCard(
            icon: "textformat.alt",
            colors: SettingsCategory.subtitles.colors,
            title: "保留 ASS 特效字幕样式",
            subtitle: "保留颜色、粗斜体与九宫格屏幕锚点定位",
            isOn: $settings.preserveASSStyling
        )

        AetherToggleCard(
            icon: "rectangle.split.1x2.fill",
            colors: SettingsCategory.subtitles.colors,
            title: "双语副字幕显示在屏幕顶部",
            subtitle: "关闭时副字幕将紧凑叠加在主字幕上方",
            isOn: $settings.secondarySubtitleAtTop
        )
    }

    @ViewBuilder
    private var playbackSection: some View {
        AetherToggleCard(
            icon: "play.circle.fill",
            colors: SettingsCategory.playback.colors,
            title: "自动续播上次观看位置",
            subtitle: "同时支持本地记录与 Emby / Jellyfin / Plex 远端进度",
            isOn: $settings.autoResumePlayback
        )

        AetherToggleCard(
            icon: "forward.end.fill",
            colors: SettingsCategory.playback.colors,
            title: "剧集自动预热并连播下一集",
            subtitle: "片尾自动预加载下一集开头数据，无缝切集",
            isOn: $settings.autoPlayNextEpisode
        )

        AetherToggleCard(
            icon: "speaker.wave.2.fill",
            colors: SettingsCategory.playback.colors,
            title: "空间交互与快进刻度音效",
            subtitle: "焦点移动、确认点击与变速快进时播放定制微声效",
            isOn: $settings.enableSystemSoundEffects
        )

        AetherToggleCard(
            icon: "gauge.with.dots.needle.67percent",
            colors: SettingsCategory.playback.colors,
            title: "默认显示 1Hz 实时码率/解码 HUD",
            subtitle: "播放期间随时按上方向键也可快速开关",
            isOn: $settings.showStatsHUD
        )

        Button {
            AppleTVSoundEffects.playPanelOpen()
        } label: {
            Label("试听 AetherTV 空间交互音效", systemImage: "music.note")
                .font(.system(size: 22, weight: .semibold))
        }
        .buttonStyle(AetherPillButtonStyle(accent: SettingsCategory.playback.colors.first ?? .orange))
    }

    @ViewBuilder
    private var networkSection: some View {
        AetherToggleCard(
            icon: "lock.shield.fill",
            colors: SettingsCategory.network.colors,
            title: "信任局域网自签名 HTTPS 证书",
            subtitle: "仅对内网 IP / .local / .lan 生效，不影响公网证书校验",
            isOn: $settings.allowSelfSignedCertificates
        )

        AetherCycleOptionCard(
            icon: "memorychip.fill",
            colors: SettingsCategory.network.colors,
            title: "前向缓冲分片数",
            valueText: "\(settings.forwardBufferSegments) 片（约 \(settings.forwardBufferSegments * 4) 秒）",
            subtitle: "高码率 4K Remux 建议 12~20 片以抵抗 Wi-Fi 波动"
        ) {
            if let idx = bufferChoices.firstIndex(where: { $0 >= settings.forwardBufferSegments }) {
                settings.forwardBufferSegments = bufferChoices[(idx + 1) % bufferChoices.count]
            } else {
                settings.forwardBufferSegments = 12
            }
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        let caps = AetherEngine.displayCapabilities
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)], spacing: 20) {
            diagnosticTile(title: "AetherEngine 引擎版本", value: AetherEngine.version, icon: "cube.fill", accent: .cyan)
            diagnosticTile(title: "HDR 显示输出", value: caps.supportsHDR ? "已支持" : "未开启", icon: "sun.max.fill", accent: caps.supportsHDR ? .green : .orange)
            diagnosticTile(title: "Dolby Vision 杜比视界", value: caps.supportsDolbyVision ? "已支持" : "不支持", icon: "sparkles.tv.fill", accent: caps.supportsDolbyVision ? .purple : .gray)
            diagnosticTile(title: "HDR10 / HLG", value: "\(caps.supportsHDR10 ? "HDR10" : "-") · \(caps.supportsHLG ? "HLG" : "-")", icon: "tv.fill", accent: .blue)
        }
    }

    private func diagnosticTile(title: String, value: String, icon: String, accent: Color) -> some View {
        HStack(spacing: 18) {
            AetherIconMedallion(systemName: icon, colors: [accent, accent.opacity(0.65)], size: 54)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.66))
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
            }
            Spacer()
        }
        .padding(24)
        .background(Color(red: 0.08, green: 0.11, blue: 0.19).opacity(0.88), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1.2)
        )
    }

    private func nextCase<T: CaseIterable & Equatable>(_ current: T) -> T {
        let all = Array(T.allCases)
        guard let idx = all.firstIndex(of: current) else { return current }
        return all[(idx + 1) % all.count]
    }
}
