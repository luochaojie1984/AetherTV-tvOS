import Foundation

/// CI 冒烟测试的接入点。
///
/// 只有启动参数里带 `--smoke-test`、并且构建配置编入了测试代码（`#if SMOKE_TEST`）时才会运行。
/// 测试步骤在 `Tests/SmokeTest/App/SmokeTestRunner.swift`，Release 构建里 `runner` 恒为 nil。
enum SmokeTest {
    /// 由测试代码在镜像加载时（`+load`）赋值。测试代码只在 SmokeTest 构建配置下存在。
    nonisolated(unsafe) static var runner: (@MainActor () async -> Void)?

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--smoke-test")
    }
}
