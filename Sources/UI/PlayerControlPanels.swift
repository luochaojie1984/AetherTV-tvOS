import SwiftUI
import AetherEngine

enum PlayerPanelTab: String, CaseIterable, Identifiable {
    case subtitles = "字幕"
    case audio = "音频"
    case video = "画面与解码"
    case chapters = "章节与工具"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .subtitles: return "captions.bubble"
        case .audio: return "speaker.wave.3"
        case .video: return "tv"
        case .chapters: return "list.bullet.rectangle"
        }
    }
}

/// 苹果原生毛玻璃风格播放器快捷控制面板（按下方向键唤出）
struct PlayerControlPanels: View {
    @ObservedObject var controller: PlaybackController
    @ObservedObject var engine: AetherEngine
    @ObservedObject var settings: PlayerSettingsStore
    let onDismiss: () -> Void

    @State private var selectedTab: PlayerPanelTab = .subtitles

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                // 顶部苹果风格分段标签栏
                HStack(spacing: 18) {
                    ForEach(PlayerPanelTab.allCases) { tab in
                        Button {
                            AppleTVSoundEffects.playSelect()
                            selectedTab = tab
                        } label: {
                            Label(tab.rawValue, systemImage: tab.icon)
                                .font(.system(size: 22, weight: .semibold))
                                .padding(.horizontal, 22)
                                .padding(.vertical, 10)
                                .background(
                                    selectedTab == tab
                                        ? Color.white.opacity(0.24)
                                        : Color.white.opacity(0.06),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button {
                        AppleTVSoundEffects.playSelect()
                        onDismiss()
                    } label: {
                        Label("完成", systemImage: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .medium))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }

                Divider().overlay(Color.white.opacity(0.18))

                ScrollView(.vertical, showsIndicators: false) {
                    switch selectedTab {
                    case .subtitles:
                        subtitleTabContent
                    case .audio:
                        audioTabContent
                    case .video:
                        videoTabContent
                    case .chapters:
                        chaptersAndToolsTabContent
                    }
                }
                .frame(height: 430)
            }
            .padding(34)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .padding(.horizontal, 60)
            .padding(.bottom, 34)
        }
        .background(Color.black.opacity(0.38).ignoresSafeArea())
    }

    // MARK: - 字幕设置面板

    private var subtitleTabContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 主字幕轨道选择
            VStack(alignment: .leading, spacing: 10) {
                Text("主字幕轨道")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.75))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        trackChip(
                            title: "关闭字幕",
                            isSelected: !engine.isSubtitleActive
                        ) {
                            engine.clearSubtitle()
                        }

                        ForEach(engine.subtitleTracks, id: \.id) { track in
                            trackChip(
                                title: formatTrackLabel(track),
                                isSelected: engine.isSubtitleActive && engine.activeSubtitleTrackIndex == track.id
                            ) {
                                engine.selectSubtitleTrack(index: track.id)
                            }
                        }
                    }
                }
            }

            // 副字幕（双语字幕）
            if engine.subtitleTracks.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("双语副字幕（可选）")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.75))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            trackChip(title: "关闭副字幕", isSelected: !engine.isSecondarySubtitleActive) {
                                engine.clearSecondarySubtitle()
                            }
                            ForEach(engine.subtitleTracks, id: \.id) { track in
                                trackChip(title: formatTrackLabel(track), isSelected: false) {
                                    engine.selectSecondarySubtitleTrack(index: track.id)
                                }
                            }
                        }
                    }
                }
            }

            // 常见字幕核心参数调节（大小、垂直位置、延迟、样式）
            HStack(spacing: 24) {
                stepperCard(
                    title: "字幕大小",
                    valueText: "\(Int(settings.subtitleFontSize)) pt",
                    onDecrement: { settings.subtitleFontSize = max(28, settings.subtitleFontSize - 4) },
                    onIncrement: { settings.subtitleFontSize = min(80, settings.subtitleFontSize + 4) }
                )

                stepperCard(
                    title: "字幕底部位置",
                    valueText: "\(Int(settings.subtitleBottomOffset)) pt",
                    onDecrement: { settings.subtitleBottomOffset = max(12, settings.subtitleBottomOffset - 12) },
                    onIncrement: { settings.subtitleBottomOffset = min(220, settings.subtitleBottomOffset + 12) }
                )

                stepperCard(
                    title: "时间偏移",
                    valueText: String(format: "%+.1fs", settings.subtitleDelaySeconds),
                    onDecrement: { settings.subtitleDelaySeconds = max(-10, settings.subtitleDelaySeconds - 0.2) },
                    onIncrement: { settings.subtitleDelaySeconds = min(10, settings.subtitleDelaySeconds + 0.2) }
                )
            }

            HStack(spacing: 18) {
                // 颜色切换
                ForEach(SubtitleColorPreset.allCases) { preset in
                    trackChip(title: "颜色：\(preset.rawValue)", isSelected: settings.subtitleColor == preset) {
                        settings.subtitleColor = preset
                    }
                }

                trackChip(title: "保留 ASS 特效样式", isSelected: settings.preserveASSStyling) {
                    settings.preserveASSStyling.toggle()
                }

                trackChip(
                    title: settings.subtitleBackgroundOpacity > 0.1 ? "字幕底框：开" : "字幕底框：关",
                    isSelected: settings.subtitleBackgroundOpacity > 0.1
                ) {
                    settings.subtitleBackgroundOpacity = settings.subtitleBackgroundOpacity > 0.1 ? 0.0 : 0.55
                }
            }
        }
    }

    // MARK: - 音频设置面板

    private var audioTabContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("音轨选择")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.75))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(engine.audioTracks, id: \.id) { track in
                            trackChip(
                                title: formatAudioTrackLabel(track),
                                isSelected: engine.activeAudioTrackIndex == track.id
                            ) {
                                engine.selectAudioTrack(index: track.id)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 24) {
                stepperCard(
                    title: "音频同步延迟",
                    valueText: String(format: "%+.2fs", settings.audioDelaySeconds),
                    onDecrement: { controller.setAudioDelay(settings.audioDelaySeconds - 0.05) },
                    onIncrement: { controller.setAudioDelay(settings.audioDelaySeconds + 0.05) }
                )

                stepperCard(
                    title: "对白增强",
                    valueText: String(format: "+%.0f dB", settings.dialogueLiftDB),
                    onDecrement: {
                        settings.dialogueLiftDB = max(0, settings.dialogueLiftDB - 2)
                        controller.applyAudioShaping()
                    },
                    onIncrement: {
                        settings.dialogueLiftDB = min(12, settings.dialogueLiftDB + 2)
                        controller.applyAudioShaping()
                    }
                )
            }

            HStack(spacing: 16) {
                trackChip(title: "夜间模式（压缩动态）", isSelected: settings.nightModeEnabled) {
                    settings.nightModeEnabled.toggle()
                    controller.applyAudioShaping()
                }

                trackChip(title: "响度均衡 (-20 LUFS)", isSelected: settings.loudnessNormalizeEnabled) {
                    settings.loudnessNormalizeEnabled.toggle()
                    controller.applyAudioShaping()
                }

                ForEach(AudioBridgePreference.allCases) { mode in
                    trackChip(title: mode.rawValue, isSelected: settings.audioBridgePreference == mode) {
                        settings.audioBridgePreference = mode
                        controller.applyDecodePreferenceLive()
                    }
                }
            }
        }
    }

    // MARK: - 视频与解码面板

    private var videoTabContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("解码通道（当前：\(engine.activeVideoDecoder ?? "自动")）")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.75))

                HStack(spacing: 14) {
                    ForEach(DecodePreference.allCases) { pref in
                        trackChip(title: pref.rawValue, isSelected: settings.decodePreference == pref) {
                            settings.decodePreference = pref
                            controller.applyDecodePreferenceLive()
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("画面比例与杜比视界")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.75))

                HStack(spacing: 14) {
                    ForEach(VideoAspectMode.allCases) { mode in
                        trackChip(title: mode.rawValue, isSelected: settings.aspectMode == mode) {
                            settings.aspectMode = mode
                            controller.applyVideoGravity()
                        }
                    }

                    ForEach(DolbyVisionMode.allCases) { dv in
                        trackChip(title: dv.rawValue, isSelected: settings.dolbyVisionMode == dv) {
                            settings.dolbyVisionMode = dv
                            controller.applyDecodePreferenceLive()
                        }
                    }

                    trackChip(title: "低清 SDR 超分放大", isSelected: settings.upscaleLowResSDR) {
                        settings.upscaleLowResSDR.toggle()
                        controller.applyDecodePreferenceLive()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("播放倍速")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.75))

                HStack(spacing: 12) {
                    ForEach([Float(0.5), 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        trackChip(
                            title: rate == 1.0 ? "1.0x 原速" : String(format: "%.2gx", rate),
                            isSelected: abs(controller.playbackRate - rate) < 0.01
                        ) {
                            controller.setRate(rate)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 章节与工具面板

    private var chaptersAndToolsTabContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                trackChip(title: "跳过片头 (+\(settings.skipIntroSeconds)s)", isSelected: false) {
                    controller.skipIntro()
                    onDismiss()
                }

                if controller.hasNextEpisode {
                    trackChip(title: "播放下一集", isSelected: false) {
                        controller.playNextEpisode()
                        onDismiss()
                    }
                }

                trackChip(title: "实时码率/解码 HUD", isSelected: settings.showStatsHUD) {
                    settings.showStatsHUD.toggle()
                }
            }

            // 睡眠定时器
            VStack(alignment: .leading, spacing: 10) {
                Text(controller.sleepTimerRemainingMinutes > 0
                     ? "睡眠定时（剩余 \(controller.sleepTimerRemainingMinutes) 分钟）"
                     : "睡眠定时")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.75))

                HStack(spacing: 12) {
                    ForEach(SleepTimerOption.allCases) { opt in
                        trackChip(
                            title: opt.label,
                            isSelected: controller.sleepTimerRemainingMinutes == opt.rawValue && opt.rawValue > 0
                        ) {
                            controller.setSleepTimer(minutes: opt.rawValue)
                        }
                    }
                }
            }

            // 章节列表（容器章节或蓝光/DVD 章节）
            let chapters = engine.mediaChapters.isEmpty ? engine.discChapters : engine.mediaChapters
            if !chapters.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("章节跳转")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.75))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(chapters, id: \.id) { ch in
                                trackChip(
                                    title: "\(ch.name) (\(BottomAppleProgressBar.formatTimestamp(ch.startSeconds)))",
                                    isSelected: false
                                ) {
                                    if !engine.discChapters.isEmpty {
                                        engine.selectChapter(id: ch.id)
                                    } else {
                                        Task { await engine.seek(to: ch.startSeconds) }
                                    }
                                    onDismiss()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 通用控件

    private func trackChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            AppleTVSoundEffects.playSelect()
            action()
        } label: {
            HStack(spacing: 8) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Text(title)
                    .font(.system(size: 20, weight: .medium))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                isSelected ? Color.white.opacity(0.26) : Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func stepperCard(
        title: String,
        valueText: String,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(valueText)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            Spacer()

            Button {
                AppleTVSoundEffects.playFocusTick()
                onDecrement()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 32))
            }
            .buttonStyle(.plain)

            Button {
                AppleTVSoundEffects.playFocusTick()
                onIncrement()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(minWidth: 320)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formatTrackLabel(_ track: TrackInfo) -> String {
        var parts: [String] = []
        if !track.name.isEmpty {
            parts.append(track.name)
        } else if let lang = track.language, !lang.isEmpty {
            parts.append(lang.uppercased())
        } else {
            parts.append("字幕 #\(track.id)")
        }
        if !track.codec.isEmpty {
            parts.append("[\(track.codec.uppercased())]")
        }
        if track.isExternal { parts.append("外挂") }
        if track.isForced { parts.append("强制") }
        return parts.joined(separator: " ")
    }

    private func formatAudioTrackLabel(_ track: TrackInfo) -> String {
        var parts: [String] = []
        if !track.name.isEmpty {
            parts.append(track.name)
        } else if let lang = track.language, !lang.isEmpty {
            parts.append(lang.uppercased())
        } else {
            parts.append("音轨 #\(track.id)")
        }
        if !track.codec.isEmpty {
            parts.append(track.codec.uppercased())
        }
        if track.channels > 0 {
            parts.append("\(track.channels)ch")
        }
        if track.isAtmos { parts.append("Atmos") }
        if track.isDTSX { parts.append("DTS:X") }
        return parts.joined(separator: " · ")
    }
}
