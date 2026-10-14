import Foundation
import HealthKit

/// Widget 扩展侧的「健康」读取器。
///
/// 为什么要它：主 App 写的共享快照只在「用户打开 App」或「后台 BGAppRefresh 被系统叫醒」时更新，
/// 而 iOS 对后台任务的调度完全不保证（几十分钟到十几小时都可能）。于是桌面组件经常挂着旧数字，
/// 必须开 App 才动——用户反馈的正是这个。
///
/// 这里让扩展在 `getTimeline` 时自己直接读 HealthKit 的今日数据，绕开后台唤醒的不确定性。
///
/// 兼容性兜底：TrollStore / 未签名环境下，扩展的 healthkit entitlement 可能不被系统信任，
/// 届时 `authorizationStatus` 或查询会失败——**任何一步失败都返回 nil**，调用方回退到共享快照，
/// 保证不会比原来更差（至少还能显示 App 上次写入的数据，并带更新时间）。
enum WidgetHealthReader {

    /// 今日健康活动：步数、活跃消耗、锻炼分钟、步行距离。
    struct TodayActivity {
        let steps: Int
        let activeKcal: Double
        let exerciseMinutes: Int
        let distanceKm: Double

        static let empty = TodayActivity(steps: 0, activeKcal: 0, exerciseMinutes: 0, distanceKm: 0)
    }

    private static let store = HKHealthStore()

    /// 查询今日（00:00 起）健康活动。失败 / 未授权 / 无数据都返回 nil。
    static func fetchTodayActivity() async -> TodayActivity? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }

        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        let types: [HKQuantityType] = [stepType, energyType, exerciseType, distanceType].compactMap { $0 }
        guard types.count == 4 else { return nil }

        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: Date()),
            end: Date(),
            options: .strictStartDate
        )

        async let steps = sum(stepType!, predicate: predicate, unit: .count())
        async let energy = sum(energyType!, predicate: predicate, unit: .kilocalorie())
        async let exercise = sum(exerciseType!, predicate: predicate, unit: .minute())
        async let distance = sum(distanceType!, predicate: predicate, unit: .meterUnit(with: .kilo))

        let (s, e, x, d) = await (steps, energy, exercise, distance)
        // 四项全查不到，说明八成是没权限（未签名环境下常见）——返回 nil 让调用方回退。
        guard s != nil || e != nil || x != nil || d != nil else { return nil }

        return TodayActivity(
            steps: Int((s ?? 0).rounded()),
            activeKcal: (e ?? 0).rounded(),
            exerciseMinutes: Int((x ?? 0).rounded()),
            distanceKm: d ?? 0
        )
    }

    private static func sum(
        _ type: HKQuantityType,
        predicate: NSPredicate,
        unit: HKUnit
    ) async -> Double? {
        await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                guard error == nil,
                      let quantity = result?.sumQuantity() else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }
}
