import SwiftUI
import UIKit
import AetherEngine

struct PlayerScreenView: View {
    let item: MediaItem
    let playlist: [MediaItem]
    let sourceConfig: MediaSourceConfig?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settings: PlayerSettingsStore
    @StateObject private var controller: PlaybackController

    /// `controller` 可注入，好让冒烟测试从外部观察同一个播放会话
    init(item: MediaItem, playlist: [MediaItem], sourceConfig: MediaSourceConfig?, controller: PlaybackController? = nil) {
        self.item = item
        self.playlist = playlist
        self.sourceConfig = sourceConfig
        _controller = StateObject(wrappedValue: controller ?? PlaybackController())
    }

    @State private var showOverlay = true
    @State private var showControlPanel = false
    @State private var hideOverlayTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let engine = controller.engine {
                // 1. AetherEngine 原生渲染层（自动管理 AVPlayerLayer / AVSampleBufferDisplayLayer）
                AetherPlayerSurface(engine: engine)
                    .ignoresSafeArea()

                // 2. 特效字幕 + 图形字幕 + 双语字幕渲染层
                SubtitleOverlayView(
                    engine: engine,
                    clock: engine.clock,
                    settings: settings
                )
                .ignoresSafeArea()

                // 3. Siri Remote 遥控器底层长按/短按/触控板微调捕获层。
                //    控制面板打开时让位给面板按钮；错误浮层出现时也移除，
                //    否则这层会在 pressesBegan 里吞掉方向键，用户无法在「重试/软解/返回」间移动焦点。
                if !showControlPanel && controller.activeErrorMessage == nil {
                    RemotePressCaptureView(
                        onLeftDown: {
                            revealOverlayTemporarily(keepVisible: true)
                            controller.scrubEngine.beginPress(direction: .rewind)
                        },
                        onLeftUp: {
                            controller.scrubEngine.endPress()
                            revealOverlayTemporarily(keepVisible: false)
                        },
                        onRightDown: {
                            revealOverlayTemporarily(keepVisible: true)
                            controller.scrubEngine.beginPress(direction: .forward)
                        },
                        onRightUp: {
                            controller.scrubEngine.endPress()
                            revealOverlayTemporarily(keepVisible: false)
                        },
                        onPlayPause: {
                            controller.togglePlayPause()
                            revealOverlayTemporarily(keepVisible: false)
                        },
                        onSelect: {
                            if !showOverlay {
                                revealOverlayTemporarily(keepVisible: false)
                            } else {
                                controller.togglePlayPause()
                                revealOverlayTemporarily(keepVisible: false)
                            }
                        },
                        onDown: {
                            AppleTVSoundEffects.playSelect()
                            hideOverlayTask?.cancel()
                            showOverlay = false
                            showControlPanel = true
                        },
                        onUp: {
                            AppleTVSoundEffects.playFocusTick()
                            settings.showStatsHUD.toggle()
                        },
                        onMenu: {
                            if controller.scrubEngine.isFineScrubbing {
                                controller.scrubEngine.cancelFineScrub()
                                revealOverlayTemporarily(keepVisible: false)
                            } else if showOverlay && !controller.scrubEngine.isScrubbing {
                                showOverlay = false
                            } else {
                                controller.stopAndDismiss()
                                dismiss()
                            }
                        },
                        onPanBegan: {
                            let started = controller.scrubEngine.beginFineScrub()
                            if started {
                                revealOverlayTemporarily(keepVisible: true)
                            }
                            return started
                        },
                        onPanChanged: { deltaSeconds in
                            controller.scrubEngine.updateFineScrub(deltaSeconds: deltaSeconds)
                        },
                        onPanEnded: {
                            controller.scrubEngine.commitFineScrub()
                            revealOverlayTemporarily(keepVisible: false)
                        },
                        onPanCancelled: {
                            controller.scrubEngine.cancelFineScrub()
                            revealOverlayTemporarily(keepVisible: false)
                        }
                    )
                    .ignoresSafeArea()
                }

                // 4. 1Hz 实时媒体信息 HUD（按上键或在设置中开启）
                if settings.showStatsHUD {
                    VStack {
                        HStack {
                            LiveStatsHUDView(
                                engine: engine,
                                diagnostics: engine.diagnostics
                            )
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(.top, 36)
                    .padding(.leading, 48)
                    .allowsHitTesting(false)
                }

                // 5. 贴底苹果原生风格进度条浮层
                if (showOverlay || controller.scrubEngine.isScrubbing) && !showControlPanel {
                    BottomAppleProgressBar(
                        engine: engine,
                        clock: engine.clock,
                        scrubEngine: controller.scrubEngine,
                        title: controller.currentItem?.title ?? item.title,
                        subtitle: controller.currentItem?.subtitle,
                        onOpenSettings: {
                            showOverlay = false
                            showControlPanel = true
                        },
                        onSkipIntro: { controller.skipIntro() },
                        onNextEpisode: controller.hasNextEpisode ? { controller.playNextEpisode() } : nil
                    )
                    .transition(.opacity)
                }

                // 6. 苹果原生毛玻璃设置面板
                if showControlPanel {
                    PlayerControlPanels(
                        controller: controller,
                        engine: engine,
                        settings: settings,
                        onDismiss: {
                            showControlPanel = false
                            revealOverlayTemporarily(keepVisible: false)
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onExitCommand {
                        showControlPanel = false
                        revealOverlayTemporarily(keepVisible: false)
                    }
                }
            }

            // 7. 错误提示浮层
            if let errorMsg = controller.activeErrorMessage {
                VStack(spacing: 18) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.yellow)
                    Text("播放出现问题")
                        .font(.title2.bold())
                    Text(errorMsg)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 720)
                    HStack(spacing: 20) {
                        if controller.engine != nil {
                            Button("重试") {
                                Task {
                                    await controller.load(item: item, playlist: playlist, sourceConfig: sourceConfig)
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            Button("切软解重试") {
                                settings.decodePreference = .software
                                Task {
                                    await controller.load(item: item, playlist: playlist, sourceConfig: sourceConfig)
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        Button("返回") {
                            controller.stopAndDismiss()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(40)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
        .task {
            await controller.load(item: item, playlist: playlist, sourceConfig: sourceConfig)
            revealOverlayTemporarily(keepVisible: false)
        }
        .onChange(of: scenePhase) { _, newPhase in
            controller.handleScenePhaseChange(newPhase)
        }
        .onChange(of: controller.routeRemovalEventCount) { _, _ in
            revealOverlayTemporarily(keepVisible: false)
        }
        .onDisappear {
            hideOverlayTask?.cancel()
            controller.stopAndDismiss()
        }
    }

    private func revealOverlayTemporarily(keepVisible: Bool) {
        hideOverlayTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            showOverlay = true
        }
        guard !keepVisible else { return }
        hideOverlayTask = Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            if !controller.scrubEngine.isScrubbing && !showControlPanel && controller.engine?.state == .playing {
                withAnimation(.easeInOut(duration: 0.35)) {
                    showOverlay = false
                }
            }
        }
    }
}

// MARK: - 1Hz 实时媒体信息 HUD

private struct LiveStatsHUDView: View {
    @ObservedObject var engine: AetherEngine
    @ObservedObject var diagnostics: EngineDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AetherTV 实时诊断")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            Text("解码：\(engine.activeVideoDecoder ?? "-") | 音频：\(engine.activeAudioDecoder ?? "-")")
            Text("格式：\(String(describing: engine.videoFormat)) | 通道：\(String(describing: engine.videoRoute))")

            // LiveTelemetry 的字段全部是可选值（该时刻没有采样即为 nil），先兜底成 0 再格式化
            if let t = diagnostics.liveTelemetry {
                Text(String(
                    format: "码率：%.1f Mbps | 网速：%.1f Mbps | 缓冲：%.1fs",
                    t.instantBitrateMbps ?? 0,
                    t.networkThroughputMbps ?? 0,
                    t.forwardBufferSeconds ?? 0
                ))
                Text(String(
                    format: "帧率：%.2f fps | 丢帧：%d",
                    t.observedFps ?? 0,
                    t.droppedFrameCount ?? 0
                ))
            }
        }
        .font(.system(size: 15, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Siri Remote 底层按键长按/短按 & 触控板微调捕获器

private struct RemotePressCaptureView: UIViewControllerRepresentable {
    let onLeftDown: () -> Void
    let onLeftUp: () -> Void
    let onRightDown: () -> Void
    let onRightUp: () -> Void
    let onPlayPause: () -> Void
    let onSelect: () -> Void
    let onDown: () -> Void
    let onUp: () -> Void
    let onMenu: () -> Void
    let onPanBegan: () -> Bool
    let onPanChanged: (Double) -> Void
    let onPanEnded: () -> Void
    let onPanCancelled: () -> Void

    func makeUIViewController(context: Context) -> RemotePressViewController {
        let vc = RemotePressViewController()
        updateCallbacks(on: vc)
        return vc
    }

    func updateUIViewController(_ uiViewController: RemotePressViewController, context: Context) {
        updateCallbacks(on: uiViewController)
    }

    private func updateCallbacks(on vc: RemotePressViewController) {
        vc.onLeftDown = onLeftDown
        vc.onLeftUp = onLeftUp
        vc.onRightDown = onRightDown
        vc.onRightUp = onRightUp
        vc.onPlayPause = onPlayPause
        vc.onSelect = onSelect
        vc.onDown = onDown
        vc.onUp = onUp
        vc.onMenu = onMenu
        vc.onPanBegan = onPanBegan
        vc.onPanChanged = onPanChanged
        vc.onPanEnded = onPanEnded
        vc.onPanCancelled = onPanCancelled
    }
}

/// tvOS 的焦点引擎作用于 view 而不是 view controller：
/// 让这个 view 可获焦，按键事件就会沿响应链交给 RemotePressViewController。
private final class RemotePressView: UIView {
    override var canBecomeFocused: Bool { true }
}

private final class RemotePressViewController: UIViewController {
    var onLeftDown: (() -> Void)?
    var onLeftUp: (() -> Void)?
    var onRightDown: (() -> Void)?
    var onRightUp: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onSelect: (() -> Void)?
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?
    var onMenu: (() -> Void)?
    var onPanBegan: (() -> Bool)?
    var onPanChanged: ((Double) -> Void)?
    var onPanEnded: (() -> Void)?
    var onPanCancelled: (() -> Void)?

    private var lastPanX: CGFloat = 0
    private var isPanFineScrubbing = false

    override func loadView() {
        view = RemotePressView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        view.addGestureRecognizer(pan)
    }

    /// 存在期间优先把焦点交给捕获层，避免焦点悬空导致方向键失灵
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [view]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translationX = gesture.translation(in: view).x
        switch gesture.state {
        case .began:
            lastPanX = translationX
            isPanFineScrubbing = onPanBegan?() ?? false
        case .changed:
            guard isPanFineScrubbing else { return }
            let dx = translationX - lastPanX
            lastPanX = translationX
            // Siri Remote 触控板轻滑：14pt 约对应 1 秒微调，实现 1~2 秒级精准定位
            let deltaSeconds = Double(dx) / 14.0
            onPanChanged?(deltaSeconds)
        case .ended:
            if isPanFineScrubbing {
                isPanFineScrubbing = false
                onPanEnded?()
            }
        case .cancelled, .failed:
            if isPanFineScrubbing {
                isPanFineScrubbing = false
                onPanCancelled?()
            }
        default:
            break
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            switch press.type {
            case .leftArrow:
                onLeftDown?()
                handled = true
            case .rightArrow:
                onRightDown?()
                handled = true
            case .playPause:
                onPlayPause?()
                handled = true
            case .select:
                onSelect?()
                handled = true
            case .downArrow:
                onDown?()
                handled = true
            case .upArrow:
                onUp?()
                handled = true
            case .menu:
                onMenu?()
                handled = true
            default:
                break
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            switch press.type {
            case .leftArrow:
                onLeftUp?()
                handled = true
            case .rightArrow:
                onRightUp?()
                handled = true
            default:
                break
            }
        }
        if !handled {
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.type == .leftArrow { onLeftUp?() }
            if press.type == .rightArrow { onRightUp?() }
        }
        super.pressesCancelled(presses, with: event)
    }
}
