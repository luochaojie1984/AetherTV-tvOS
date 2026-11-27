import SwiftUI
import AetherEngine

/// 苹果原生 Liquid Glass 风格贴底极简进度条（处于安全区最底部，不超出 TV 过扫描边界）
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
            // 留足安全边距：外边距 56*2 + 内边距 28*2，保证进度条、文字与预览气泡永不超出屏幕
            let barWidth = max(geo.size.width - 168, 240)
            let thumbX = barWidth * progressFraction

            VStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    // 实时画面预览浮窗（仅在长按变速 / 暂停触控微调时显示，紧随进度指示点）
                    if scrubEngine.isScrubbing {
                        previewThumbnailBubble(barWidth: barWidth, thumbX: thumbX)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                    }

                    // 苹果原生 Liquid Glass 贴底胶囊条
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(title)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)

                            if let subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.70))
                                    .lineLimit(1)
                            }

                            formatBadges

                            Spacer()

                            if scrubEngine.isScrubbing {
                                speedCapsuleBadge
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.down.circle.fill")
                                    Text("下键：字幕与设置")
                                }
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.78))
                            }
                        }

                        // Liquid Glass 进度轨道
                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.24))
                                .frame(height: scrubEngine.isScrubbing ? 11 : 7)

                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.42))
                                .frame(width: barWidth * bufferedFraction, height: scrubEngine.isScrubbing ? 11 : 7)

                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.45, green: 0.88, blue: 1.0), Color.white],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(thumbX, 0), height: scrubEngine.isScrubbing ? 11 : 7)
                                .shadow(color: Color.cyan.opacity(0.50), radius: 6, x: 0, y: 0)

                            ForEach(engine.mediaChapters, id: \.id) { chapter in
                                let frac = min(max(chapter.startSeconds / duration, 0), 1)
                                if frac > 0.01 && frac < 0.99 {
                                    Circle()
                                        .fill(Color.black.opacity(0.55))
                                        .frame(width: 4, height: 4)
                                        .offset(x: barWidth * frac - 2)
                                }
                            }

                            Capsule(style: .continuous)
                                .fill(Color.white)
                                .frame(
                                    width: scrubEngine.isScrubbing ? 6 : 4,
                                    height: scrubEngine.isScrubbing ? 22 : 16
                                )
                                .shadow(color: Color.black.opacity(0.55), radius: 4, x: 0, y: 1)
                                .offset(x: max(0, min(barWidth - 4, thumbX - 2)))
                        }
                        .frame(width: barWidth, height: 22)
                        .animation(.easeOut(duration: 0.12), value: scrubEngine.isScrubbing)

                        HStack {
                            Text(Self.formatTimestamp(displayTime))
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Color.white.opacity(0.94))

                            Spacer()

                            if engine.playbackPhase == .rebuffering || engine.playbackPhase == .loading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("正在缓冲…")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(Color.white.opacity(0.78))
                                }
                            }

                            Spacer()

                            Text("-\(Self.formatTimestamp(max(duration - displayTime, 0)))")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Color.white.opacity(0.74))
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(Color.black.opacity(0.28))
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.42), Color.white.opacity(0.10)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 10)
                }
                .padding(.horizontal, 56)
                .padding(.bottom, 16)
            }
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
                        Color.black.opacity(0.68)
                        VStack(spacing: 8) {
                            Image(systemName: scrubEngine.direction.symbolName)
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.85))
                            Text(Self.formatTimestamp(scrubEngine.scrubTime))
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(width: previewWidth, height: previewHeight)
                }

                HStack(spacing: 6) {
                    Image(systemName: scrubEngine.isFineScrubbing ? "hand.draw.fill" : scrubEngine.direction.symbolName)
                        .font(.system(size: 14, weight: .bold))
                    Text(scrubEngine.isFineScrubbing ? "精调" : "\(Int(scrubEngine.speedMultiplier.rounded()))x")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.55), Color.white.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: Color.black.opacity(0.55), radius: 18, x: 0, y: 10)
        }
        .padding(.leading, 28)
        .offset(x: clampedX)
    }

    private var speedCapsuleBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: scrubEngine.isFineScrubbing ? "hand.draw.fill" : scrubEngine.direction.symbolName)
            Text(scrubEngine.isFineScrubbing ? "触控精调预览" : "\(Int(scrubEngine.speedMultiplier.rounded()))x 实时预览")
                .monospacedDigit()
        }
        .font(.system(size: 19, weight: .semibold, design: .rounded))
        .foregroundStyle(Color.black)
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
            .foregroundStyle(Color.white.opacity(0.92))
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
