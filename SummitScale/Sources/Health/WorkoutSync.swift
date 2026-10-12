import CoreData
import Foundation

/// 把「健康」里的数据搬进本地运动表。
///
/// 分两路：
/// 1. **锻炼样本（HKWorkout）**：Apple Watch 或运动 App 真正记下来的锻炼，按 UUID 去重。
/// 2. **每日汇总**：iPhone 自己只会记步数、步行距离和活跃消耗，**不产生锻炼样本**，
///    所以没有锻炼样本的日子用「步数 + 活跃消耗 + 步行距离」汇总成一条「日常活动」，
///    让「今天动了多少」至少能落库。同一天的汇总会刷新（当天数字一直在涨）。
///
/// 只读「健康」，不写回、不删健康里的任何数据。App 里删掉某条导入记录后，
/// 下次同步它会因为仍在健康里而重新出现——这是刻意的，避免误删后数据永久缺失。
@MainActor
enum WorkoutSync {
    /// 写进 `ActivityEntry.source` 的标记，用来跟手动记录区分。
    static let source = "healthkit"
    /// 每日汇总记录的来源标记。
    static let dailySource = "healthkit-daily"

    /// 少于这个步数（且消耗也不高）的一天不算「动过」，不产生记录。
    private static let quietDaySteps = 500.0
    private static let quietDayKcal = 50.0

    struct Summary {
        /// 健康里读到的锻炼样本条数（诊断用：为 0 说明这台设备没有锻炼样本）。
        var workoutCount = 0
        /// 新导入的锻炼条数。
        var inserted = 0
        /// 已存在、跳过的锻炼条数。
        var skipped = 0
        /// 新汇总的「日常活动」天数。
        var dailyInserted = 0
        /// 刷新过数字的「日常活动」天数。
        var dailyUpdated = 0
        var unavailable = false

        var message: String {
            if unavailable {
                return "没拿到「健康」的读取权限，或这台设备的健康数据不可用。"
            }
            var parts = ["健康里读到 \(workoutCount) 条锻炼样本"]
            if inserted > 0 { parts.append("新导入 \(inserted) 条") }
            if skipped > 0 { parts.append("已有 \(skipped) 条") }
            let dailyTouched = dailyInserted + dailyUpdated
            if dailyTouched > 0 {
                parts.append("按步数与活跃消耗汇总 \(dailyTouched) 天日常活动")
            }
            if inserted == 0 && dailyTouched == 0 {
                parts.append("没有可落库的新数据")
            }
            return parts.joined(separator: "，") + "。"
        }
    }

    /// 拉近 `days` 天的锻炼与每日汇总并落库。
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

            var workouts: [HealthKitManager.WorkoutRecord]?
            var steps: [(day: Date, steps: Double)]?
            var energy: [(day: Date, kcal: Double)]?
            var distance: [(day: Date, kilometers: Double)]?

            // 四路查询都在主线程回调，齐了再一起写库，避免一小时内写四次。
            @MainActor func finishIfReady() {
                guard let w = workouts, let s = steps, let e = energy, let d = distance else { return }
                var summary = insert(w)
                summary.workoutCount = w.count
                upsertDaily(steps: s, energy: e, distance: d, workoutDays: workoutDays(in: w), into: &summary)
                completion?(summary)
            }

            health.recentWorkouts(days: days) { records in
                workouts = records
                finishIfReady()
            }
            health.dailySteps(days: days) { points in
                steps = points
                finishIfReady()
            }
            health.dailyActiveEnergy(days: days) { points in
                energy = points
                finishIfReady()
            }
            health.dailyWalkingDistance(days: days) { points in
                distance = points
                finishIfReady()
            }
        }
    }

    // MARK: - 锻炼样本

    /// 写库：同一个 workout UUID 只写一次；不碰手动记的条目。
    private static func insert(_ records: [HealthKitManager.WorkoutRecord]) -> Summary {
        var summary = Summary()
        guard !records.isEmpty else { return summary }

        let context = Persistence.shared.container.viewContext
        let request = ActivityEntry.fetchRequest()
        request.predicate = NSPredicate(format: "externalID IN %@", records.map { $0.externalID })
        request.fetchLimit = records.count
        let existing = Set(((try? context.fetch(request)) ?? []).compactMap { $0.externalID })

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

    private static func workoutDays(in records: [HealthKitManager.WorkoutRecord]) -> Set<Date> {
        let calendar = Calendar.current
        return Set(records.map { calendar.startOfDay(for: $0.start) })
    }

    // MARK: - 每日汇总

    /// 没有锻炼样本的日子，用当天的步数、活跃消耗、步行距离汇总成一条「日常活动」。
    /// 同一天第二次同步会刷新数字而不是再插一条。
    private static func upsertDaily(
        steps: [(day: Date, steps: Double)],
        energy: [(day: Date, kcal: Double)],
        distance: [(day: Date, kilometers: Double)],
        workoutDays: Set<Date>,
        into summary: inout Summary
    ) {
        let calendar = Calendar.current
        func byDay<T>(_ points: [(day: Date, value: T)]) -> [Date: T] {
            Dictionary(points.map { (calendar.startOfDay(for: $0.day), $0.value) }, uniquingKeysWith: { first, _ in first })
        }
        let stepMap = byDay(steps.map { (day: $0.day, value: $0.steps) })
        let energyMap = byDay(energy.map { (day: $0.day, value: $0.kcal) })
        let distanceMap = byDay(distance.map { (day: $0.day, value: $0.kilometers) })

        // 有锻炼样本的那天已经有记录了，不再叠加汇总，免得一天算两遍。
        let days = Set(stepMap.keys)
            .union(energyMap.keys)
            .union(distanceMap.keys)
            .subtracting(workoutDays)
        guard !days.isEmpty else { return }

        let context = Persistence.shared.container.viewContext
        let ids = days.map { dailyID(for: $0) }
        let request = ActivityEntry.fetchRequest()
        request.predicate = NSPredicate(format: "externalID IN %@", ids)
        request.fetchLimit = ids.count
        var existing: [String: ActivityEntry] = [:]
        for entry in (try? context.fetch(request)) ?? [] {
            if let id = entry.externalID { existing[id] = entry }
        }

        for day in days.sorted() {
            let stepCount = stepMap[day] ?? 0
            let kcal = energyMap[day] ?? 0
            let kilometers = distanceMap[day] ?? 0
            guard stepCount >= quietDaySteps || kcal >= quietDayKcal else { continue }

            // 步数除 110 约等于走路分钟数；没有步数就用距离按 4.8 km/h 反推。
            let minutes = stepCount > 0 ? stepCount / 110.0 : kilometers / 4.8 * 60
            let id = dailyID(for: day)

            if let entry = existing[id] {
                let changed = abs(entry.kcal - kcal) > 0.5
                    || abs(entry.distanceKilometers - kilometers) > 0.05
                    || abs(entry.durationMinutes - minutes) > 1
                guard changed else { continue }
                entry.kcal = kcal
                entry.distanceKilometers = kilometers
                entry.durationMinutes = minutes
                entry.createdAt = Date()
                summary.dailyUpdated += 1
            } else {
                let entry = ActivityEntry(context: context)
                entry.id = UUID()
                entry.date = day
                entry.kind = ActivityKind.walking.rawValue
                entry.title = "日常活动"
                entry.durationMinutes = minutes
                entry.distanceKilometers = kilometers
                entry.elevationGainMeters = 0
                entry.kcal = kcal
                entry.note = "来自「健康」· 当日步数与活跃消耗汇总（这天没有锻炼样本）"
                entry.createdAt = Date()
                entry.source = dailySource
                entry.externalID = id
                summary.dailyInserted += 1
            }
        }

        if summary.dailyInserted + summary.dailyUpdated > 0 { Persistence.shared.save() }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func dailyID(for day: Date) -> String {
        "daily-" + dayFormatter.string(from: day)
    }
}
