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
        let displaySize = context.displaySize
        let family = String(describing: context.family)

        // 关键：扩展在这里「自己直接读健康」，绕开 BGAppRefresh 不被按时叫醒的问题。
        // 之前只有主 App 打开时才写快照，所以桌面组件必须开 App 才更新。
        Task {
            let stored = WidgetBridge.read()
            let merged = await Self.mergedWithHealth(stored)

            WidgetDiagnostics.recordTimeline(
                snapshotMissing: merged == nil,
                displaySize: displaySize,
                family: family
            )
            let entry = TodayEntry(date: now, snapshot: merged)
            // 15 分钟兜底 + 若次日 00:05 的跨天临界点更早则提前，
            // 免得快照过期后桌面挂着昨天的数字。
            completion(Timeline(entries: [entry], policy: .after(Self.nextRefresh(after: now))))
        }
    }

    /// 把「刚才读到的健康今日数据」合并进共享快照。
    ///
    /// - 快照存在：用健康的步数 / 活跃消耗 / 锻炼分钟 / 距离覆盖对应字段，
    ///   摄入、目标、手动运动等 App 侧数据保持不动（widget 读不到 CoreData）。
    /// - 快照不存在但健康读到了：用健康数据拼一份最小快照，至少能显示运动数字。
    /// - 健康读不到（未授权 / TrollStore 未签名 entitlement 不被信任）：原样返回快照，绝不比原来差。
    static func mergedWithHealth(_ stored: WidgetSnapshot?) async -> WidgetSnapshot? {
        let activity = await WidgetHealthReader.fetchTodayActivity()
        guard let activity else { return stored }

        let today = Calendar.current.startOfDay(for: Date())

        guard var snapshot = stored, snapshot.dayStart == today else {
            // 没有今天的快照：用健康数据凑一份，摄入 / 目标等留给 App 下次补。
            return WidgetSnapshot(
                savedAt: Date(),
                dayStart: today,
                intakeKcal: 0,
                targetKcal: stored?.targetKcal ?? 0,
                burnKcal: activity.activeKcal,
                steps: Double(activity.steps),
                distanceKm: activity.distanceKm,
                exerciseMinutes: Double(activity.exerciseMinutes),
                weightKg: stored?.weightKg,
                targetWeightKg: stored?.targetWeightKg,
                healthBurnKcal: activity.activeKcal,
                manualBurnKcal: 0
            )
        }

        // 用健康值覆盖「健康来源」的字段，手动记录那半保持快照里的原值。
        let manualBurn = snapshot.manualBurnKcal
        snapshot.steps = Double(activity.steps)
        snapshot.healthBurnKcal = activity.activeKcal
        snapshot.burnKcal = activity.activeKcal + manualBurn
        snapshot.exerciseMinutes = Double(activity.exerciseMinutes)
        snapshot.distanceKm = activity.distanceKm
        snapshot.savedAt = Date()
        return snapshot
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
