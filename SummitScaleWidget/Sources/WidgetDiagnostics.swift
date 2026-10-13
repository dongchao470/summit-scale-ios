import Foundation
import CoreGraphics

/// 把扩展的运行痕迹写进共享容器。
///
/// 为什么要留这个：桌面整块白屏时，「扩展没被系统调用」和「扩展跑了但视图渲染不出来」
/// 在手机上是同一个样子——都没字。把心跳写进 App Group，就能从容器里读出来分辨，
/// 不用再靠猜、也不用麻烦用户描述。
enum WidgetDiagnostics {
    private static let suite = "group.com.dongchao470.summit-scale"

    /// 每次时间线被系统调用时记一笔，顺带记下系统真正给到的尺寸。
    /// `displaySize` 是关键：之前按「158 − 16×2」推算内容区，真机上文字被裁，
    /// 说明推算的边距不对；这里直接记系统给的值，下次照它排。
    static func recordTimeline(snapshotMissing: Bool, displaySize: CGSize, family: String) {
        let defaults = UserDefaults(suiteName: suite)
        defaults?.set(Date().timeIntervalSince1970, forKey: "diag.timelineAt")
        defaults?.set(currentVersion, forKey: "diag.version")
        defaults?.set(snapshotMissing, forKey: "diag.snapshotMissing")
        defaults?.set("\(Int(displaySize.width))x\(Int(displaySize.height))", forKey: "diag.displaySize")
        defaults?.set(family, forKey: "diag.family")
        // 扩展进程可能随时被系统挂起，这里显式落盘，免得心跳丢了。
        defaults?.synchronize()
    }

    /// widget 图库预览 / 桌面刷新时被问「现在该显示什么」——与时间线分开记，
    /// 这样能分辨「预览能渲染、桌面不渲染」这种分叉。
    static func recordSnapshotRequest(snapshotMissing: Bool, displaySize: CGSize) {
        let defaults = UserDefaults(suiteName: suite)
        defaults?.set(Date().timeIntervalSince1970, forKey: "diag.snapshotAt")
        defaults?.set(snapshotMissing, forKey: "diag.snapshotMissing")
        defaults?.set("\(Int(displaySize.width))x\(Int(displaySize.height))", forKey: "diag.displaySize")
        defaults?.synchronize()
    }

    /// 视图第一次求值时记一笔（能区分「时间线被调了但视图没渲染」）。
    static func recordViewRendered() {
        let defaults = UserDefaults(suiteName: suite)
        defaults?.set(Date().timeIntervalSince1970, forKey: "diag.viewAt")
        defaults?.synchronize()
    }

    /// 扩展自己的版本号。
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}
