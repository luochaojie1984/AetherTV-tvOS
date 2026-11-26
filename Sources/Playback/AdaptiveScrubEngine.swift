import Foundation
import SwiftUI
import CoreGraphics
import AetherEngine

enum ScrubDirection: Int, Sendable {
    case rewind = -1
    case forward = 1

    var symbolName: String {
        self == .forward ? "forward.fill" : "backward.fill"
    }
}

/// 长按顺滑变速快进/快退 + 画面实时预览引擎
/// 核心特性：
/// 1. 短按（< 0.28s）：原生 Apple TV 风格 ±10 秒精准跳转
/// 2. 长按（>= 0.28s）：非线性平滑加速（按住越久速度越快，从 4x 平滑爬升至 120x）
/// 3. 实时画面预览与速度匹配：
///    - 优先调用 AetherEngine 的 cache-backed `scrubPreviewFrame`，零额外连接开销
///    - 随着倍速提高自动缩短帧刷新间隔，快进越快画面切换越快
///    - 超出缓存区间时，通过单并发节流 `seek(to:)` 直接驱动主画面实时刷新，同时保护 SMB/WebDAV 与解码队列不被打爆
@MainActor
final class AdaptiveScrubEngine: ObservableObject {
    @Published private(set) var isScrubbing: Bool = false
    @Published private(set) var direction: ScrubDirection = .forward
    @Published private(set) var scrubTime: Double = 0
    @Published private(set) var speedMultiplier: Double = 1.0
    @Published private(set) var previewImage: CGImage?
    @Published private(set) var previewActualTime: Double?

    private weak var engine: AetherEngine?
    private var pressStartUptime: TimeInterval = 0
    private var lastTickUptime: TimeInterval = 0
    private var lastPreviewRequestUptime: TimeInterval = 0
    private var lastLiveSeekUptime: TimeInterval = 0
    private var wasPlayingBeforeScrub: Bool = false
    private var isLiveSeekInFlight: Bool = false
    private var isPreviewInFlight: Bool = false

    private var tickTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var liveSeekTask: Task<Void, Never>?

    /// 触发长按变速的阈值（秒）
    private let longPressThreshold: TimeInterval = 0.28
    /// 短按步进秒数
    private let shortTapStepSeconds: Double = 10.0

    func attach(engine: AetherEngine) {
        self.engine = engine
    }

    func beginPress(direction: ScrubDirection) {
        guard let engine, engine.duration > 1 else { return }
        if isScrubbing && self.direction == direction { return }

        cancelInternalTasks()
        self.direction = direction
        pressStartUptime = ProcessInfo.processInfo.systemUptime
        lastTickUptime = pressStartUptime
        lastPreviewRequestUptime = 0
        lastLiveSeekUptime = 0
        scrubTime = engine.clock.currentTime
        speedMultiplier = 1.0
        wasPlayingBeforeScrub = (engine.state == .playing)

        // 启动 60Hz 监控循环：超过 0.28s 自动无缝切入长按变速预览模式
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_666_667) // ~60fps
                guard let self, !Task.isCancelled else { break }
                self.onFrameTick()
            }
        }
    }

    func endPress() {
        let held = ProcessInfo.processInfo.systemUptime - pressStartUptime
        let dir = direction
        let target = scrubTime
        let wasScrub = isScrubbing
        let resumeAfter = wasPlayingBeforeScrub

        cancelInternalTasks()

        guard let engine else {
            resetState()
            return
        }

        if !wasScrub && held < longPressThreshold {
            // 短按：执行原生 ±10 秒跳转
            AppleTVSoundEffects.playSelect()
            let jumpTarget = clampTime(engine.clock.currentTime + Double(dir.rawValue) * shortTapStepSeconds, duration: engine.duration)
            resetState()
            Task {
                await engine.seek(to: jumpTarget)
            }
            return
        }

        // 长按松手：提交最终精准落点，并恢复之前的播放状态
        isScrubbing = false
        speedMultiplier = 1.0
        Task { [weak self] in
            await engine.seek(to: target)
            if resumeAfter {
                engine.play()
            }
            // 等待画面落地后淡出预览缩略图
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.previewImage = nil
            self?.previewActualTime = nil
        }
    }

    func cancel() {
        cancelInternalTasks()
        resetState()
    }

    // MARK: - 核心变速曲线与实时预览调度

    private func onFrameTick() {
        guard let engine else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let held = now - pressStartUptime
        let dt = min(now - lastTickUptime, 0.1)
        lastTickUptime = now

        guard held >= longPressThreshold else { return }

        if !isScrubbing {
            isScrubbing = true
            // 进入长按实时预览时先暂停音频输出，避免变速爆音，由画面预览主导视觉反馈
            if engine.state == .playing {
                engine.pause()
            }
        }

        let activeHold = held - longPressThreshold
        let speed = computeSmoothSpeed(activeHoldSeconds: activeHold, duration: engine.duration)
        speedMultiplier = speed

        let nextTime = clampTime(scrubTime + Double(direction.rawValue) * speed * dt, duration: engine.duration)
        scrubTime = nextTime

        AppleTVSoundEffects.playScrubNotch(speedMultiplier: speed)
        scheduleMatchedPreview(targetSeconds: nextTime, speed: speed, now: now, engine: engine)
    }

    /// 非线性平滑加速曲线：按住越久速度越快
    /// - 0s ~ 1.0s: 4x -> 10x（微调/中速浏览）
    /// - 1.0s ~ 3.0s: 10x -> 36x（快速扫片）
    /// - 3.0s ~ 6.0s+: 36x -> 120x（长片高速跨越）
    /// 同时根据影片总时长做自适应上限，避免短视频一秒飞过头
    private func computeSmoothSpeed(activeHoldSeconds t: Double, duration: Double) -> Double {
        let baseSpeed = 4.0
        let raw = baseSpeed * pow(1.78, t) + 2.5 * t * t
        // 保证最快也至少需要 ~18 秒扫完全片，且最高不超过 120x
        let durationAwareCap = max(16.0, min(120.0, duration / 18.0))
        return min(max(raw, baseSpeed), durationAwareCap)
    }

    /// 根据当前倍速动态调整预览刷新间隔：快进越快，画面切换越快
    private func scheduleMatchedPreview(
        targetSeconds: Double,
        speed: Double,
        now: TimeInterval,
        engine: AetherEngine
    ) {
        // 倍速越高，帧间隔越短（从 120ms 线性压缩到 48ms），呈现与速度成正比的实时画面切换感
        let previewInterval: TimeInterval
        let refinedDecode: Bool
        if speed <= 12 {
            previewInterval = 0.115
            refinedDecode = true
        } else if speed <= 40 {
            previewInterval = 0.075
            refinedDecode = false
        } else {
            previewInterval = 0.048
            refinedDecode = false
        }

        // 1. 优先尝试 AetherEngine 零连接开销的缓存关键帧预览
        if engine.supportsCacheBackedStills,
           !isPreviewInFlight,
           now - lastPreviewRequestUptime >= previewInterval {
            lastPreviewRequestUptime = now
            isPreviewInFlight = true
            let gen = engine.scrubPreviewSourceGeneration
            previewTask = Task { [weak self] in
                defer {
                    Task { @MainActor in self?.isPreviewInFlight = false }
                }
                let frame = await engine.scrubPreviewFrame(
                    atSeconds: targetSeconds,
                    refined: refinedDecode,
                    maxWidth: 640,
                    isCancelled: { Task.isCancelled }
                )
                await MainActor.run {
                    guard let self, self.isScrubbing, engine.scrubPreviewSourceGeneration == gen else { return }
                    if let frame {
                        self.previewImage = frame.image
                        self.previewActualTime = frame.actualSeconds
                    } else {
                        // 超出本地缓存区间时，触发节流主画面实时 Seek，保证画面持续跟随快进切换
                        self.triggerThrottledLiveSeek(to: targetSeconds, speed: speed, engine: engine)
                    }
                }
            }
        } else if !engine.supportsCacheBackedStills {
            // 非缓存支持路径（如本地软解等）直接走节流主画面 Seek
            triggerThrottledLiveSeek(to: targetSeconds, speed: speed, engine: engine)
        }
    }

    /// 保护局域网 SMB/WebDAV 与解码队列的单并发节流主画面 Seek
    private func triggerThrottledLiveSeek(to targetSeconds: Double, speed: Double, engine: AetherEngine) {
        let now = ProcessInfo.processInfo.systemUptime
        let minSeekInterval: TimeInterval = speed > 40 ? 0.18 : 0.26
        guard !isLiveSeekInFlight, now - lastLiveSeekUptime >= minSeekInterval else { return }

        lastLiveSeekUptime = now
        isLiveSeekInFlight = true
        liveSeekTask = Task { [weak self] in
            defer {
                Task { @MainActor in self?.isLiveSeekInFlight = false }
            }
            await engine.seek(to: targetSeconds)
        }
    }

    private func clampTime(_ value: Double, duration: Double) -> Double {
        min(max(value, 0), max(duration - 0.5, 0))
    }

    private func cancelInternalTasks() {
        tickTask?.cancel()
        tickTask = nil
        previewTask?.cancel()
        previewTask = nil
        liveSeekTask?.cancel()
        liveSeekTask = nil
        isPreviewInFlight = false
        isLiveSeekInFlight = false
    }

    private func resetState() {
        isScrubbing = false
        speedMultiplier = 1.0
        previewImage = nil
        previewActualTime = nil
    }
}
