import Foundation
import SwiftUI
import UIKit
import Combine
import AVFoundation
import AetherEngine
import AetherEngineSMB

@MainActor
final class PlaybackController: ObservableObject {
    let engine: AetherEngine?
    let scrubEngine = AdaptiveScrubEngine()

    @Published private(set) var currentItem: MediaItem?
    @Published private(set) var playlist: [MediaItem] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var playbackRate: Float = 1.0
    @Published private(set) var activeErrorMessage: String?
    @Published private(set) var sleepTimerRemainingMinutes: Int = 0
    @Published private(set) var isPrewarmingNextEpisode: Bool = false
    @Published private(set) var activeAspectMode: VideoAspectMode = PlayerSettingsStore.shared.aspectMode
    @Published private(set) var routeRemovalEventCount: Int = 0

    private let settings = PlayerSettingsStore.shared
    private let historyStore = WatchHistoryStore.shared
    private var cancellables = Set<AnyCancellable>()
    private var historySaveTask: Task<Void, Never>?
    private var sleepTimerTask: Task<Void, Never>?
    private var routeObserver: NSObjectProtocol?
    private var hasPrewarmedNext = false
    private var wasPausedState = false
    private var activeSourceConfig: MediaSourceConfig?
    private var activeTempSubtitleDirectory: URL?

    private static let nonHDMIRouteRemovalPorts: Set<AVAudioSession.Port> = [
        .headphones,
        .bluetoothA2DP,
        .bluetoothLE,
        .bluetoothHFP,
        .airPlay,
        .usbAudio
    ]

    init() {
        do {
            let instance = try AetherEngine()
            self.engine = instance
            // AetherEngine 宿主契约：原生路径默认由 AVPlayerViewController 在 play() 时激活音频会话；
            // 本应用用的是裸播放层 AetherPlayerSurface，没有人替它激活，必须交给引擎自己来做，
            // 否则 HDMI 音频路由不会协商（原生路径无声或不出多声道）。
            instance.nativeAudioSessionActivationEnabled = true
            scrubEngine.attach(engine: instance)
            bindEngineObservers(instance)
            installAudioRouteObserver()
        } catch {
            self.engine = nil
            self.activeErrorMessage = "无法初始化播放引擎：\(error.localizedDescription)"
        }
    }

    var hasNextEpisode: Bool {
        currentIndex + 1 < playlist.count
    }

    var nextEpisodeItem: MediaItem? {
        hasNextEpisode ? playlist[currentIndex + 1] : nil
    }

    // MARK: - 加载与播放

    func load(item: MediaItem, playlist: [MediaItem] = [], sourceConfig: MediaSourceConfig? = nil) async {
        guard let engine else {
            activeErrorMessage = activeErrorMessage ?? "播放引擎未能初始化，请返回后重试。"
            return
        }

        cancelTimers()
        scrubEngine.cancel()
        cleanupTempSubtitles()
        activeErrorMessage = nil
        hasPrewarmedNext = false
        wasPausedState = false

        self.currentItem = item
        self.playlist = playlist.isEmpty ? [item] : playlist
        self.currentIndex = self.playlist.firstIndex(where: { $0.id == item.id }) ?? 0

        let resolvedSource = resolveSourceConfig(for: item, explicit: sourceConfig)
        self.activeSourceConfig = resolvedSource

        guard let streamURL = item.streamURL else {
            activeErrorMessage = "该媒体条目没有有效的播放地址。"
            return
        }

        let trackMemory = historyStore.trackMemory(for: item.id)
        activeAspectMode = trackMemory?.aspectMode ?? settings.aspectMode
        applyVideoGravity()

        var effectiveExternalSubs = item.externalSubtitles
        if item.protocolType == .smb,
           !item.externalSubtitles.isEmpty,
           let smbSource = resolvedSource {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("AetherTVSubtitles", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            if let downloaded = try? await SMBSourceClient().downloadSubtitles(
                source: smbSource,
                subtitles: item.externalSubtitles,
                destinationDirectory: tempDir
            ), !downloaded.isEmpty {
                activeTempSubtitleDirectory = tempDir
                effectiveExternalSubs = downloaded
            }
        }

        let options = buildLoadOptions(
            item: item,
            sourceConfig: resolvedSource,
            externalSubtitles: effectiveExternalSubs
        )

        let startPosition: Double
        if settings.autoResumePlayback {
            if let localSaved = historyStore.savedPosition(for: item.id) {
                startPosition = localSaved
            } else if let remoteSaved = item.serverResumeSeconds, remoteSaved > 8 {
                startPosition = remoteSaved
            } else {
                startPosition = 0
            }
        } else {
            startPosition = 0
        }

        do {
            if item.protocolType == .smb {
                try await loadOverSMB(
                    engine: engine,
                    url: streamURL,
                    item: item,
                    source: resolvedSource,
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
            restoreTrackSelectionsIfSaved(memory: trackMemory, engine: engine)
            if playbackRate != 1.0 {
                engine.setRate(playbackRate)
            }
            startPeriodicHistorySave()
            reportServerProgress(event: .started)
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
        engine: AetherEngine,
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
        reportServerProgress(event: .stopped)
        cancelTimers()
        scrubEngine.cancel()
        setIdleTimerDisabled(false)
        removeAudioRouteObserver()
        cleanupTempSubtitles()
        engine?.stop(resetDisplayCriteria: true, finalTeardown: true)
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            saveCurrentProgressNow()
            reportServerProgress(event: .paused)
            setIdleTimerDisabled(false)
        case .active:
            guard let engine, engine.needsForegroundVideoRestore else { return }
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await engine.reloadAtCurrentPosition()
                } catch {
                    if let item = self.currentItem {
                        await self.load(item: item, playlist: self.playlist, sourceConfig: self.activeSourceConfig)
                    }
                }
            }
        default:
            break
        }
    }

    func togglePlayPause() {
        guard let engine else { return }
        AppleTVSoundEffects.playSelect()
        if engine.state == .ended, let item = currentItem {
            Task { await load(item: item, playlist: playlist, sourceConfig: activeSourceConfig) }
            return
        }
        engine.togglePlayPause()
    }

    func skipIntro() {
        guard let engine else { return }
        AppleTVSoundEffects.playSelect()
        let target = min(engine.clock.currentTime + Double(settings.skipIntroSeconds), max(engine.duration - 1, 0))
        Task { await engine.seek(to: target) }
    }

    func playNextEpisode() {
        guard let engine, let next = nextEpisodeItem else { return }
        AppleTVSoundEffects.playSelect()
        saveCurrentProgressNow()
        reportServerProgress(event: .stopped)
        engine.prepareForItemReplacement()
        Task {
            await load(item: next, playlist: playlist, sourceConfig: activeSourceConfig)
        }
    }

    func setRate(_ rate: Float) {
        guard let engine else { return }
        let clamped = min(max(rate, 0.5), engine.maxSupportedRate)
        playbackRate = clamped
        engine.setRate(clamped)
    }

    func setAudioDelay(_ seconds: Double) {
        let clamped = min(max(seconds, -2.0), 2.0)
        settings.audioDelaySeconds = clamped
        engine?.setAudioDelay(clamped)
    }

    func setAspectMode(_ mode: VideoAspectMode) {
        activeAspectMode = mode
        settings.aspectMode = mode
        applyVideoGravity()
        if let item = currentItem {
            historyStore.recordTrackSelection(for: item, aspectMode: mode)
        }
    }

    func applyVideoGravity() {
        engine?.videoGravity = (activeAspectMode == .aspectFill) ? .resizeAspectFill : .resizeAspect
    }

    // MARK: - 音轨 / 字幕选择与单片记忆

    func selectAudioTrack(index: Int) {
        guard let engine else { return }
        engine.selectAudioTrack(index: index)
        if let item = currentItem {
            historyStore.recordTrackSelection(for: item, audioTrackId: index)
        }
    }

    func selectPrimarySubtitleTrack(index: Int) {
        guard let engine else { return }
        engine.selectSubtitleTrack(index: index)
        if let item = currentItem {
            historyStore.recordTrackSelection(for: item, primarySubtitleTrackId: index)
        }
    }

    func clearPrimarySubtitle() {
        guard let engine else { return }
        engine.clearSubtitle()
        if let item = currentItem {
            historyStore.recordTrackSelection(for: item, primarySubtitleDisabled: true)
        }
    }

    func selectSecondarySubtitleTrack(index: Int) {
        guard let engine else { return }
        engine.selectSecondarySubtitleTrack(index: index)
        if let item = currentItem {
            historyStore.recordTrackSelection(for: item, secondarySubtitleTrackId: index)
        }
    }

    func clearSecondarySubtitle() {
        guard let engine else { return }
        engine.clearSecondarySubtitle()
        if let item = currentItem {
            historyStore.recordTrackSelection(for: item, clearSecondarySubtitle: true)
        }
    }

    func applyDecodePreferenceLive() {
        guard let engine else { return }
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
        guard let engine else { return }
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
                self?.engine?.pause()
                self?.saveCurrentProgressNow()
                self?.reportServerProgress(event: .paused)
            }
        }
    }

    // MARK: - LoadOptions 组装（含局域网避坑配置与 Keychain 动态鉴权注入）

    private func resolveSourceConfig(for item: MediaItem, explicit: MediaSourceConfig?) -> MediaSourceConfig? {
        if let explicit { return explicit }
        guard let sourceId = item.sourceId else { return nil }
        return MediaSourceStore.shared.sources.first { $0.id == sourceId }
    }

    private func hydratedHeaders(for item: MediaItem, sourceConfig: MediaSourceConfig?) -> [String: String] {
        var headers = item.httpHeaders
        if let sourceConfig {
            for (key, value) in NetworkPitfallGuards.standardHTTPHeaders(for: sourceConfig) {
                headers[key] = value
            }
        }
        return headers
    }

    private func buildLoadOptions(
        item: MediaItem,
        sourceConfig: MediaSourceConfig?,
        externalSubtitles: [ExternalSubtitleReference]
    ) -> LoadOptions {
        var options = LoadOptions()
        let freshHeaders = hydratedHeaders(for: item, sourceConfig: sourceConfig)
        options.httpHeaders = freshHeaders
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

        // 注入同目录 / 媒体服外挂字幕（远端字幕补全最新鉴权头，SMB 本地字幕无需头）
        if !externalSubtitles.isEmpty {
            options.externalSubtitles = externalSubtitles.map { sub in
                let subHeaders: [String: String]?
                if sub.url.isFileURL {
                    subHeaders = nil
                } else {
                    var merged = sub.httpHeaders
                    for (k, v) in freshHeaders where merged[k] == nil {
                        merged[k] = v
                    }
                    subHeaders = merged.isEmpty ? nil : merged
                }
                return ExternalSubtitleTrack(
                    url: sub.url,
                    name: sub.title,
                    language: sub.language,
                    httpHeaders: subHeaders,
                    formatHint: sub.formatHint
                )
            }
        }
        return options
    }

    private func restoreTrackSelectionsIfSaved(memory: WatchHistoryEntry?, engine: AetherEngine) {
        guard let memory else { return }
        if let audioId = memory.audioTrackId,
           engine.audioTracks.contains(where: { $0.id == audioId }),
           engine.activeAudioTrackIndex != audioId {
            engine.selectAudioTrack(index: audioId)
        }
        if memory.primarySubtitleDisabled == true {
            engine.clearSubtitle()
        } else if let subId = memory.primarySubtitleTrackId,
                  engine.subtitleTracks.contains(where: { $0.id == subId }) {
            engine.selectSubtitleTrack(index: subId)
        }
        if let secondaryId = memory.secondarySubtitleTrackId,
           engine.subtitleTracks.contains(where: { $0.id == secondaryId }) {
            engine.selectSecondarySubtitleTrack(index: secondaryId)
        }
    }

    // MARK: - 观察、防休眠、音频路由与自动续播

    private func bindEngineObservers(_ engine: AetherEngine) {
        engine.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                let keepAwake = (state == .playing || state == .loading || state == .seeking)
                self.setIdleTimerDisabled(keepAwake)

                switch state {
                case .playing:
                    if self.wasPausedState {
                        self.wasPausedState = false
                        self.reportServerProgress(event: .playing)
                    }
                case .paused:
                    self.wasPausedState = true
                    self.saveCurrentProgressNow()
                    self.reportServerProgress(event: .paused)
                case .error(let msg):
                    self.activeErrorMessage = self.formatEngineError(fallback: msg)
                case .ended:
                    self.saveCurrentProgressNow()
                    self.reportServerProgress(event: .stopped)
                    if self.settings.autoPlayNextEpisode && self.hasNextEpisode {
                        self.playNextEpisode()
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func installAudioRouteObserver() {
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
                  reason == .oldDeviceUnavailable,
                  let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else {
                return
            }
            // 仅在蓝牙耳机 / AirPods / 耳机 / AirPlay / USB 音频断开时暂停，
            // 绝不拦截 HDMI 热插拔（Apple TV 匹配动态范围/帧率或 eARC 切换会触发 HDMI 路由重建）
            let removedNonHDMI = previousRoute.outputs.contains { Self.nonHDMIRouteRemovalPorts.contains($0.portType) }
            guard removedNonHDMI else { return }

            Task { @MainActor [weak self] in
                guard let self, let engine = self.engine else { return }
                if engine.state == .playing || engine.state == .seeking {
                    engine.pause()
                    self.saveCurrentProgressNow()
                    self.reportServerProgress(event: .paused)
                    self.routeRemovalEventCount &+= 1
                }
            }
        }
    }

    private func removeAudioRouteObserver() {
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        if UIApplication.shared.isIdleTimerDisabled != disabled {
            UIApplication.shared.isIdleTimerDisabled = disabled
        }
    }

    private func startPeriodicHistorySave() {
        historySaveTask?.cancel()
        historySaveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, !Task.isCancelled else { break }
                self.saveCurrentProgressNow()
                if self.engine?.state == .playing {
                    self.reportServerProgress(event: .playing)
                }
                self.maybePrewarmNextEpisode()
            }
        }
    }

    private func saveCurrentProgressNow() {
        guard let engine, let item = currentItem, engine.duration > 10 else { return }
        historyStore.recordProgress(
            item: item,
            position: engine.clock.currentTime,
            duration: engine.duration
        )
    }

    private func reportServerProgress(event: PlaybackSyncEvent) {
        guard let engine,
              let item = currentItem,
              item.protocolType == .emby || item.protocolType == .jellyfin || item.protocolType == .plex,
              let source = resolveSourceConfig(for: item, explicit: activeSourceConfig) else {
            return
        }
        let pos = engine.clock.currentTime
        let dur = engine.duration
        let allowSelfSigned = settings.allowSelfSignedCertificates
        Task.detached(priority: .utility) {
            await MediaServerClients(allowSelfSignedLAN: allowSelfSigned).reportProgress(
                source: source,
                item: item,
                positionSeconds: pos,
                durationSeconds: dur,
                event: event
            )
        }
    }

    /// 距离片尾不足 90 秒时，利用 AetherEngine.prewarm 预热下一集开头数据，实现无缝切集
    /// （prewarm 只走 HTTP Range 请求，SMB 条目不参与预热）
    private func maybePrewarmNextEpisode() {
        guard let engine,
              !hasPrewarmedNext,
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
        let nextSource = resolveSourceConfig(for: next, explicit: activeSourceConfig)
        let headers = hydratedHeaders(for: next, sourceConfig: nextSource)
        Task.detached { [weak self] in
            _ = await AetherEngine.prewarm(url: nextURL, httpHeaders: headers)
            guard let self else { return }
            await MainActor.run {
                self.isPrewarmingNextEpisode = false
            }
        }
    }

    private func cleanupTempSubtitles() {
        if let dir = activeTempSubtitleDirectory {
            try? FileManager.default.removeItem(at: dir)
            activeTempSubtitleDirectory = nil
        }
    }

    private func formatEngineError(fallback: String) -> String {
        guard let info = engine?.errorInfo else { return fallback }
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
        if let info = engine?.errorInfo {
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
