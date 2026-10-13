import SwiftUI

/// 诊断版视图：只显示四行字，用来判断「扩展有没有被系统加载并渲染」。
///
/// 0.6.2–0.6.7 桌面整块白屏，但快照数据、崩溃日志、App Group 通道全都正常，
/// 于是先装这个最小视图：
/// - 能看到这几行字 → 扩展本身没问题，问题在完整视图的渲染路径；
/// - 一个字都看不到 → 问题在扩展加载（签名/注册），跟视图代码无关。
struct TodayWidgetView: View {
    let entry: TodayEntry

    private var snapshotLine: String {
        guard let snapshot = entry.snapshot else { return "快照 无" }
        return "快照 有 · 剩 \(Int(snapshot.remainingKcal))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("扩展已加载")
                .font(.system(size: 13, weight: .bold))
            Text("版本 \(WidgetDiagnostics.currentVersion)")
                .font(.system(size: 11))
            Text(snapshotLine)
                .font(.system(size: 11))
            Text("时间 \(entry.date.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear { WidgetDiagnostics.recordViewRendered() }
    }
}
