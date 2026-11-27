#if SMOKE_TEST
import SwiftUI
import UIKit
import AetherEngine

// tvOS 模拟器冒烟测试：与界面走同一套代码路径（WebDAV / SMB 客户端、PlaybackController、
// PlayerScreenView），把每一步的结果写进 App 沙盒的 Documents/smoke-test-result.json，
// 由 .github/workflows/smoke-test-tvos.yml 读取并判定。
//
// 只在 SmokeTest 构建配置下编入（project.yml 为该配置定义了 SMOKE_TEST 编译条件），
// Release 包里这段代码完全不存在。

enum SmokeTestFailure: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

@MainActor
enum SmokeTestRunner {

    // MARK: - 报告结构

    struct Step: Codable {
        var name: String
        var ok: Bool
        var startedAt: Double
        var durationSeconds: Double
        var detail: String
        var message: String?
    }

    struct Report: Codable {
        var ok = true
        var startedAt = Date().timeIntervalSince1970
        var finishedAt: Double?
        var appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        var engineVersion = AetherEngine.version
        var system = ProcessInfo.processInfo.operatingSystemVersionString
        var steps: [Step] = []
    }

    static var report = Report()
    static var didStart = false

    // MARK: - 入口

    /// 由 Sources/App/SmokeTest.swift 在 `#if SMOKE_TEST` 分支里调用
    static func run() async {
        // 只跑一次：界面重新出现、多窗口都不该重复整轮测试
        guard !didStart else { return }
        didStart = true
        do {
            try await waitForRoot()
        } catch {
            fail("启动", error.localizedDescription)
            return
        }

        let defaults = UserDefaults.standard
        let webdavPort = defaults.integer(forKey: "smokeWebdavPort")
        let hlsPort = defaults.integer(forKey: "smokeHlsPort")
        let smbPort = defaults.integer(forKey: "smokeSmbPort")

        guard webdavPort > 0 else {
            fail("配置", "--smoke-test 需要 -smokeWebdavPort（可选 -smokeSmbPort / -smokeHlsPort）")
            return
        }

        // 提前种入媒体源，让首页的「局域网媒体源」在最初的截图里就能看到
        let webdav = MediaSourceConfig(
            name: "Smoke WebDAV",
            protocolType: .webdav,
            host: "127.0.0.1",
            port: webdavPort,
            useHTTPS: false,
            basePath: "/dav",
            username: "smoke",
            password: "smoke-pass"
        )
        let smb: MediaSourceConfig? = smbPort > 0 ? MediaSourceConfig(
            name: "Smoke SMB",
            protocolType: .smb,
            host: "127.0.0.1",
            port: smbPort,
            useHTTPS: false,
            username: "smoke",
            password: "smoke-pass",
            shareName: "MEDIA"
        ) : nil
        MediaSourceStore.shared.sources = [webdav] + (smb.map { [$0] } ?? [])
        startWatchdog()

        try? await Task.sleep(nanoseconds: 5_000_000_000)   // 首页先出画面，留给截图

        await step("ui.settings") {
            try await showcase("设置", AppSettingsView().environmentObject(PlayerSettingsStore.shared))
        }
        await step("ui.sources") {
            try await showcase("媒体源", SourceBrowserView()
                .environmentObject(MediaSourceStore.shared)
                .environmentObject(PlayerSettingsStore.shared))
        }
        await step("ui.addSourceSMB") {
            try await showcase("添加SMB", AddMediaSourceView(initialProtocol: .smb) { _ in }
                .environmentObject(PlayerSettingsStore.shared))
        }
        await step("ui.home") {
            try await showcase("首页", HomeLibraryView()
                .environmentObject(MediaSourceStore.shared)
                .environmentObject(WatchHistoryStore.shared)
                .environmentObject(PlayerSettingsStore.shared))
        }

        await step("unit.soundBundleAssets") {
            for cue in AppleTVSoundEffects.Cue.allCases {
                let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "wav")
                try require(url != nil, "打包产物中缺少定制交互音效：\(cue.rawValue).wav")
            }
            AppleTVSoundEffects.prepareIfNeeded()
            return "all \(AppleTVSoundEffects.Cue.allCases.count) custom wav sound effects bundled"
        }

        await step("unit.keychainAndSanitization") {
            try runKeychainAndSanitizationTests()
        }
        await step("unit.dlnaXmlAndSSDP") {
            try runDLNAXmlAndSSDPTests()
        }
        await step("unit.smbSubtitleMatching") {
            try runSMBSubtitleMatchingTests()
        }
        await step("unit.hostNormalization") {
            try runHostNormalizationTests()
        }

        // 确保前置单元测试完成后媒体源仍为冒烟测试夹具配置
        MediaSourceStore.shared.sources = [webdav] + (smb.map { [$0] } ?? [])

        var webdavMovie: MediaItem?
        await step("browse.webdav.root") {
            let items = try await webdavItems(webdav, path: "/")
            let titles = items.map(\.title)
            try require(titles.contains("Movies"), "根目录列表里没有 Movies：\(titles)")
            try require(titles.contains("中文 目录"), "根目录列表丢了中文目录（百分号编码/NFC）：\(titles)")
            try require(items.contains { $0.isDirectory }, "根目录没有目录项")
            return describe(items)
        }
        await step("browse.webdav.movies") {
            let items = try await webdavItems(webdav, path: "/Movies")
            let movie = items.first { $0.title == "sample.mkv" }
            try require(movie != nil, "没有 sample.mkv：\(describe(items))")
            try require(movie?.externalSubtitles.count == 2, "sample.mkv 应带 2 条同目录外挂字幕：\(describe(items))")
            webdavMovie = movie
            return describe(items)
        }

        if let smb {
            await step("browse.smb.root") {
                let items = try await SMBSourceClient().listDirectory(source: smb, path: "/")
                let titles = items.map(\.title)
                try require(titles.contains("Movies"), "SMB 根目录没有 Movies：\(titles)")
                return describe(items)
            }
            await step("play.smb.mkv") {
                let items = try await SMBSourceClient().listDirectory(source: smb, path: "/Movies")
                guard let movie = items.first(where: { $0.title == "sample.mkv" }) else {
                    throw SmokeTestFailure.failed("SMB /Movies 里没有 sample.mkv：\(describe(items))")
                }
                try require(movie.externalSubtitles.count == 2, "SMB sample.mkv 应匹配 2 条同目录外挂字幕：\(describe(items))")
                return try await play(movie, source: smb, wantSubtitles: true)
            }
        }

        await step("play.webdav.mkv") {
            guard let movie = webdavMovie else {
                throw SmokeTestFailure.failed("browse.webdav.movies 没有拿到 sample.mkv")
            }
            return try await play(movie, source: webdav, wantSubtitles: true)
        }

        if hlsPort > 0 {
            await step("play.hls") {
                guard let url = URL(string: "http://127.0.0.1:\(hlsPort)/hls/sample.m3u8") else {
                    throw SmokeTestFailure.failed("HLS URL 构造失败")
                }
                let item = MediaItem(
                    id: "hls:smoke",
                    title: "HLS 测试流",
                    isDirectory: false,
                    streamURL: url,
                    protocolType: .directURL,
                    remotePath: "/hls/sample.m3u8"
                )
                return try await play(item, source: nil, wantSubtitles: false)
            }
        }

        report.finishedAt = Date().timeIntervalSince1970
        flush()
    }

    // MARK: - 步骤与断言

    static func step(_ name: String, _ body: () async throws -> String) async {
        let start = Date()
        var entry = Step(name: name, ok: true, startedAt: start.timeIntervalSince1970,
                         durationSeconds: 0, detail: "", message: nil)
        do {
            entry.detail = try await body()
        } catch {
            entry.ok = false
            entry.message = error.localizedDescription
        }
        entry.durationSeconds = Date().timeIntervalSince(start)
        report.steps.append(entry)
        report.ok = report.ok && entry.ok
        flush()
    }

    static func fail(_ name: String, _ message: String) {
        report.steps.append(Step(name: name, ok: false, startedAt: Date().timeIntervalSince1970,
                                 durationSeconds: 0, detail: "", message: message))
        report.ok = false
        report.finishedAt = Date().timeIntervalSince1970
        flush()
    }

    static func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw SmokeTestFailure.failed(message()) }
    }

    static func startWatchdog() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 330_000_000_000)
            if report.finishedAt == nil {
                report.ok = false
                report.steps.append(Step(name: "watchdog", ok: false,
                                         startedAt: Date().timeIntervalSince1970,
                                         durationSeconds: 330, detail: "",
                                         message: "整轮冒烟测试超过时间预算（330 秒）"))
                report.finishedAt = Date().timeIntervalSince1970
                flush()
            }
        }
    }

    // MARK: - 目录浏览

    static func webdavItems(_ source: MediaSourceConfig, path: String) async throws -> [MediaItem] {
        try await WebDAVClient(allowSelfSignedLAN: false).listDirectory(source: source, path: path)
    }

    static func describe(_ items: [MediaItem]) -> String {
        items.map { item in
            var line = "\(item.isDirectory ? "D" : "F") \(item.title)"
            if let size = item.fileSize { line += " [\(size)B]" }
            if !item.externalSubtitles.isEmpty { line += " [subs=\(item.externalSubtitles.count)]" }
            return line
        }.joined(separator: "; ")
    }

    // MARK: - 界面截图用

    static func showcase<V: View>(_ name: String, _ view: V) async throws -> String {
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .fullScreen
        host.view.backgroundColor = .black
        present(host)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await dismissAll()
        return "已展示 \(name)"
    }

    // MARK: - 播放

    static func play(_ item: MediaItem, source: MediaSourceConfig?, wantSubtitles: Bool) async throws -> String {
        let controller = PlaybackController()
        let host = UIHostingController(rootView: PlayerScreenView(
            item: item,
            playlist: [item],
            sourceConfig: source,
            controller: controller
        ).environmentObject(PlayerSettingsStore.shared))
        host.modalPresentationStyle = .fullScreen
        host.view.backgroundColor = .black
        present(host)

        guard let engine = controller.engine else {
            throw SmokeTestFailure.failed("PlaybackController 初始化引擎失败：\(controller.activeErrorMessage ?? "未知")")
        }
        do {
            try await waitFor("开始播放", 45) {
                if case .error = engine.state { return true }
                return engine.state == .playing && engine.clock.currentTime >= 2.5
            }
            if case .error(let message) = engine.state {
                throw SmokeTestFailure.failed("引擎报错：\(message)")
            }

            var detail = "state=\(engine.state) pos=\(rounded(engine.clock.currentTime))"
            detail += " dur=\(rounded(engine.duration)) route=\(engine.videoRoute.rawValue)"
            detail += " vdec=\(engine.activeVideoDecoder ?? "-") adec=\(engine.activeAudioDecoder ?? "-")"
            detail += " fmt=\(engine.videoFormat)"

            if wantSubtitles {
                guard let track = engine.subtitleTracks.first(where: { $0.isExternal }) else {
                    throw SmokeTestFailure.failed("没有外挂字幕轨：\(engine.subtitleTracks.map { "\($0.id):\($0.name):external=\($0.isExternal)" })")
                }
                engine.selectSubtitleTrack(index: track.id)
                try await waitFor("外挂字幕出句", 15) { !engine.subtitleCues.isEmpty }
                let text = engine.subtitleCues.compactMap(\.text).first ?? "-"
                detail += " subtitleCues=\(engine.subtitleCues.count) cue=\"\(text)\""
            }

            await engine.seek(to: 12)
            try await waitFor("跳转到 12 秒", 20) {
                engine.state == .playing && abs(engine.clock.currentTime - 12) < 2
            }
            detail += " afterSeek=\(rounded(engine.clock.currentTime))"

            controller.scrubEngine.beginPress(direction: .forward)
            try await waitFor("长按变速模式", 6) { controller.scrubEngine.isScrubbing }
            let previewDeadline = Date().addingTimeInterval(8)
            while Date() < previewDeadline && controller.scrubEngine.previewImage == nil {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            let preview = controller.scrubEngine.previewImage != nil
            let speed = controller.scrubEngine.speedMultiplier
            controller.scrubEngine.endPress()
            detail += " scrubPreview=\(preview ? "yes" : "no") speed=\(rounded(speed))"

            controller.stopAndDismiss()
            await dismissAll()
            return detail
        } catch {
            var context = "state=\(engine.state) pos=\(rounded(engine.clock.currentTime)) dur=\(rounded(engine.duration))"
            if let info = engine.errorInfo { context += " error=\(info.kind.rawValue): \(info.message)" }
            controller.stopAndDismiss()
            await dismissAll()
            throw SmokeTestFailure.failed("\(error.localizedDescription) [\(context)]")
        }
    }

    static func waitFor(_ what: String, _ seconds: TimeInterval, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        throw SmokeTestFailure.failed("等待「\(what)」超时（\(Int(seconds)) 秒）")
    }

    static func rounded(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    // MARK: - 窗口与结果文件

    static func rootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        return (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    }

    /// 从 App.init 启动时窗口还没建好，等它出现再开始
    static func waitForRoot() async throws {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if rootViewController() != nil { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        throw SmokeTestFailure.failed("30 秒内没有拿到 App 的窗口")
    }

    static func present(_ controller: UIViewController) {
        guard let root = rootViewController() else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(controller, animated: false)
    }

    static func dismissAll() async {
        rootViewController()?.dismiss(animated: false)
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    // MARK: - 单元测试（Keychain / 脱敏 / XML 转义 / SMB 字幕 / Host 清理）

    static func runKeychainAndSanitizationTests() throws -> String {
        let probeId = UUID()
        let creds = SourceCredentials(password: "P@ssSecret!9", apiToken: "TokSecret_ABC")
        KeychainCredentialStore.shared.save(creds, for: probeId)
        let loaded = KeychainCredentialStore.shared.load(for: probeId)
        try require(loaded == creds, "Keychain 存取往返不匹配")
        let backend = KeychainCredentialStore.shared.isUsingMemoryFallback
            ? "mem-fallback(\(KeychainCredentialStore.shared.lastStatus))"
            : "native-keychain"
        KeychainCredentialStore.shared.delete(for: probeId)
        try require(KeychainCredentialStore.shared.load(for: probeId) == nil, "Keychain 删除后仍可读出凭据")

        // 验证 MediaSourceStore 迁移旧明文数据并在 UserDefaults 中清除密码/Token
        let legacyId = UUID()
        let legacySource = MediaSourceConfig(
            id: legacyId,
            name: "Legacy Emby",
            protocolType: .emby,
            host: "192.168.1.99",
            port: 8096,
            username: "alice",
            password: "LegacyPassword!123",
            apiToken: "LegacyToken!456"
        )
        let encodedLegacy = try JSONEncoder().encode([legacySource])
        UserDefaults.standard.set(encodedLegacy, forKey: "AetherTV.MediaSources.v1")
        MediaSourceStore.shared.reloadFromStorage()

        let migratedInMemory = MediaSourceStore.shared.sources.first(where: { $0.id == legacyId })
        try require(migratedInMemory?.password == "LegacyPassword!123", "旧数据迁移后内存中密码缺失")
        try require(migratedInMemory?.apiToken == "LegacyToken!456", "旧数据迁移后内存中 Token 缺失")

        let storedSourceData = UserDefaults.standard.data(forKey: "AetherTV.MediaSources.v1") ?? Data()
        let storedSourceJSON = String(data: storedSourceData, encoding: .utf8) ?? ""
        try require(!storedSourceJSON.contains("LegacyPassword!123"), "UserDefaults 中仍存在明文 password")
        try require(!storedSourceJSON.contains("LegacyToken!456"), "UserDefaults 中仍存在明文 apiToken")
        MediaSourceStore.shared.remove(id: legacyId)

        // 验证 WatchHistoryStore 脱敏（httpHeaders、URL Query、externalSubtitles）及单片轨道记忆
        let secretItem = MediaItem(
            id: "unit:secret:item",
            title: "Secret Movie",
            isDirectory: false,
            streamURL: URL(string: "http://192.168.1.20:8096/Videos/1/stream?Static=true&api_key=LEAK_API_KEY"),
            posterURL: URL(string: "http://192.168.1.20:8096/Items/1/Images/Primary?maxWidth=480&X-Plex-Token=LEAK_PLEX_TOKEN"),
            durationSeconds: 1200,
            sourceId: nil,
            protocolType: .emby,
            remotePath: "1",
            httpHeaders: [
                "Authorization": "Basic LEAK_BASIC",
                "X-Emby-Token": "LEAK_EMBY",
                "X-Emby-Authorization": "MediaBrowser Token=\"LEAK_EMBY_AUTH\"",
                "X-Plex-Token": "LEAK_PLEX_HDR",
                "Cookie": "session=LEAK_COOKIE",
                "User-Agent": "AetherTV/1.0"
            ],
            externalSubtitles: [
                ExternalSubtitleReference(
                    title: "sub.srt",
                    language: "zh",
                    url: URL(string: "http://192.168.1.20:8096/Subtitles/0/Stream.srt?api_key=LEAK_SUB_KEY")!,
                    formatHint: "srt",
                    httpHeaders: ["X-Emby-Token": "LEAK_SUB_HDR", "Accept": "*/*"]
                )
            ],
            serverItemId: "1"
        )

        WatchHistoryStore.shared.recordProgress(item: secretItem, position: 120, duration: 1200)
        WatchHistoryStore.shared.recordTrackSelection(
            for: secretItem,
            audioTrackId: 2,
            primarySubtitleTrackId: 100_001,
            secondarySubtitleTrackId: 5,
            aspectMode: .aspectFill
        )
        WatchHistoryStore.shared.toggleFavorite(secretItem)

        let historyJSON = String(data: UserDefaults.standard.data(forKey: "AetherTV.WatchHistory.v1") ?? Data(), encoding: .utf8) ?? ""
        let favJSON = String(data: UserDefaults.standard.data(forKey: "AetherTV.Favorites.v1") ?? Data(), encoding: .utf8) ?? ""
        for forbidden in ["LEAK_API_KEY", "LEAK_PLEX_TOKEN", "LEAK_BASIC", "LEAK_EMBY", "LEAK_EMBY_AUTH", "LEAK_PLEX_HDR", "LEAK_COOKIE", "LEAK_SUB_KEY", "LEAK_SUB_HDR"] {
            try require(!historyJSON.contains(forbidden), "观看记录落盘包含未脱敏凭据：\(forbidden)")
            try require(!favJSON.contains(forbidden), "收藏夹落盘包含未脱敏凭据：\(forbidden)")
        }
        try require(historyJSON.contains("AetherTV\\/1.0") || historyJSON.contains("AetherTV/1.0"), "脱敏误删了非敏感 User-Agent")

        let memory = WatchHistoryStore.shared.trackMemory(for: secretItem.id)
        try require(memory?.audioTrackId == 2 && memory?.primarySubtitleTrackId == 100_001 && memory?.secondarySubtitleTrackId == 5 && memory?.aspectMode == .aspectFill,
                    "单片轨道与画面比例记忆未正确保存")

        WatchHistoryStore.shared.clearProgress(for: secretItem.id)
        WatchHistoryStore.shared.toggleFavorite(secretItem)
        return "keychain=\(backend), migration+sanitization+trackMemory OK"
    }

    static func runDLNAXmlAndSSDPTests() throws -> String {
        let escaped = DLNADiscoveryClient.xmlEscape("0&a<b\"c'd>")
        try require(escaped == "0&amp;a&lt;b&quot;c&apos;d&gt;", "DLNA XML 转义错误：\(escaped)")

        let ssdpSample = "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nLocation: http://192.168.1.50:8200/rootDesc.xml\r\nST: urn:schemas-upnp-org:service:ContentDirectory:1\r\n\r\n"
        let locs = DLNADiscoveryClient.parseSSDPResponseLocations(ssdpSample)
        try require(locs.first?.absoluteString == "http://192.168.1.50:8200/rootDesc.xml", "SSDP LOCATION 解析失败：\(locs)")

        let xml = """
        <?xml version="1.0"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <device>
            <friendlyName>LivingRoom NAS</friendlyName>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>
                <controlURL>/ctl/ContentDir</controlURL>
              </service>
            </serviceList>
          </device>
        </root>
        """
        let dev = DLNADiscoveryClient.parseDeviceDescription(
            data: Data(xml.utf8),
            locationURL: URL(string: "http://192.168.1.50:8200/rootDesc.xml")!
        )
        try require(dev?.friendlyName == "LivingRoom NAS", "DLNA friendlyName 解析失败")
        try require(dev?.controlURL.absoluteString == "http://192.168.1.50:8200/ctl/ContentDir", "DLNA controlURL 解析失败：\(dev?.controlURL.absoluteString ?? "nil")")
        return "xmlEscape + SSDP + DeviceXML OK"
    }

    static func runSMBSubtitleMatchingTests() throws -> String {
        let matched = SMBSourceClient.matchSubtitles(
            videoName: "Ep1.mkv",
            subtitleFiles: ["Ep1.zh.ass", "Ep1.en.srt", "Ep10.zh.srt", "other.srt"]
        )
        try require(matched == ["Ep1.zh.ass", "Ep1.en.srt"], "SMB 字幕边界匹配失败：\(matched)")

        let nfdSub = "Cafe\u{0301}.zh.srt"
        let nfdMatched = SMBSourceClient.matchSubtitles(videoName: "Café.mkv", subtitleFiles: [nfdSub])
        try require(nfdMatched == [nfdSub] && nfdMatched.first?.unicodeScalars.count == nfdSub.unicodeScalars.count,
                    "SMB 字幕匹配未保留服务器原始字节")
        return "matched=\(matched.count), rawBytesPreserved=true"
    }

    static func runHostNormalizationTests() throws -> String {
        let cfg1 = MediaSourceConfig(name: "t1", protocolType: .webdav, host: "  Http://192.168.1.10/  ", port: 5005)
        let cfg2 = MediaSourceConfig(name: "t2", protocolType: .smb, host: "Smb://nas.local/", port: 445)
        let cfg3 = MediaSourceConfig(name: "t3", protocolType: .emby, host: "HTTPS://emby.home/", port: 443, useHTTPS: true)
        try require(cfg1.cleanedHost == "192.168.1.10", "Http:// 前缀未清除：\(cfg1.cleanedHost)")
        try require(cfg2.cleanedHost == "nas.local", "Smb:// 前缀未清除：\(cfg2.cleanedHost)")
        try require(cfg3.cleanedHost == "emby.home", "HTTPS:// 前缀未清除：\(cfg3.cleanedHost)")
        return "case-insensitive host cleanup OK"
    }

    static var resultURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("smoke-test-result.json")
    }

    static func flush() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return }
        try? data.write(to: resultURL, options: .atomic)
    }
}
#endif
