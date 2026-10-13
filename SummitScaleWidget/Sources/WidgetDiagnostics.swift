import Foundation

/// 把扩展的运行痕迹写进共享容器。
///
/// 为什么要留这个：桌面整块白屏时，「扩展没被系统调用」和「扩展跑了但视图渲染不出来」
/// 在手机上是同一个样子——都没字。把心跳写进 App Group，就能从容器里读出来分辨，
/// 不用再靠猜、也不用麻烦用户描述。
enum WidgetDiagnostics {
    private static let suite = "group.com.dongchao470.summit-scale"

    /// 每次时间线被系统调用时记一笔。
    static func recordTimeline(snapshotMissing: Bool) {
        let defaults = UserDefaults(suiteName: suite)
        defaults?.set(Date().timeIntervalSince1970, forKey: "diag.timelineAt")
        defaults?.set(currentVersion, forKey: "diag.version")
        defaults?.set(snapshotMissing, forKey: "diag.snapshotMissing")
    }

    /// widget 图库预览 / 桌面刷新时被问「现在该显示什么」——与时间线分开记，
    /// 这样能分辨「预览能渲染、桌面不渲染」这种分叉。
    static func recordSnapshotRequest(snapshotMissing: Bool) {
        let defaults = UserDefaults(suiteName: suite)
        defaults?.set(Date().timeIntervalSince1970, forKey: "diag.snapshotAt")
        defaults?.set(snapshotMissing, forKey: "diag.snapshotMissing")
    }

    /// 视图第一次求值时记一笔（能区分「时间线被调了但视图没渲染」）。
    static func recordViewRendered() {
        UserDefaults(suiteName: suite)?
            .set(Date().timeIntervalSince1970, forKey: "diag.viewAt")
    }

    /// 扩展自己的版本号。
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}
