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
        completion(TodayEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = TodayEntry(date: Date(), snapshot: WidgetBridge.read())
        // 15 分钟兜底刷新；主 App 数据一变会主动 reload，正常不必等这一轮。
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date())
            ?? Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
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
