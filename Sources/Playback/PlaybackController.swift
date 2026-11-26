import Foundation
import SwiftUI
import Combine
import AVFoundation
import AetherEngine
import AetherEngineSMB

@MainActor
final class PlaybackController: ObservableObject {
    let engine: AetherEngine
    let scrubEngine = AdaptiveScrubEngine()

    @Published private(set) var currentItem: MediaItem?
    @Published private(set) var playlist: [MediaItem] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var playbackRate: Float = 1.0
    @Published private(set) var activeErrorMessage: String?
    @Published private(set) var sleepTimerRemainingMinutes: Int = 0
    @Published private(set) var isPrewarmingNextEpisode: Bool = false

    private let settings = PlayerSettingsStore.shared
    private let historyStore = WatchHistoryStore.shared
    private var cancellables = Set<AnyCancellable>()
    private var historySaveTask: Task<Void, Never>?
    private var sleepTimerTask: Task<Void, Never>?
    private var hasPrewarmedNext = false

    init() {
        do {
            self.engine = try AetherEngine()
        } catch {
            fatalError("无法初始化 AetherEngine: \(error.localizedDescription)")
        }
        // AetherEngine 宿主契约：原生路径默认由 AVPlayerViewController 在 play() 时激活音频会话；
        // 本应用用的是裸播放层 AetherPlayerSurface，没有人替它激活，必须交给引擎自己来做，
        // 否则 HDMI 音频路由不会协商（原生路径无声或不出多声道）。
        engine.nativeAudioSessionActivationEnabled = true
        scrubEngine.attach(engine: engine)
        bindEngineObservers()
    }

    var hasNextEpisode: Bool {
        currentIndex + 1 < playlist.count
    }

    var nextEpisodeItem: MediaItem? {
        hasNextEpisode ? playlist[currentIndex + 1] : nil
    }

    // MARK: - 加载与播放

    func load(item: MediaItem, playlist: [MediaItem] = [], sourceConfig: MediaSourceConfig? = nil) async {
        cancelTimers()
        scrubEngine.cancel()
        activeErrorMessage = nil
        hasPrewarmedNext = false

        self.currentItem = item
        self.playlist = playlist.isEmpty ? [item] : playlist
        self.currentIndex = self.playlist.firstIndex(where: { $0.id == item.id }) ?? 0

        guard let streamURL = item.streamURL else {
            activeErrorMessage = "该媒体条目没有有效的播放地址。"
            return
        }

        let options = buildLoadOptions(item: item, sourceConfig: sourceConfig)
        let startPosition: Double
        if settings.autoResumePlayback, let saved = historyStore.savedPosition(for: item.id) {
            startPosition = saved
        } else {
            startPosition = 0
        }

        applyVideoGravity()

        do {
            if item.protocolType == .smb {
                try await loadOverSMB(
                    url: streamURL,
                    item: item,
                    source: sourceConfig,
                    startPosition: startPosition,
                    options: options
                )
            } else {
                try await engine.load(
                    url: streamURL,
                    startPosition: startPosition,
                    options: options
                )
            }
            applyAudioShaping()
            if playbackRate != 1.0 {
                engine.setRate(playbackRate)
            }
            startPeriodicHistorySave()
        } catch is CancellationError {
            // 被新的 load() 或 stop() 取代，按 AetherEngine 契约不视为播放错误
        } catch {
            activeErrorMessage = describeError(error)
        }
    }

    /// SMB 播放：AetherEngine 本体不处理 smb://，需要宿主经 AetherEngineSMB 连上共享，
    /// 再把文件包成 IOReader 交给引擎；reader 的关闭由引擎在拆解会话时负责。
    /// 凭据不写进 URL（否则会随观看记录/收藏落盘），而是按媒体源 ID 回查配置。
    private func loadOverSMB(
        url: URL,
        item: MediaItem,
        source: MediaSourceConfig?,
        startPosition: Double,
        options: LoadOptions
    ) async throws {
        let parsed = try SMBURL.parse(url.absoluteString)
        let smbSource = source.flatMap { $0.protocolType == .smb ? $0 : nil }
            ?? item.sourceId.flatMap { id in
                MediaSourceStore.shared.sources.first { $0.id == id && $0.protocolType == .smb }
            }
        let user = smbSource?.username ?? parsed.user
        let password = smbSource?.password ?? parsed.password

        let connection = try await SMBConnection.connect(
            server: parsed.server,
            share: parsed.share,
            path: parsed.path,
            user: user,
            password: password
        )
        let reader = SMBIOReader(source: connection, discImageProbeEnabled: item.isDiscImage)
        do {
            try await engine.load(source: .custom(reader), startPosition: startPosition, options: options)
        } catch {
            reader.close()
            throw error
        }
    }

    func stopAndDismiss() {
        saveCurrentProgressNow()
        cancelTimers()
        scrubEngine.cancel()
        engine.stop(resetDisplayCriteria: true, finalTeardown: true)
    }

    func togglePlayPause() {
        AppleTVSoundEffects.playSelect()
        if engine.state == .ended, let item = currentItem {
            Task { await load(item: item, playlist: playlist) }
            return
        }
        engine.togglePlayPause()
    }

    func skipIntro() {
        AppleTVSoundEffects.playSelect()
        let target = min(engine.clock.currentTime + Double(settings.skipIntroSeconds), max(engine.duration - 1, 0))
        Task { await engine.seek(to: target) }
    }

    func playNextEpisode() {
        guard let next = nextEpisodeItem else { return }
        AppleTVSoundEffects.playSelect()
        engine.prepareForItemReplacement()
        Task {
            await load(item: next, playlist: playlist)
        }
    }

    func setRate(_ rate: Float) {
        let clamped = min(max(rate, 0.5), engine.maxSupportedRate)
        playbackRate = clamped
        engine.setRate(clamped)
    }

    func setAudioDelay(_ seconds: Double) {
        let clamped = min(max(seconds, -2.0), 2.0)
        settings.audioDelaySeconds = clamped
        engine.setAudioDelay(clamped)
    }

    func applyVideoGravity() {
        engine.videoGravity = (settings.aspectMode == .aspectFill) ? .resizeAspectFill : .resizeAspect
    }

    func applyDecodePreferenceLive() {
        Task {
            do {
                try await engine.reloadAtCurrentPosition { opts in
                    opts.preferredDecodePath = (self.settings.decodePreference == .software) ? .software : .automatic
                    opts.dolbyVisionHandling = (self.settings.dolbyVisionMode == .baseLayerOnly) ? .baseLayerOnly : .automatic
                    opts.audioBridgeMode = (self.settings.audioBridgePreference == .lossless) ? .lossless : .surroundCompat
                    opts.upscalesLowResolutionVideo = self.settings.upscaleLowResSDR
                }
            } catch {
                activeErrorMessage = "切换解码/画质模式失败：\(error.localizedDescription)"
            }
        }
    }

    func applyAudioShaping() {
        // AetherEngine 的 setAudioShaping 只接受非可选的 AudioShaping；
        // 全部保持默认值（对白增益 0、无压缩、无响度目标）就等于关闭塑形。
        let compressor: AudioShaping.Compressor? = settings.nightModeEnabled
            ? .init(thresholdDB: -30, ratio: 4, makeupGainDB: 10)
            : nil
        let shaping = AudioShaping(
            dialogueGainDB: settings.dialogueLiftDB > 0.1 ? settings.dialogueLiftDB : 0,
            compressor: compressor,
            loudnessTargetLUFS: settings.loudnessNormalizeEnabled ? -20 : nil
        )
        engine.setAudioShaping(shaping)
    }

    func setSleepTimer(minutes: Int) {
        sleepTimerTask?.cancel()
        sleepTimerRemainingMinutes = minutes
        guard minutes > 0 else { return }
        sleepTimerTask = Task { [weak self] in
            var remaining = minutes
            while remaining > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                remaining -= 1
                self?.sleepTimerRemainingMinutes = remaining
            }
            if !Task.isCancelled {
                self?.engine.pause()
                self?.saveCurrentProgressNow()
            }
        }
    }

    // MARK: - LoadOptions 组装（含局域网避坑配置）

    private func buildLoadOptions(item: MediaItem, sourceConfig: MediaSourceConfig?) -> LoadOptions {
        var options = LoadOptions()
        options.httpHeaders = item.httpHeaders
        options.preferredAudioLanguages = settings.parsedAudioLanguages
        options.preferredSubtitleLanguages = settings.parsedSubtitleLanguages
        options.preferredDecodePath = (settings.decodePreference == .software) ? .software : .automatic
        options.audioBridgeMode = (settings.audioBridgePreference == .lossless) ? .lossless : .surroundCompat
        options.dolbyVisionHandling = (settings.dolbyVisionMode == .baseLayerOnly) ? .baseLayerOnly : .automatic
        options.matchContentEnabled = settings.matchContentEnabled
        options.upscalesLowResolutionVideo = settings.upscaleLowResSDR
        options.audioDelaySeconds = settings.audioDelaySeconds
        options.preserveASSMarkup = false // 使用引擎解析好的 .richText 结构化 ASS 样式，兼顾性能与完整样式
        options.prepareNativeSubtitles = true
        options.progressiveSegmentDelivery = true
        options.forwardBufferSegments = settings.forwardBufferSegments
        options.escalatesToSoftwarePath = true

        // 局域网 WebDAV / 网盘反代避坑开关
        if let cfg = sourceConfig {
            if cfg.limitSingleConnection {
                options.maxConcurrentSourceRequests = 1
            }
            if cfg.holdSourceConnection {
                options.heldSourceConnection = true
            }
        }

        // 注入同目录 / 媒体服外挂字幕
        if !item.externalSubtitles.isEmpty {
            options.externalSubtitles = item.externalSubtitles.map { sub in
                ExternalSubtitleTrack(
                    url: sub.url,
                    name: sub.title,
                    language: sub.language,
                    httpHeaders: sub.httpHeaders.isEmpty ? nil : sub.httpHeaders,
                    formatHint: sub.formatHint
                )
            }
        }
        return options
    }

    // MARK: - 观察与自动续播/下一集预热

    private func bindEngineObservers() {
        engine.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .error(let msg):
                    self.activeErrorMessage = self.formatEngineError(fallback: msg)
                case .ended:
                    self.saveCurrentProgressNow()
                    if self.settings.autoPlayNextEpisode && self.hasNextEpisode {
                        self.playNextEpisode()
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func startPeriodicHistorySave() {
        historySaveTask?.cancel()
        historySaveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, !Task.isCancelled else { break }
                self.saveCurrentProgressNow()
                self.maybePrewarmNextEpisode()
            }
        }
    }

    private func saveCurrentProgressNow() {
        guard let item = currentItem, engine.duration > 10 else { return }
        historyStore.recordProgress(
            item: item,
            position: engine.clock.currentTime,
            duration: engine.duration
        )
    }

    /// 距离片尾不足 90 秒时，利用 AetherEngine.prewarm 预热下一集开头数据，实现无缝切集
    /// （prewarm 只走 HTTP Range 请求，SMB 条目不参与预热）
    private func maybePrewarmNextEpisode() {
        guard !hasPrewarmedNext,
              settings.autoPlayNextEpisode,
              let next = nextEpisodeItem,
              next.protocolType != .smb,
              let nextURL = next.streamURL,
              engine.duration > 180,
              (engine.duration - engine.clock.currentTime) <= Double(max(settings.skipOutroSeconds, 60)) else {
            return
        }
        hasPrewarmedNext = true
        isPrewarmingNextEpisode = true
        Task.detached { [weak self] in
            _ = await AetherEngine.prewarm(url: nextURL, httpHeaders: next.httpHeaders)
            await MainActor.run {
                self?.isPrewarmingNextEpisode = false
            }
        }
    }

    private func formatEngineError(fallback: String) -> String {
        guard let info = engine.errorInfo else { return fallback }
        switch info.kind {
        case .sourceCertificateRejected:
            return "HTTPS 证书校验未通过（错误码 \(info.underlyingCode ?? 0)）。若为局域网自签名服务，请在设置中开启「信任局域网自签名证书」。"
        case .sourceRefused:
            return "服务器拒绝访问（HTTP \(info.underlyingCode ?? 0)），请检查账号密码、Token 或同时连接数限制。"
        case .sourceRateLimited:
            return "服务器触发限流（HTTP \(info.underlyingCode ?? 429)），建议在媒体源配置中开启「单连接限流模式」。"
        default:
            return info.message.isEmpty ? fallback : info.message
        }
    }

    private func describeError(_ error: Error) -> String {
        if let info = engine.errorInfo {
            return formatEngineError(fallback: info.message)
        }
        return error.localizedDescription
    }

    private func cancelTimers() {
        historySaveTask?.cancel()
        historySaveTask = nil
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerRemainingMinutes = 0
    }
}
