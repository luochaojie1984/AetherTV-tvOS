import Foundation
import SwiftUI
import UIKit
import CoreGraphics
import AetherEngine

enum ScrubDirection: Int, Sendable {
    case rewind = -1
    case forward = 1

    var symbolName: String {
        self == .forward ? "forward.fill" : "backward.fill"
    }
}

/// 长按顺滑变速快进/快退 + 暂停触控精调 + 画面实时预览引擎
/// 核心特性：
/// 1. 短按（< 0.28s）：原生 Apple TV 风格 ±10 秒精准跳转
/// 2. 长按（>= 0.28s）：非线性平滑加速（按住越久速度越快，从 4x 平滑爬升至 120x）
/// 3. 暂停触控精调（Jog Scrub）：触控板轻滑微调 1~2 秒级定位并实时刷新预览
/// 4. 实时画面预览与防闪烁防回弹：
///    - 优先调用 AetherEngine 的 cache-backed `scrubPreviewFrame`，保持上一帧直至新帧就绪
///    - 松手提交最终 seek 前先等待旧的节流 `liveSeekTask` 完成，杜绝高速快进松手后画面回弹
@MainActor
final class AdaptiveScrubEngine: ObservableObject {
    @Published private(set) var isScrubbing: Bool = false
    @Published private(set) var isFineScrubbing: Bool = false
    @Published private(set) var direction: ScrubDirection = .forward
    @Published private(set) var scrubTime: Double = 0
    @Published private(set) var speedMultiplier: Double = 1.0
    @Published private(set) var previewImage: CGImage?
    @Published private(set) var previewUIImage: UIImage?
    @Published private(set) var previewActualTime: Double?

    private weak var engine: AetherEngine?
    private var pressStartUptime: TimeInterval = 0
    private var lastTickUptime: TimeInterval = 0
    private var lastPreviewRequestUptime: TimeInterval = 0
    private var lastLiveSeekUptime: TimeInterval = 0
    private var lastFineNotchTime: Double = 0
    private var wasPlayingBeforeScrub: Bool = false
    private var isLiveSeekInFlight: Bool = false
    private var isPreviewInFlight: Bool = false

    private var tickTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var liveSeekTask: Task<Void, Never>?
    private var finalSeekTask: Task<Void, Never>?

    /// 触发长按变速的阈值（秒）
    private let longPressThreshold: TimeInterval = 0.28
    /// 短按步进秒数
    private let shortTapStepSeconds: Double = 10.0

    func attach(engine: AetherEngine) {
        self.engine = engine
    }

    func beginPress(direction: ScrubDirection) {
        guard let engine, engine.duration > 1 else { return }
        if isScrubbing && !isFineScrubbing && self.direction == direction { return }

        finalSeekTask?.cancel()
        finalSeekTask = nil
        cancelInternalTasks()
        isFineScrubbing = false
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

        let pendingLiveSeek = liveSeekTask
        pendingLiveSeek?.cancel()
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
            finalSeekTask?.cancel()
            finalSeekTask = Task {
                _ = await pendingLiveSeek?.value
                guard !Task.isCancelled else { return }
                await engine.seek(to: jumpTarget)
            }
            return
        }

        // 长按松手：先等旧的节流预览 seek 结束，再提交最终精准落点，防止旧 seek 覆盖导致画面回弹
        isScrubbing = false
        isFineScrubbing = false
        speedMultiplier = 1.0
        finalSeekTask?.cancel()
        finalSeekTask = Task { [weak self] in
            _ = await pendingLiveSeek?.value
            guard !Task.isCancelled else { return }
            await engine.seek(to: target)
            guard !Task.isCancelled else { return }
            if resumeAfter {
                engine.play()
            }
            // 保持上一帧直至画面落地后淡出预览缩略图
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self?.clearPreviewImages()
        }
    }

    // MARK: - 暂停态 Siri Remote 触控板微调（Jog Scrub）

    @discardableResult
    func beginFineScrub() -> Bool {
        guard let engine, engine.duration > 1, engine.state == .paused else { return false }
        finalSeekTask?.cancel()
        finalSeekTask = nil
        cancelInternalTasks()

        isScrubbing = true
        isFineScrubbing = true
        speedMultiplier = 1.0
        wasPlayingBeforeScrub = false
        scrubTime = engine.clock.currentTime
        lastFineNotchTime = scrubTime
        lastPreviewRequestUptime = 0
        lastLiveSeekUptime = 0

        requestFinePreview(at: scrubTime, engine: engine, force: true)
        return true
    }

    func updateFineScrub(deltaSeconds: Double) {
        guard isFineScrubbing, let engine else { return }
        if abs(deltaSeconds) > 0.001 {
            direction = deltaSeconds >= 0 ? .forward : .rewind
        }
        let nextTime = clampTime(scrubTime + deltaSeconds, duration: engine.duration)
        scrubTime = nextTime

        if abs(nextTime - lastFineNotchTime) >= 1.0 {
            lastFineNotchTime = nextTime
            AppleTVSoundEffects.playScrubNotch(speedMultiplier: 1.5)
        }
        requestFinePreview(at: nextTime, engine: engine, force: false)
    }

    func commitFineScrub() {
        guard isFineScrubbing else { return }
        let target = scrubTime
        let pendingLiveSeek = liveSeekTask
        pendingLiveSeek?.cancel()
        cancelInternalTasks()

        isScrubbing = false
        isFineScrubbing = false
        speedMultiplier = 1.0

        guard let engine else {
            clearPreviewImages()
            return
        }

        finalSeekTask?.cancel()
        finalSeekTask = Task { [weak self] in
            _ = await pendingLiveSeek?.value
            guard !Task.isCancelled else { return }
            await engine.seek(to: target)
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self?.clearPreviewImages()
        }
    }

    func cancelFineScrub() {
        guard isFineScrubbing else { return }
        cancel()
    }

    func cancel() {
        finalSeekTask?.cancel()
        finalSeekTask = nil
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

    private func requestFinePreview(at targetSeconds: Double, engine: AetherEngine, force: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if engine.supportsCacheBackedStills {
            guard !isPreviewInFlight, force || (now - lastPreviewRequestUptime >= 0.075) else { return }
            lastPreviewRequestUptime = now
            isPreviewInFlight = true
            let gen = engine.scrubPreviewSourceGeneration
            previewTask = Task { [weak self] in
                defer {
                    Task { @MainActor in self?.isPreviewInFlight = false }
                }
                let frame = await engine.scrubPreviewFrame(
                    atSeconds: targetSeconds,
                    refined: true,
                    maxWidth: 640,
                    isCancelled: { Task.isCancelled }
                )
                await MainActor.run {
                    guard let self, self.isFineScrubbing, engine.scrubPreviewSourceGeneration == gen else { return }
                    if let frame {
                        self.previewImage = frame.image
                        self.previewUIImage = UIImage(cgImage: frame.image)
                        self.previewActualTime = frame.actualSeconds
                    } else {
                        self.triggerThrottledLiveSeek(to: targetSeconds, speed: 4.0, engine: engine)
                    }
                }
            }
        } else {
            triggerThrottledLiveSeek(to: targetSeconds, speed: 4.0, engine: engine)
        }
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
                    // 仅在新帧解码成功后更新，保持上一帧直到新帧就绪，防止预览窗闪烁
                    if let frame {
                        self.previewImage = frame.image
                        self.previewUIImage = UIImage(cgImage: frame.image)
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

    private func clearPreviewImages() {
        previewImage = nil
        previewUIImage = nil
        previewActualTime = nil
    }

    private func resetState() {
        isScrubbing = false
        isFineScrubbing = false
        speedMultiplier = 1.0
        clearPreviewImages()
    }
}
