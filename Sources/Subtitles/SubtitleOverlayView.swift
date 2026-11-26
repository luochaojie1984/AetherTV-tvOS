import SwiftUI
import AetherEngine

/// 特效字幕渲染层：
/// - 严格对齐 `engine.clock.$sourceTime`（扣除用户设定的字幕时间偏移）
/// - 支持纯文本（SRT/VTT）、富文本 ASS 特效样式（颜色/粗体/斜体/下划线/删除线/ASS 九宫格定位）与图形字幕（PGS/DVB/DVD）
/// - 支持主副双语字幕同时渲染
struct SubtitleOverlayView: View {
    @ObservedObject var engine: AetherEngine
    @ObservedObject var clock: PlaybackClock
    @ObservedObject var settings: PlayerSettingsStore

    var body: some View {
        let effectiveTime = clock.sourceTime - settings.subtitleDelaySeconds
        let activePrimary = engine.subtitleCues.filter {
            effectiveTime >= $0.startTime && effectiveTime <= $0.endTime
        }
        let activeSecondary = engine.secondarySubtitleCues.filter {
            effectiveTime >= $0.startTime && effectiveTime <= $0.endTime
        }

        GeometryReader { geo in
            ZStack {
                // 1. 图形字幕层（PGS / DVB / DVD）
                ForEach(activePrimary, id: \.id) { cue in
                    if case .image(let img) = cue.body {
                        bitmapSubtitleView(img, containerSize: geo.size)
                    }
                }

                // 2. 定位型 ASS 特效字幕（携带显式 placement 锚点）
                ForEach(activePrimary, id: \.id) { cue in
                    if let placement = cue.placement, let pos = placement.position {
                        styledCueText(cue, scale: 1.0)
                            .position(
                                x: CGFloat(pos.x) * geo.size.width,
                                y: CGFloat(pos.y) * geo.size.height
                            )
                    }
                }

                // 3. 常规底部（或九宫格顶部）字幕堆叠层
                VStack(spacing: 8) {
                    if settings.secondarySubtitleAtTop && !activeSecondary.isEmpty {
                        VStack(spacing: 4) {
                            ForEach(activeSecondary, id: \.id) { cue in
                                styledCueText(cue, scale: 0.84)
                            }
                        }
                        .padding(.top, 36)
                    }

                    Spacer()

                    if !settings.secondarySubtitleAtTop && !activeSecondary.isEmpty {
                        VStack(spacing: 4) {
                            ForEach(activeSecondary, id: \.id) { cue in
                                styledCueText(cue, scale: 0.82)
                            }
                        }
                        .padding(.bottom, 4)
                    }

                    VStack(spacing: 6) {
                        ForEach(activePrimary.filter { $0.placement?.position == nil }, id: \.id) { cue in
                            switch cue.body {
                            case .text, .richText:
                                styledCueText(cue, scale: 1.0)
                            case .image:
                                EmptyView()
                            }
                        }
                    }
                    .padding(.bottom, CGFloat(settings.subtitleBottomOffset))
                }
                .frame(maxWidth: geo.size.width * 0.88)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func styledCueText(_ cue: SubtitleCue, scale: Double) -> some View {
        let baseFontSize = CGFloat(settings.subtitleFontSize * scale)

        Group {
            switch cue.body {
            case .text(let plain):
                Text(plain)
                    .font(.system(size: baseFontSize, weight: .semibold, design: .default))
                    .foregroundStyle(settings.subtitleColor.swiftUIColor)
            case .richText(let runs):
                buildRichText(runs: runs, baseSize: baseFontSize)
            case .image:
                EmptyView()
            }
        }
        .multilineTextAlignment(.center)
        .lineSpacing(4)
        .padding(.horizontal, settings.subtitleBackgroundOpacity > 0.01 ? 18 : 6)
        .padding(.vertical, settings.subtitleBackgroundOpacity > 0.01 ? 8 : 2)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(settings.subtitleBackgroundOpacity))
        )
        .shadow(
            color: settings.subtitleShadowEnabled ? Color.black.opacity(0.9) : .clear,
            radius: settings.subtitleStrokeEnabled ? 3 : 6,
            x: 0,
            y: 2
        )
        .shadow(
            color: settings.subtitleStrokeEnabled ? Color.black.opacity(0.95) : .clear,
            radius: 1.2,
            x: 0,
            y: 0
        )
    }

    private func buildRichText(runs: [SubtitleTextRun], baseSize: CGFloat) -> Text {
        runs.reduce(Text("")) { partial, run in
            let size: CGFloat
            if settings.preserveASSStyling, let runSize = run.fontSize, runSize > 0 {
                // 将 ASS 逻辑字号适度映射到 1080p tvOS 视觉尺度
                size = max(24, min(88, CGFloat(runSize) * (baseSize / 46.0)))
            } else {
                size = baseSize
            }

            var t = Text(run.text)
                .font(.system(
                    size: size,
                    weight: run.isBold ? .bold : .semibold,
                    design: .default
                ))

            if run.isItalic { t = t.italic() }
            if run.isUnderlined { t = t.underline() }
            if run.isStruckThrough { t = t.strikethrough() }

            if settings.preserveASSStyling, let c = run.color {
                t = t.foregroundColor(Color(
                    red: Double(c.r) / 255.0,
                    green: Double(c.g) / 255.0,
                    blue: Double(c.b) / 255.0
                ))
            } else {
                t = t.foregroundColor(settings.subtitleColor.swiftUIColor)
            }

            return partial + t
        }
    }

    @ViewBuilder
    private func bitmapSubtitleView(_ img: SubtitleImage, containerSize: CGSize) -> some View {
        let uiImage = UIImage(cgImage: img.cgImage)
        let canvasW = img.canvasSize.width > 0 ? img.canvasSize.width : CGFloat(img.cgImage.width)
        let canvasH = img.canvasSize.height > 0 ? img.canvasSize.height : CGFloat(img.cgImage.height)
        let scaleX = containerSize.width / max(canvasW, 1)
        let scaleY = containerSize.height / max(canvasH, 1)
        let drawW = CGFloat(img.cgImage.width) * scaleX
        let drawH = CGFloat(img.cgImage.height) * scaleY
        let posX = img.position.minX * containerSize.width + drawW / 2
        let posY = img.position.minY * containerSize.height + drawH / 2

        Image(uiImage: uiImage)
            .resizable()
            .interpolation(.high)
            .frame(width: drawW, height: drawH)
            .position(x: posX, y: posY)
    }
}
