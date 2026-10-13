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
        let now = Date()
        let cached = WidgetBridge.read()
        Task {
            // 系统叫醒的是扩展进程自己，跟主 App 死没死无关，
            // 所以先自己问一次 HealthKit——App 被划掉后桌面也能有新数字。
            let health = await WidgetHealthReader.todayWithTimeout()
            let entry = TodayEntry(date: now, snapshot: Self.merged(cached, with: health, now: now))
            completion(Timeline(entries: [entry], policy: .after(Self.nextRefresh(after: now))))
        }
    }

    /// 用 widget 自己查到的最新健康数，覆盖快照里对应的两个字段。
    /// - 没有底稿（App 从没写过快照）：不拼。目标热量只有 App 知道，硬凑会显示「剩余 -800」这种假数字，
    ///   不如老实提示去打开 App。
    /// - 跨天：不拼。摄入与手动记录该由 App 重算，这里只负责健康那一半。
    static func merged(
        _ cached: WidgetSnapshot?,
        with health: WidgetHealthReader.TodayHealth?,
        now: Date
    ) -> WidgetSnapshot? {
        guard let cached else { return nil }
        guard let health, cached.isToday else { return cached }
        return WidgetSnapshot(
            savedAt: now,
            dayStart: cached.dayStart,
            intakeKcal: cached.intakeKcal,
            targetKcal: cached.targetKcal,
            burnKcal: health.activeKcal + cached.manualBurnKcal,
            steps: health.steps,
            distanceKm: cached.distanceKm,
            exerciseMinutes: cached.exerciseMinutes,
            weightKg: cached.weightKg,
            targetWeightKg: cached.targetWeightKg,
            healthBurnKcal: health.activeKcal,
            manualBurnKcal: cached.manualBurnKcal
        )
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
