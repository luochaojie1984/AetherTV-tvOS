import Foundation

/// CI 冒烟测试的接入点。
///
/// 只有启动参数里带 `--smoke-test` 时才会运行；测试代码本身在
/// `Tests/SmokeTest/App/`，只随 `SMOKE_TEST` 编译条件编入（见 project.yml），
/// Release 构建里这个函数是空的。
enum SmokeTest {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--smoke-test")
    }

    static func runIfRequested() async {
        #if SMOKE_TEST
        await SmokeTestRunner.run()
        #endif
    }
}
