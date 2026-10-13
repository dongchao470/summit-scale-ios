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
        /// 补上心率的锻炼条数 / 日常活动天数（诊断用：为 0 说明这台设备/这段时间没有心率采样）。
        var heartRateWorkouts = 0
        var heartRateDays = 0

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
            if heartRateWorkouts > 0 || heartRateDays > 0 {
                parts.append("带心率的：\(heartRateWorkouts) 条锻炼、\(heartRateDays) 天日常")
            }
            if inserted == 0 && dailyTouched == 0 && heartRateWorkouts == 0 && heartRateDays == 0 {
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
            var heartRates: [(day: Date, average: Double, maximum: Double)]?

            // 五路查询都在主线程回调，齐了再一起写库，避免一小时内写五次。
            @MainActor func finishIfReady() {
                guard let w = workouts, let s = steps, let e = energy, let d = distance else { return }
                var summary = insert(w)
                summary.workoutCount = w.count
                upsertDaily(steps: s, energy: e, distance: d, workouts: w, into: &summary)
                applyHeartRate(daily: heartRates ?? []) { workouts, days in
                    summary.heartRateWorkouts = workouts
                    summary.heartRateDays = days
                    completion?(summary)
                }
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
            health.dailyHeartRate(days: days) { points in
                heartRates = points
                finishIfReady()
            }
        }
    }

    // MARK: - 心率补齐

    /// 把心率补到已落库的记录上：日常活动按整天的心率取，锻炼按样本时段取；拿不到就留 0。
    /// 顺序查询、不并发，避免一次开几十个 HealthKit 查询；只有补上了才回存。
    @MainActor
    static func applyHeartRate(daily: [(day: Date, average: Double, maximum: Double)],
                               completion: @escaping (_ workouts: Int, _ days: Int) -> Void) {
        let context = Persistence.shared.container.viewContext
        let calendar = Calendar.current
        let since = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let request = ActivityEntry.fetchRequest()
        request.predicate = NSPredicate(format: "(source == %@ OR source == %@) AND date >= %@",
                                        source, dailySource, since as NSDate)
        request.sortDescriptors = ActivityEntry.dateDescending
        request.fetchLimit = 400
        let entries = (try? context.fetch(request)) ?? []

        var dayMap: [Date: (average: Double, maximum: Double)] = [:]
        for point in daily where point.average > 0 {
            dayMap[calendar.startOfDay(for: point.day)] = (point.average, point.maximum)
        }

        var filledDays = 0
        for entry in entries where entry.source == dailySource {
            guard let stats = dayMap[calendar.startOfDay(for: entry.date)], stats.average > 0 else { continue }
            entry.averageHeartRate = stats.average
            entry.maximumHeartRate = stats.maximum
            filledDays += 1
        }

        let workoutEntries = Array(entries.filter { $0.source == source }.prefix(60))

        @MainActor func fillWorkout(at index: Int, hits: Int, days: Int) {
            guard index < workoutEntries.count else {
                if hits > 0 || days > 0 { Persistence.shared.save() }
                completion(hits, days)
                return
            }
            let entry = workoutEntries[index]
            let start = entry.date
            let end = start.addingTimeInterval(max(entry.durationMinutes * 60, 600))
            HealthKitManager.shared.heartRateStats(from: start, to: end) { average, maximum in
                Task { @MainActor in
                    var next = hits
                    if average > 0 {
                        entry.averageHeartRate = average
                        entry.maximumHeartRate = maximum
                        next += 1
                    }
                    fillWorkout(at: index + 1, hits: next, days: days)
                }
            }
        }

        fillWorkout(at: 0, hits: 0, days: filledDays)
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

    // MARK: - 每日汇总

    /// 没有锻炼样本的日子，用当天的步数、活跃消耗、步行距离汇总成一条「日常活动」。
    /// 同一天第二次同步会刷新数字而不是再插一条。
    private static func upsertDaily(
        steps: [(day: Date, steps: Double)],
        energy: [(day: Date, kcal: Double)],
        distance: [(day: Date, kilometers: Double)],
        workouts: [HealthKitManager.WorkoutRecord],
        into summary: inout Summary
    ) {
        let calendar = Calendar.current
        func byDay<T>(_ points: [(day: Date, value: T)]) -> [Date: T] {
            Dictionary(points.map { (calendar.startOfDay(for: $0.day), $0.value) }, uniquingKeysWith: { first, _ in first })
        }
        let stepMap = byDay(steps.map { (day: $0.day, value: $0.steps) })
        let energyMap = byDay(energy.map { (day: $0.day, value: $0.kcal) })
        let distanceMap = byDay(distance.map { (day: $0.day, value: $0.kilometers) })

        // 当天锻炼已经计过的消耗 / 距离 / 时长。日常活动汇总要把这块扣掉，
        // 否则和锻炼条目加在一起就成了一天算两遍。
        var workoutByDay: [Date: (kcal: Double, kilometers: Double, minutes: Double)] = [:]
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.start)
            var acc = workoutByDay[day] ?? (0, 0, 0)
            acc.kcal += workout.kcal
            acc.kilometers += workout.distanceKilometers
            acc.minutes += max(workout.end.timeIntervalSince(workout.start) / 60, 0)
            workoutByDay[day] = acc
        }

        // 有锻炼的日子同样要汇总：这天走了多少步、日常走动了多少，也是当天的一部分。
        let days = Set(stepMap.keys)
            .union(energyMap.keys)
            .union(distanceMap.keys)
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
            let workout = workoutByDay[day] ?? (0, 0, 0)
            // 扣掉当天锻炼已经计过的消耗和距离，剩下的才算「日常活动」。
            let kcal = max((energyMap[day] ?? 0) - workout.kcal, 0)
            let kilometers = max((distanceMap[day] ?? 0) - workout.kilometers, 0)
            guard stepCount >= quietDaySteps || kcal >= quietDayKcal else { continue }

            // 步数除 110 约等于走路分钟数；没有步数就用距离按 4.8 km/h 反推，再扣掉锻炼时长。
            let walked = stepCount > 0 ? stepCount / 110.0 : kilometers / 4.8 * 60
            let minutes = max(walked - workout.minutes, 0)
            // 扣完什么都不剩（比如整天都在锻炼）就不插这条，免得堆一行全 0。
            guard minutes > 0 || kilometers > 0.05 || kcal > 1 else { continue }
            let note = workout.kcal > 0 || workout.kilometers > 0
                ? "来自「健康」· 当日步数与活跃消耗汇总（已扣除当天锻炼）"
                : "来自「健康」· 当日步数与活跃消耗汇总（这天没有锻炼样本）"
            let id = dailyID(for: day)

            if let entry = existing[id] {
                let changed = abs(entry.kcal - kcal) > 0.5
                    || abs(entry.distanceKilometers - kilometers) > 0.05
                    || abs(entry.durationMinutes - minutes) > 1
                    || entry.note != note
                guard changed else { continue }
                entry.kcal = kcal
                entry.distanceKilometers = kilometers
                entry.durationMinutes = minutes
                entry.note = note
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
                entry.note = note
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

    /// 自检用：本地已落库的、来自「健康」的记录条数（锻炼 / 每日汇总分开数）。
    static func storedCounts() -> (workouts: Int, daily: Int) {
        let context = Persistence.shared.container.viewContext
        let request = ActivityEntry.fetchRequest()
        request.predicate = NSPredicate(format: "source == %@ OR source == %@", source, dailySource)
        let entries = (try? context.fetch(request)) ?? []
        let daily = entries.filter { $0.source == dailySource }.count
        return (workouts: entries.count - daily, daily: daily)
    }

    private static func dailyID(for day: Date) -> String {
        "daily-" + dayFormatter.string(from: day)
    }
}
