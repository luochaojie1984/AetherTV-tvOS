import SwiftUI
import AetherEngine

struct AppSettingsView: View {
    @EnvironmentObject private var settings: PlayerSettingsStore

    var body: some View {
        NavigationStack {
            Form {
                Section("视频与 HDR") {
                    Picker("默认解码方式", selection: $settings.decodePreference) {
                        ForEach(DecodePreference.allCases) { pref in
                            Text(pref.rawValue).tag(pref)
                        }
                    }
                    Picker("默认画面比例", selection: $settings.aspectMode) {
                        ForEach(VideoAspectMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Picker("杜比视界策略", selection: $settings.dolbyVisionMode) {
                        ForEach(DolbyVisionMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Toggle("匹配动态范围与帧率（推荐开启）", isOn: $settings.matchContentEnabled)
                    Toggle("低清 SDR 视频超分放大", isOn: $settings.upscaleLowResSDR)
                }

                Section("音频与声道") {
                    Picker("多声道桥接模式", selection: $settings.audioBridgePreference) {
                        ForEach(AudioBridgePreference.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Toggle("夜间模式（自动压缩大动态音量）", isOn: $settings.nightModeEnabled)
                    Toggle("响度均衡（拉升偏小声影片）", isOn: $settings.loudnessNormalizeEnabled)
                }

                Section("字幕默认偏好") {
                    TextField("首选音轨语言（逗号分隔）", text: $settings.preferredAudioLanguage)
                    TextField("首选字幕语言（逗号分隔）", text: $settings.preferredSubtitleLanguage)
                    Toggle("保留 ASS 特效字幕样式", isOn: $settings.preserveASSStyling)
                    Toggle("双语副字幕显示在屏幕顶部", isOn: $settings.secondarySubtitleAtTop)
                }

                Section("播放体验与音效") {
                    Toggle("自动续播上次观看位置", isOn: $settings.autoResumePlayback)
                    Toggle("剧集自动预热并连播下一集", isOn: $settings.autoPlayNextEpisode)
                    Toggle("苹果原生风格交互与快进刻度音效", isOn: $settings.enableSystemSoundEffects)
                    Toggle("默认显示 1Hz 实时码率/解码 HUD", isOn: $settings.showStatsHUD)
                }

                Section("局域网与证书避坑") {
                    Toggle("信任局域网自签名 HTTPS 证书", isOn: $settings.allowSelfSignedCertificates)
                    Stepper("前向缓冲分片数：\(settings.forwardBufferSegments)（约 \(settings.forwardBufferSegments * 4) 秒）", value: $settings.forwardBufferSegments, in: 4...40, step: 2)
                }

                Section("当前 Apple TV 显示能力与引擎诊断") {
                    let caps = AetherEngine.displayCapabilities
                    LabeledContent("AetherEngine 版本", value: AetherEngine.version)
                    LabeledContent("支持 HDR", value: caps.supportsHDR ? "是" : "否")
                    LabeledContent("支持 Dolby Vision", value: caps.supportsDolbyVision ? "是" : "否")
                    LabeledContent("支持 HDR10 / HLG", value: "\(caps.supportsHDR10 ? "HDR10" : "-") / \(caps.supportsHLG ? "HLG" : "-")")
                }
            }
            .navigationTitle("设置")
        }
    }
}
