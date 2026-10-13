import Foundation
import HealthKit

/// widget 自己直接问 HealthKit 要「今天」的数。
///
/// 为什么需要它：widget 的时间线刷新是**系统拉起扩展进程**做的，跟主 App 死没死无关；
/// 但快照得靠主 App 写，App 被划掉后就没人写，桌面就冻在最后一次的数字上。
/// 扩展带上 `com.apple.developer.healthkit` 权限、且用户已经在主 App 里授权过，
/// 就能自己取数（扩展自己不能弹授权框，这是 Apple 的限制，不是我们偷懒）。
/// 取不到——没授权、查询失败、超时——一律退回读共享快照，行为和以前完全一样，不会更差。
enum WidgetHealthReader {
    private static let store = HKHealthStore()

    struct TodayHealth {
        var steps: Double
        var activeKcal: Double
    }

    /// 查一次今天的步数与活跃消耗；4 秒拿不到就放弃。
    /// widget 的时间线刷新有硬性时限，宁可退回旧快照也不能把刷新卡死。
    static func todayWithTimeout() async -> TodayHealth? {
        await withTaskGroup(of: TodayHealth?.self) { group in
            group.addTask { await today() }
            group.addTask {
                try? await Task.sleep(nanoseconds: 4 * 1_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func today() async -> TodayHealth? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = Date()

        guard
            let steps = await sum(.stepCount, .count(), from: start, to: end),
            let kcal = await sum(.activeEnergyBurned, .kilocalorie(), from: start, to: end)
        else { return nil }

        return TodayHealth(steps: steps, activeKcal: kcal)
    }

    /// 累计求和。注意：没有读取权限时 HealthKit **不会报错**，只是给不出 sumQuantity，
    /// 这里一律当「拿不到」处理，交给调用方退回快照——别拿 0 去覆盖真实步数。
    private static func sum(
        _ identifier: HKQuantityTypeIdentifier,
        _ unit: HKUnit,
        from start: Date,
        to end: Date
    ) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }
}
