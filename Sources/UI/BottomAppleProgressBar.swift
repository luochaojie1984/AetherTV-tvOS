import SwiftUI
import AetherEngine

/// 极简苹果原生风格进度条，贴近屏幕最底部（最小底边距）
/// 独立观察 `PlaybackClock` 与 `AdaptiveScrubEngine`，避免 10Hz/60Hz 刷新导致主菜单重绘
struct BottomAppleProgressBar: View {
    @ObservedObject var engine: AetherEngine
    @ObservedObject var clock: PlaybackClock
    @ObservedObject var scrubEngine: AdaptiveScrubEngine
    let title: String
    let subtitle: String?
    let onOpenSettings: () -> Void
    let onSkipIntro: () -> Void
    let onNextEpisode: (() -> Void)?

    private var displayTime: Double {
        scrubEngine.isScrubbing ? scrubEngine.scrubTime : clock.currentTime
    }

    private var duration: Double {
        max(engine.duration, 1)
    }

    private var progressFraction: Double {
        min(max(displayTime / duration, 0), 1)
    }

    private var bufferedFraction: Double {
        min(max(clock.bufferedPosition / duration, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let barWidth = max(geo.size.width - 96, 200)
            let thumbX = barWidth * progressFraction

            VStack(spacing: 0) {
                Spacer()

                // 底部渐变暗角，保证进度条在亮画面下也具备苹果原生级可读性
                VStack(alignment: .leading, spacing: 10) {
                    // 实时画面预览浮窗（仅在长按变速快进/快退时显示，位置紧随进度指示点）
                    if scrubEngine.isScrubbing {
                        previewThumbnailBubble(barWidth: barWidth, thumbX: thumbX)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                    }

                    // 标题与原生胶囊徽章行（紧贴进度条上方）
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(title)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.white.opacity(0.68))
                                .lineLimit(1)
                        }

                        formatBadges

                        Spacer()

                        // 快捷提示（按下键唤出控制面板，长按左右键顺滑变速）
                        HStack(spacing: 16) {
                            if scrubEngine.isScrubbing {
                                speedCapsuleBadge
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.down.circle.fill")
                                    Text("设置与字幕")
                                }
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }

                    // 苹果原生风格细长胶囊进度条
                    ZStack(alignment: .leading) {
                        // 底轨
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.30))
                            .frame(height: scrubEngine.isScrubbing ? 11 : 7)

                        // 缓冲轨
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.46))
                            .frame(width: barWidth * bufferedFraction, height: scrubEngine.isScrubbing ? 11 : 7)

                        // 已播进度轨
                        Capsule(style: .continuous)
                            .fill(Color.white)
                            .frame(width: max(thumbX, 0), height: scrubEngine.isScrubbing ? 11 : 7)
                            .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 0)

                        // 章节刻度点
                        ForEach(engine.mediaChapters, id: \.id) { chapter in
                            let frac = min(max(chapter.startSeconds / duration, 0), 1)
                            if frac > 0.01 && frac < 0.99 {
                                Circle()
                                    .fill(Color.black.opacity(0.55))
                                    .frame(width: 4, height: 4)
                                    .offset(x: barWidth * frac - 2)
                            }
                        }

                        // 原生白色竖条/圆点指示器
                        Capsule(style: .continuous)
                            .fill(Color.white)
                            .frame(
                                width: scrubEngine.isScrubbing ? 6 : 4,
                                height: scrubEngine.isScrubbing ? 22 : 16
                            )
                            .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)
                            .offset(x: max(0, min(barWidth - 4, thumbX - 2)))
                    }
                    .frame(width: barWidth, height: 22)
                    .animation(.easeOut(duration: 0.12), value: scrubEngine.isScrubbing)

                    // 时间行（左已播，右剩余，等宽数字）
                    HStack {
                        Text(Self.formatTimestamp(displayTime))
                            .font(.system(size: 22, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.92))

                        Spacer()

                        if engine.playbackPhase == .rebuffering || engine.playbackPhase == .loading {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("正在缓冲…")
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }

                        Spacer()

                        Text("-\(Self.formatTimestamp(max(duration - displayTime, 0)))")
                            .font(.system(size: 22, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 40)
                // 刻意贴近屏幕最底部（配合 ignoresSafeArea(.bottom)），留出过扫描余量
                .padding(.bottom, 24)
                .background(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.0),
                            Color.black.opacity(0.62),
                            Color.black.opacity(0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    // MARK: - 实时预览缩略图浮窗

    @ViewBuilder
    private func previewThumbnailBubble(barWidth: CGFloat, thumbX: CGFloat) -> some View {
        let previewWidth: CGFloat = 340
        let previewHeight: CGFloat = 192
        let clampedX = min(max(thumbX - previewWidth / 2, 0), max(barWidth - previewWidth, 0))

        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                if let uiImage = scrubEngine.previewUIImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: previewWidth, height: previewHeight)
                        .clipped()
                } else {
                    ZStack {
                        Color.black.opacity(0.72)
                        VStack(spacing: 8) {
                            Image(systemName: scrubEngine.direction.symbolName)
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                            Text(Self.formatTimestamp(scrubEngine.scrubTime))
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: previewWidth, height: previewHeight)
                }

                // 预览浮窗右下角同步显示倍速与时间
                HStack(spacing: 6) {
                    Image(systemName: scrubEngine.isFineScrubbing ? "hand.draw.fill" : scrubEngine.direction.symbolName)
                        .font(.system(size: 14, weight: .bold))
                    Text(scrubEngine.isFineScrubbing ? "精调" : "\(Int(scrubEngine.speedMultiplier.rounded()))x")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.65), radius: 18, x: 0, y: 10)
        }
        .offset(x: clampedX)
    }

    private var speedCapsuleBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: scrubEngine.isFineScrubbing ? "hand.draw.fill" : scrubEngine.direction.symbolName)
            Text(scrubEngine.isFineScrubbing ? "触控精调预览" : "\(Int(scrubEngine.speedMultiplier.rounded()))x 实时预览")
                .monospacedDigit()
        }
        .font(.system(size: 20, weight: .semibold, design: .rounded))
        .foregroundStyle(.black)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color.white, in: Capsule())
    }

    @ViewBuilder
    private var formatBadges: some View {
        HStack(spacing: 8) {
            switch engine.videoFormat {
            case .dolbyVision:
                badge("Dolby Vision")
            case .hdr10Plus:
                badge("HDR10+")
            case .hdr10:
                badge("HDR10")
            case .hlg:
                badge("HLG")
            case .sdr:
                EmptyView()
            @unknown default:
                EmptyView()
            }

            if let codec = engine.sourceVideoCodecName?.uppercased() {
                badge(codec)
            }

            if engine.audioTracks.first(where: { $0.id == engine.activeAudioTrackIndex })?.isAtmos == true {
                badge("Dolby Atmos")
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    static func formatTimestamp(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
