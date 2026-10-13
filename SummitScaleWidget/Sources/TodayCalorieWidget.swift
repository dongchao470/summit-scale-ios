import SwiftUI
import WidgetKit

/// 一条时间线数据：整个 widget 只吃这一份快照。
struct TodayEntry: TimelineEntry {
    let date: Date
    /// nil 表示主 App 还没写过快照（共享通道不通或从没打开过 App）。
    let snapshot: WidgetSnapshot?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        // 桌面预览 / widget 图库走占位数据，别显示空态。
        let snapshot = WidgetBridge.read() ?? (context.isPreview ? .placeholder : nil)
        WidgetDiagnostics.recordSnapshotRequest(snapshotMissing: snapshot == nil, displaySize: context.displaySize)
        completion(TodayEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetBridge.read()
        // 顺带把系统真正给到的尺寸写进容器：版式该按这个排，不是按 widget 外框推算。
        WidgetDiagnostics.recordTimeline(
            snapshotMissing: snapshot == nil,
            displaySize: context.displaySize,
            family: String(describing: context.family)
        )
        let entry = TodayEntry(date: now, snapshot: snapshot)
        // widget 自己只会「重读快照」，快照由主 App 写、由后台刷新补。
        // 所以这里只决定什么时候再读一次：常规 15 分钟兜底；
        // 若次日 00:05 的跨天临界点更早，就提前到那一刻——
        // 否则快照过期后桌面会挂着昨天的数字直到兜底刷新。
        completion(Timeline(entries: [entry], policy: .after(Self.nextRefresh(after: now))))
    }

    /// 下一次刷新时刻。
    static func nextRefresh(after now: Date) -> Date {
        let calendar = Calendar.current
        let fallback = calendar.date(byAdding: .minute, value: 15, to: now)
            ?? now.addingTimeInterval(15 * 60)

        guard
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
            let boundary = calendar.date(byAdding: .minute, value: 5, to: tomorrow),
            boundary < fallback
        else {
            return fallback
        }
        return boundary
    }
}

struct TodayCalorieWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayCalorieWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("今日热量")
        .description("剩余可吃、消耗、步数与距离，瞄一眼就够。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
