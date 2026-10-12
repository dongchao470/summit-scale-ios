import CoreData
import Foundation

/// 把「健康」里的锻炼记录搬进本地运动表。
///
/// 为什么需要它：`HealthKitManager` 只把步数、活跃消耗喂给「今日活动」卡和趋势柱，
/// 从来没往 `ActivityEntry` 写过东西，所以「运动消耗」那段列表永远是空的、
/// 趋势柱也永远没有数据。这里按 workout 的 UUID 去重补写。
///
/// 只读「健康」，不写回、不删健康里的任何数据。App 里删掉某条导入记录后，
/// 下次同步它会因为仍在健康里而重新出现——这是刻意的，避免误删后数据永久缺失。
@MainActor
enum WorkoutSync {
    /// 写进 `ActivityEntry.source` 的标记，用来跟手动记录区分。
    static let source = "healthkit"

    struct Summary {
        var inserted = 0
        var skipped = 0
        var unavailable = false

        var message: String {
            if unavailable {
                return "没拿到「健康」的读取权限，或这台设备的健康数据不可用。"
            }
            if inserted == 0 {
                return skipped > 0
                    ? "没有新的锻炼，已有的 \(skipped) 条都还在。"
                    : "近段时间健康里没有锻炼记录。"
            }
            if skipped > 0 {
                return "导入 \(inserted) 条锻炼，跳过 \(skipped) 条已存在的。"
            }
            return "导入 \(inserted) 条锻炼。"
        }
    }

    /// 拉近 `days` 天的锻炼并落库。
    /// 用户没开健康同步时回调 nil——界面不要拿它当失败提示。
    static func importRecent(days: Int = 30, completion: ((Summary?) -> Void)? = nil) {
        let health = HealthKitManager.shared
        guard health.enabledByUser, health.activitySync else {
            completion?(nil)
            return
        }

        Task { @MainActor in
            guard await health.ensureAccess() else {
                completion?(Summary(unavailable: true))
                return
            }
            health.recentWorkouts(days: days) { records in
                completion?(insert(records))
            }
        }
    }

    /// 写库：同一个 workout UUID 只写一次；不碰手动记的条目。
    private static func insert(_ records: [WorkoutRecord]) -> Summary {
        var summary = Summary()
        guard !records.isEmpty else { return summary }

        let context = Persistence.shared.container.viewContext
        let request = ActivityEntry.fetchRequest()
        request.predicate = NSPredicate(format: "externalID IN %@", records.map(\.externalID))
        request.fetchLimit = records.count
        let existing = Set(((try? context.fetch(request)) ?? []).compactMap(\.externalID))

        for record in records {
            guard !existing.contains(record.externalID) else {
                summary.skipped += 1
                continue
            }
            let entry = ActivityEntry(context: context)
            entry.id = UUID()
            entry.date = record.start
            entry.kind = record.kind.rawValue
            entry.title = record.title
            entry.durationMinutes = max(record.end.timeIntervalSince(record.start) / 60, 0)
            entry.distanceKilometers = record.distanceKilometers
            entry.elevationGainMeters = 0
            entry.kcal = record.kcal
            entry.note = "来自「健康」"
            entry.createdAt = Date()
            entry.source = source
            entry.externalID = record.externalID
            summary.inserted += 1
        }

        if summary.inserted > 0 { Persistence.shared.save() }
        return summary
    }
}
