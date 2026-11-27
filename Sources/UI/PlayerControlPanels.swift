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
        case .subtitles: return "captions.bubble.fill"
        case .audio: return "speaker.wave.3.fill"
        case .video: return "sparkles.tv.fill"
        case .chapters: return "list.bullet.rectangle.fill"
        }
    }

    var accent: Color {
        switch self {
        case .subtitles: return Color(red: 0.32, green: 0.78, blue: 1.0)
        case .audio: return Color(red: 0.22, green: 0.86, blue: 0.56)
        case .video: return Color(red: 0.64, green: 0.44, blue: 1.0)
        case .chapters: return Color(red: 0.98, green: 0.72, blue: 0.22)
        }
    }
}

/// 苹果原生 Liquid Glass 风格播放器快捷控制面板（按下方向键唤出；显式 FocusState + focusSection 保证遥控器顺畅选择字幕等选项，且不超出画面边界）
struct PlayerControlPanels: View {
    private enum PanelFocus: Hashable {
        case tab(PlayerPanelTab)
        case done
    }

    @ObservedObject var controller: PlaybackController
    @ObservedObject var engine: AetherEngine
    @ObservedObject var settings: PlayerSettingsStore
    let onDismiss: () -> Void

    @State private var selectedTab: PlayerPanelTab = .subtitles
    @FocusState private var focusedItem: PanelFocus?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                // 顶部苹果风格分段标签栏（独立 focusSection，按下方向键直达下方选项）
                HStack(spacing: 16) {
                    ForEach(PlayerPanelTab.allCases) { tab in
                        Button {
                            AppleTVSoundEffects.playSelect()
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedTab = tab
                            }
                        } label: {
                            Label(tab.rawValue, systemImage: tab.icon)
                                .font(.system(size: 22, weight: .semibold))
                        }
                        .buttonStyle(AetherPillButtonStyle(
                            accent: tab.accent,
                            isSelected: selectedTab == tab,
                            cornerRadius: 24,
                            horizontalPadding: 24,
                            verticalPadding: 12
                        ))
                        .focused($focusedItem, equals: .tab(tab))
                    }

                    Spacer()

                    Button {
                        AppleTVSoundEffects.playBack()
                        onDismiss()
                    } label: {
                        Label("完成", systemImage: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                    }
                    .buttonStyle(AetherPillButtonStyle(
                        accent: .white,
                        cornerRadius: 24,
                        horizontalPadding: 22,
                        verticalPadding: 12
                    ))
                    .focused($focusedItem, equals: .done)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .focusSection()

                Divider().overlay(Color.white.opacity(0.20))

                ScrollView(.vertical, showsIndicators: false) {
                    Group {
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
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .frame(maxHeight: 420)
                .focusSection()
            }
            .padding(28)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(Color(red: 0.05, green: 0.07, blue: 0.13).opacity(0.62))
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [selectedTab.accent.opacity(0.14), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.42), selectedTab.accent.opacity(0.22), Color.white.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.3
                    )
            )
            .shadow(color: Color.black.opacity(0.65), radius: 36, x: 0, y: 16)
            .padding(.horizontal, 56)
            .padding(.bottom, 22)
        }
        .background(Color.black.opacity(0.42).ignoresSafeArea())
        .onAppear {
            AppleTVSoundEffects.playPanelOpen()
            // 主动将遥控器焦点引导至当前面板标签栏，确保从播放器按确定/下键进入后可立即左右上下选择字幕与音轨
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                focusedItem = .tab(selectedTab)
            }
        }
    }

    // MARK: - 字幕设置面板

    private var subtitleTabContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("主字幕轨道")
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(0.75))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        trackChip(title: "关闭字幕", isSelected: !engine.isSubtitleActive) {
                            controller.clearPrimarySubtitle()
                        }

                        ForEach(engine.subtitleTracks, id: \.id) { track in
                            trackChip(
                                title: formatTrackLabel(track),
                                isSelected: engine.isSubtitleActive && engine.activeSubtitleTrackIndex == track.id
                            ) {
                                controller.selectPrimarySubtitleTrack(index: track.id)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }
            }

            if engine.subtitleTracks.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("双语副字幕（可选）")
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.75))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            trackChip(title: "关闭副字幕", isSelected: !engine.isSecondarySubtitleActive) {
                                controller.clearSecondarySubtitle()
                            }
                            ForEach(engine.subtitleTracks, id: \.id) { track in
                                trackChip(
                                    title: formatTrackLabel(track),
                                    isSelected: engine.isSecondarySubtitleActive && engine.activeSecondarySubtitleTrackIndex == track.id
                                ) {
                                    controller.selectSecondarySubtitleTrack(index: track.id)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                }
            }

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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
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
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - 音频设置面板

    private var audioTabContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("音轨选择")
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(0.75))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(engine.audioTracks, id: \.id) { track in
                            trackChip(
                                title: formatAudioTrackLabel(track),
                                isSelected: engine.activeAudioTrackIndex == track.id
                            ) {
                                controller.selectAudioTrack(index: track.id)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
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
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - 视频与解码面板

    private var videoTabContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("解码通道（当前：\(engine.activeVideoDecoder ?? "自动")）")
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(0.75))

                HStack(spacing: 14) {
                    ForEach(DecodePreference.allCases) { pref in
                        trackChip(title: pref.rawValue, isSelected: settings.decodePreference == pref) {
                            settings.decodePreference = pref
                            controller.applyDecodePreferenceLive()
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("画面比例与杜比视界")
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(0.75))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(VideoAspectMode.allCases) { mode in
                            trackChip(title: mode.rawValue, isSelected: controller.activeAspectMode == mode) {
                                controller.setAspectMode(mode)
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
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("播放倍速")
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(0.75))

                HStack(spacing: 14) {
                    ForEach([Float(0.5), 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        trackChip(
                            title: rate == 1.0 ? "1.0x 原速" : String(format: "%.2gx", rate),
                            isSelected: abs(controller.playbackRate - rate) < 0.01
                        ) {
                            controller.setRate(rate)
                        }
                    }
                }
                .padding(.vertical, 6)
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
            .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 10) {
                Text(controller.sleepTimerRemainingMinutes > 0
                     ? "睡眠定时（剩余 \(controller.sleepTimerRemainingMinutes) 分钟）"
                     : "睡眠定时")
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(0.75))

                HStack(spacing: 14) {
                    ForEach(SleepTimerOption.allCases) { opt in
                        trackChip(
                            title: opt.label,
                            isSelected: controller.sleepTimerRemainingMinutes == opt.rawValue && opt.rawValue > 0
                        ) {
                            controller.setSleepTimer(minutes: opt.rawValue)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            let chapters = engine.mediaChapters.isEmpty ? engine.discChapters : engine.mediaChapters
            if !chapters.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("章节跳转")
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.75))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
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
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
    }

    // MARK: - 高对比度控件（聚焦自动切白底深字 + 焦点音效）

    private func trackChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            AppleTVSoundEffects.playSelect()
            action()
        } label: {
            HStack(spacing: 8) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                }
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
            }
        }
        .buttonStyle(AetherPillButtonStyle(
            accent: selectedTab.accent,
            isSelected: isSelected,
            cornerRadius: 15,
            horizontalPadding: 20,
            verticalPadding: 12
        ))
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
                    .foregroundStyle(Color.white.opacity(0.70))
                Text(valueText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .monospacedDigit()
            }

            Spacer()

            Button {
                AppleTVSoundEffects.playSelect()
                onDecrement()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 20, weight: .bold))
            }
            .buttonStyle(AetherPillButtonStyle(
                accent: selectedTab.accent,
                cornerRadius: 14,
                horizontalPadding: 14,
                verticalPadding: 10
            ))

            Button {
                AppleTVSoundEffects.playSelect()
                onIncrement()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
            }
            .buttonStyle(AetherPillButtonStyle(
                accent: selectedTab.accent,
                cornerRadius: 14,
                horizontalPadding: 14,
                verticalPadding: 10
            ))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(minWidth: 340)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
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
