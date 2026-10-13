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
        WidgetDiagnostics.recordSnapshotRequest(snapshotMissing: snapshot == nil)
        completion(TodayEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        // 数据由主 App 写进共享容器（前台进今日页时写、退后台时由后台刷新补）。
        // widget 这边只决定「什么时候再读一次」：常规 15 分钟兜底；
        // 若次日 00:05 的跨天点更早，就提前到那一刻，免得桌面整晚挂着昨天的数字。
        let snapshot = WidgetBridge.read()
        WidgetDiagnostics.recordTimeline(snapshotMissing: snapshot == nil)
        let entry = TodayEntry(date: now, snapshot: snapshot)
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
