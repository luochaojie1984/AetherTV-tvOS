# AetherTV — 原生苹果风格 Apple TV 全协议局域网播放器

基于开源播放引擎 [AetherEngine](https://github.com/superuser404notfound/AetherEngine) 构建的 tvOS 18+ 原生风格视频播放器，专为自签名 Apple TV 客厅观影场景设计。

## 核心特性

- **苹果原生视觉与交互体验**：复用 tvOS 原生焦点引擎（Focus Engine）、毛玻璃视觉层级与系统交互音效。
- **贴底极简原生进度条**：播放进度条锚定于屏幕最底部（最小底边距），集成缓冲轨、章节刻度点与实时格式徽标（Dolby Vision / HDR10+ / HDR10 / HLG / Dolby Atmos）。
- **长按顺滑变速快进/快退 + 实时画面预览**：
  - 短按左/右方向键：原生 ±10 秒跳转。
  - 长按左/右方向键：按住时间越长，速度按非线性曲线从 `4x` 平滑加速至最高 `120x`；同时动态匹配刷新频率调用缓存关键帧预览（`scrubPreviewFrame`）与单并发节流 Seek，实现**快进越快、画面切换越快**的实时预览效果，且不会打爆局域网连接或解码队列。
- **主流编码软硬解与原盘级音画**：
  - 硬解（VideoToolbox）+ 软解（`dav1d` / `libavcodec`）双通道，支持播放中热切换。
  - 完整支持 HDR10 / HDR10+ / HLG / Dolby Vision（含防绿紫偏色的仅基础层模式）与 Dolby Atmos 透传、eARC 无损多声道 LPCM / ARC 环绕声桥接。
- **特效字幕与双语字幕**：
  - 支持 SRT / VTT / ASS / SSA（保留颜色、粗斜体、九宫格定位等特效样式）及 PGS / DVB / DVD 图形字幕。
  - 支持主副双语字幕、字体大小、底部垂直位置、颜色、底框透明度、时间延迟偏移微调，以及 WebDAV 同目录外挂字幕自动匹配。
- **主流局域网协议全覆盖与避坑防护**：
  - 支持 **WebDAV、SMB（AetherEngineSMB）、Emby、Jellyfin、Plex、DLNA、HTTP 直链**。
  - 内置路径 Unicode NFC 规范化与防二次百分号编码、同源重定向保留 `Authorization` / Token、64 位大文件长度解析、局域网自签名 HTTPS 证书信任（`EngineTLS.serverTrustEvaluator`）、单连接限流与长连接拉流开关。
- **主流播放器常用功能**：
  - 自动续播记忆、剧集结尾自动预热下一集（`AetherEngine.prewarm`）并连播、跳过片头/片尾、倍速播放（0.5x~2.0x）、画面比例切换、对白增强、夜间模式、响度均衡、音频同步延迟、低清 SDR 超分放大、章节跳转、睡眠定时器、1Hz 实时码率/帧率/解码器 HUD。

---

## GitHub Actions 一键云端打包无签名 `.ipa`（无需本地 Mac）

1. 在 GitHub 创建一个新的仓库（公开或私有均可）。
2. 将本压缩包解压后的全部文件（包含隐藏目录 `.github/workflows/build-tvos-ipa.yml`）推送到仓库的 `main` 分支。
3. 打开仓库顶部的 **Actions** 页面，选择 **Build AetherTV Unsigned IPA (tvOS)**，点击右侧 **Run workflow**（或推送代码后自动触发）。
4. 等待编译完成后，在本次运行页面的 **Artifacts** 区域下载 `AetherTV-tvOS-unsigned-ipa`，解压即可得到 **`AetherTV-tvOS-unsigned.ipa`**。
5. 将该无签名 `.ipa` 交给路由器上的自签程序签名并安装到 Apple TV。

构建步骤固定为：`brew install xcodegen` → `xcodegen generate` → `xcodebuild -resolvePackageDependencies` → `xcodebuild -sdk appletvos -destination "generic/platform=tvOS" CODE_SIGNING_ALLOWED=NO` → 把 `AetherTV.app` 打进 `Payload/` 压成 `.ipa`。

### 构建环境

[AetherEngine](https://github.com/superuser404notfound/AetherEngine) 官方支持的工具链是 **Xcode 27（Swift 6.4）**，所以工作流默认跑在 GitHub 的 **`xcode-27`** runner 标签上（macOS 27，镜像自带 Xcode 27.x）。注意 `macos-latest` 标签目前指向 macOS 26，镜像里最高只有 Xcode 26.6；上游只在每个版本发布前用 Xcode 26.3 做一次 best-effort 兼容构建，不作为门禁。

手动触发时可选项：

| 输入 | 默认 | 说明 |
| :--- | :--- | :--- |
| `runner` | `xcode-27` | 换成 `macos-latest` 可试 Xcode 26.6 兼容构建 |
| `xcode_version` | 空 | 指定 Xcode 路径；留空沿用镜像默认 Xcode |
| `traits` | `none` | 见下方「可选组件」 |

构建失败时，运行页面会多出一个 `AetherTV-xcodebuild-log` 产物，里面是完整的编译日志。

> **如果 Xcode 版本偏低**：工作流会给出警告并继续。构建因此失败时，把 `runner` 改回 `xcode-27`；自建 Mac 无法升级的话，再在 `project.yml` 里把 `AetherEngine` 固定到支持该 Xcode 的旧 tag。

### 可选组件（Package Traits）

AetherEngine 的 5 个高级组件默认**都不编入**，对应的 `LoadOptions` 会被接受但不生效：

| Trait | 作用 |
| :--- | :--- |
| `TrueHDObjectAudio` | TrueHD Atmos 天空声道 |
| `DTSXObjectAudio` | DTS:X 天空声道 |
| `DolbyVisionFelCurves` | 杜比视界 Profile 7 FEL（曲线折叠，走原生路径） |
| `DolbyVisionStillReshaping` | 杜比视界 Profile 5 / 10.0 的预览缩略图与静帧（长按快进有彩色预览需要它） |
| `DualLayerDolbyVision` | Profile 7 FEL 双层合成（软件路径） |

- `traits = recommended`：开启前四项。原盘 Remux 较多、又想要 Profile 5 实时预览缩略图，选这个。
- `traits = all`：再加上 `DualLayerDolbyVision`。上游明确不建议对外分发（涉及在途的杜比专利），自己签名自用请自行判断；这些组件可能需要的第三方专利许可以及分发责任，由开启者自己承担。

### 工程配置里的几个硬性前提

这几项任意一项缺失，首次构建就会直接失败，改动 `project.yml` 时请留意：

- **`scheme: {}`**：XcodeGen 不会为 application 目标自动生成 scheme，而 `xcodebuild -scheme AetherTV` 需要共享 scheme。
- **`Assets.xcassets/App Icon & Top Shelf Image.brandassets`**：XcodeGen 给 tvOS 应用默认写入 `ASSETCATALOG_COMPILER_APPICON_NAME = App Icon & Top Shelf Image`，资源目录里没有同名图标时 `actool` 会报错；启动图绑定已显式清空。
- **`SWIFT_VERSION: 5.0`**：Swift 6 语言模式下并发检查恒为 error，`SWIFT_STRICT_CONCURRENCY: minimal` 会被整个忽略；要让未标注 `Sendable` 的代码只告警，必须用 Swift 5 语言模式。

---

## Siri Remote 遥控器快捷键

| 按键操作 | 功能 |
| :--- | :--- |
| **短按 左 / 右方向键** | 快退 / 快进 10 秒 |
| **长按 左 / 右方向键** | 顺滑变速快进/快退（按越久越快）+ 实时画面预览，松手精准落点 |
| **确认键 / 播放暂停键** | 显示进度条 / 播放或暂停 |
| **下方向键** | 打开毛玻璃设置面板（字幕、音频、解码、章节、倍速、睡眠定时） |
| **上方向键** | 开启 / 关闭 1Hz 实时码率、解码器与网络吞吐 HUD |
| **返回键（Menu）** | 隐藏浮层 / 退出播放并自动保存续播进度 |

---

## 局域网协议避坑说明

- **SMB**：进入 SMB 媒体源后可逐级浏览共享内的文件夹，凭据只保存在媒体源配置里（不随观看记录/收藏落盘）。播放走 `AetherEngineSMB` 的自定义 reader（ISO / IMG 镜像会保留引擎的光盘探测）。`AetherEngineSMB` 使用 SMB 2.0.2 / 2.1（NTLMv2 或访客），请在群晖 / 飞牛 / 威联通 / Windows 中确保**最小 SMB 协议设为 SMB2**，不要强制启用 SMB3 加密或强制签名。SMB 下暂不支持同目录外挂字幕，需要的话请在 NAS 上同时开启 WebDAV 或 Emby / Jellyfin。
- **WebDAV（含 Alist / OpenList / 网盘反代）**：如果网盘反代限制同时连接数或频繁 Range 请求会被 403/429 限流，请在添加媒体源时勾选「单连接限流模式」或「保持长连接拉流」。
- **自签名 HTTPS**：若局域网 NAS 或 Emby/Jellyfin 使用自签名证书，请在 App「设置 → 信任局域网自签名 HTTPS 证书」保持开启（仅对私有局域网 IP / `.local` / `.lan` 生效，不影响公网安全）。
