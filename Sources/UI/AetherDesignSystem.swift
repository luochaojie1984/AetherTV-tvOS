import SwiftUI

// MARK: - 协议视觉识别体系（图标、宝石渐变色与简洁说明）

extension MediaProtocolType {
    var displayName: String {
        switch self {
        case .smb: return "SMB 共享"
        case .webdav: return "WebDAV"
        case .emby: return "Emby"
        case .jellyfin: return "Jellyfin"
        case .plex: return "Plex"
        case .dlna: return "DLNA"
        case .directURL: return "HTTP 直链"
        }
    }

    var cardSymbolName: String {
        switch self {
        case .smb: return "server.rack"
        case .webdav: return "network"
        case .emby: return "play.tv.fill"
        case .jellyfin: return "sparkles.tv.fill"
        case .plex: return "film.stack.fill"
        case .dlna: return "dot.radiowaves.left.and.right"
        case .directURL: return "link.circle.fill"
        }
    }

    var shortTagline: String {
        switch self {
        case .smb: return "NAS / 群晖 / 飞牛 / Windows 共享"
        case .webdav: return "NAS / AList / OpenList 网盘"
        case .emby: return "直连媒体库与进度同步"
        case .jellyfin: return "开源媒体服与特效字幕"
        case .plex: return "Plex 影库与跨端续播"
        case .dlna: return "局域网 UPnP 免账号目录"
        case .directURL: return "直链视频 / HLS / 直播流"
        }
    }

    var accentColor: Color {
        switch self {
        case .smb: return Color(red: 0.22, green: 0.72, blue: 1.0)
        case .webdav: return Color(red: 0.14, green: 0.84, blue: 0.78)
        case .emby: return Color(red: 0.26, green: 0.85, blue: 0.45)
        case .jellyfin: return Color(red: 0.64, green: 0.44, blue: 1.0)
        case .plex: return Color(red: 0.98, green: 0.72, blue: 0.18)
        case .dlna: return Color(red: 0.98, green: 0.46, blue: 0.26)
        case .directURL: return Color(red: 0.44, green: 0.56, blue: 1.0)
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .smb:
            return [Color(red: 0.12, green: 0.42, blue: 0.96), Color(red: 0.08, green: 0.76, blue: 0.96)]
        case .webdav:
            return [Color(red: 0.06, green: 0.58, blue: 0.58), Color(red: 0.16, green: 0.86, blue: 0.82)]
        case .emby:
            return [Color(red: 0.08, green: 0.62, blue: 0.28), Color(red: 0.28, green: 0.86, blue: 0.44)]
        case .jellyfin:
            return [Color(red: 0.46, green: 0.24, blue: 0.94), Color(red: 0.22, green: 0.74, blue: 0.98)]
        case .plex:
            return [Color(red: 0.86, green: 0.46, blue: 0.06), Color(red: 0.98, green: 0.78, blue: 0.22)]
        case .dlna:
            return [Color(red: 0.88, green: 0.30, blue: 0.14), Color(red: 0.98, green: 0.52, blue: 0.36)]
        case .directURL:
            return [Color(red: 0.30, green: 0.34, blue: 0.92), Color(red: 0.24, green: 0.74, blue: 0.98)]
        }
    }
}

// MARK: - 影院级动态极光背景

struct AetherAmbientBackdrop: View {
    var accent: Color = Color(red: 0.20, green: 0.70, blue: 1.0)
    @State private var animateGlow = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.11),
                    Color(red: 0.06, green: 0.08, blue: 0.16),
                    Color(red: 0.03, green: 0.04, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 左侧流光主极光
            RadialGradient(
                colors: [accent.opacity(0.24), accent.opacity(0.06), Color.clear],
                center: animateGlow ? UnitPoint(x: 0.20, y: 0.14) : UnitPoint(x: 0.14, y: 0.20),
                startRadius: 20,
                endRadius: 680
            )

            // 右下影院紫蓝氛围光
            RadialGradient(
                colors: [
                    Color(red: 0.48, green: 0.28, blue: 0.96).opacity(0.19),
                    Color(red: 0.20, green: 0.14, blue: 0.52).opacity(0.06),
                    Color.clear
                ],
                center: animateGlow ? UnitPoint(x: 0.84, y: 0.80) : UnitPoint(x: 0.88, y: 0.72),
                startRadius: 30,
                endRadius: 720
            )
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                animateGlow = true
            }
        }
    }
}

// MARK: - 立体玻璃图标徽章

struct AetherIconMedallion: View {
    let systemName: String
    let colors: [Color]
    var size: CGFloat = 68
    var iconScale: CGFloat = 0.46

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.32), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.2)
                )
                .shadow(color: (colors.first ?? .blue).opacity(0.45), radius: 14, x: 0, y: 6)

            Image(systemName: systemName)
                .font(.system(size: size * iconScale, weight: .semibold))
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.28), radius: 4, x: 0, y: 2)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 焦点感知高对比度胶囊按钮（聚焦白底深字，绝不白底白字）

struct AetherPillButtonStyle: ButtonStyle {
    var accent: Color = Color(red: 0.22, green: 0.74, blue: 1.0)
    var isSelected: Bool = false
    var prominent: Bool = false
    var cornerRadius: CGFloat = 16
    var horizontalPadding: CGFloat = 22
    var verticalPadding: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        AetherPillButtonBody(
            configuration: configuration,
            accent: accent,
            isSelected: isSelected,
            prominent: prominent,
            cornerRadius: cornerRadius,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )
    }
}

private struct AetherPillButtonBody: View {
    @Environment(\.isFocused) private var isFocused
    let configuration: ButtonStyle.Configuration
    let accent: Color
    let isSelected: Bool
    let prominent: Bool
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    private var foregroundInk: Color {
        if isFocused {
            return Color(red: 0.05, green: 0.07, blue: 0.13)
        }
        return Color.white
    }

    var body: some View {
        configuration.label
            .foregroundStyle(foregroundInk)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundFill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 2 : (isSelected ? 1.5 : 1))
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.06 : 1.0))
            .shadow(
                color: isFocused ? accent.opacity(0.45) : Color.black.opacity(0.25),
                radius: isFocused ? 22 : 8,
                x: 0,
                y: isFocused ? 10 : 4
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.74), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: isFocused) { _, focused in
                if focused {
                    AppleTVSoundEffects.playFocusTick()
                }
            }
    }

    @ViewBuilder
    private var backgroundFill: some View {
        if isFocused {
            Color.white
        } else if prominent {
            LinearGradient(
                colors: [accent, accent.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if isSelected {
            LinearGradient(
                colors: [accent.opacity(0.32), accent.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color.white.opacity(0.10)
        }
    }

    private var borderColor: Color {
        if isFocused { return Color.white }
        if isSelected || prominent { return accent.opacity(0.85) }
        return Color.white.opacity(0.18)
    }
}

// MARK: - 焦点感知影院玻璃聚焦卡（深色流光玻璃 + 聚焦亮边与光晕，保证文字恒定高对比度）

struct AetherSpotlightCardStyle: ButtonStyle {
    var accent: Color = Color(red: 0.22, green: 0.74, blue: 1.0)
    var isSelected: Bool = false
    var cornerRadius: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        AetherSpotlightCardBody(
            configuration: configuration,
            accent: accent,
            isSelected: isSelected,
            cornerRadius: cornerRadius
        )
    }
}

private struct AetherSpotlightCardBody: View {
    @Environment(\.isFocused) private var isFocused
    let configuration: ButtonStyle.Configuration
    let accent: Color
    let isSelected: Bool
    let cornerRadius: CGFloat

    var body: some View {
        configuration.label
            .foregroundStyle(Color.white)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            isFocused
                                ? Color(red: 0.11, green: 0.15, blue: 0.27)
                                : (isSelected ? Color(red: 0.10, green: 0.14, blue: 0.24) : Color(red: 0.08, green: 0.10, blue: 0.17).opacity(0.86))
                        )
                    if isFocused || isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accent.opacity(isFocused ? 0.34 : 0.18),
                                        accent.opacity(isFocused ? 0.10 : 0.04),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    // 顶部玻璃反光高光
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isFocused ? 0.16 : 0.06), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: isFocused
                                ? [Color.white.opacity(0.95), accent.opacity(0.92)]
                                : (isSelected
                                    ? [accent.opacity(0.85), accent.opacity(0.35)]
                                    : [Color.white.opacity(0.18), Color.white.opacity(0.06)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isFocused ? 2.5 : (isSelected ? 1.6 : 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.045 : 1.0))
            .shadow(
                color: isFocused ? accent.opacity(0.46) : Color.black.opacity(0.34),
                radius: isFocused ? 28 : 12,
                x: 0,
                y: isFocused ? 14 : 6
            )
            .animation(.spring(response: 0.30, dampingFraction: 0.74), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: isFocused) { _, focused in
                if focused {
                    AppleTVSoundEffects.playFocusTick()
                }
            }
    }
}

// MARK: - 影院海报卡片样式

struct AetherPosterCardStyle: ButtonStyle {
    var accent: Color = Color(red: 0.24, green: 0.78, blue: 1.0)
    var cornerRadius: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        AetherPosterCardBody(configuration: configuration, accent: accent, cornerRadius: cornerRadius)
    }
}

private struct AetherPosterCardBody: View {
    @Environment(\.isFocused) private var isFocused
    let configuration: ButtonStyle.Configuration
    let accent: Color
    let cornerRadius: CGFloat

    var body: some View {
        configuration.label
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: isFocused
                                ? [Color.white, accent.opacity(0.9)]
                                : [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isFocused ? 3 : 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.06 : 1.0))
            .shadow(
                color: isFocused ? accent.opacity(0.48) : Color.black.opacity(0.45),
                radius: isFocused ? 30 : 12,
                x: 0,
                y: isFocused ? 16 : 6
            )
            .animation(.spring(response: 0.30, dampingFraction: 0.74), value: isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused {
                    AppleTVSoundEffects.playFocusTick()
                }
            }
    }
}

// MARK: - 高对比度可聚焦开关卡与选项卡（替代易白底白字的 Form Toggle / Picker）

struct AetherToggleCard: View {
    let icon: String
    var colors: [Color] = [Color(red: 0.16, green: 0.56, blue: 0.98), Color(red: 0.22, green: 0.82, blue: 0.98)]
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Button {
            AppleTVSoundEffects.playSelect()
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 20) {
                AetherIconMedallion(systemName: icon, colors: colors, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.white)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.66))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 16)
                // 清晰的发光胶囊状态指示器
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule(style: .continuous)
                        .fill(isOn ? Color.green : Color.white.opacity(0.20))
                        .frame(width: 78, height: 42)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 34, height: 34)
                        .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)
                        .padding(4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .buttonStyle(AetherSpotlightCardStyle(accent: colors.first ?? .cyan, isSelected: isOn, cornerRadius: 20))
    }
}

struct AetherCycleOptionCard: View {
    let icon: String
    var colors: [Color] = [Color(red: 0.36, green: 0.44, blue: 0.98), Color(red: 0.22, green: 0.78, blue: 0.98)]
    let title: String
    let valueText: String
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            AppleTVSoundEffects.playSelect()
            action()
        } label: {
            HStack(spacing: 20) {
                AetherIconMedallion(systemName: icon, colors: colors, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.white)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.66))
                    }
                }
                Spacer(minLength: 16)
                HStack(spacing: 10) {
                    Text(valueText)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color(red: 0.54, green: 0.88, blue: 1.0))
                        .lineLimit(1)
                    Image(systemName: "chevron.left.chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.10), in: Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .buttonStyle(AetherSpotlightCardStyle(accent: colors.first ?? .cyan, cornerRadius: 20))
    }
}

struct AetherSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color(red: 0.36, green: 0.84, blue: 1.0))
            }
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.white)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            Spacer()
        }
    }
}
