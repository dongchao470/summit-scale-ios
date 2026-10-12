import Foundation
import HealthKit
import SwiftUI

/// HealthKit 接入管理：权限、体重双向、步数/锻炼消耗、睡眠。
///
/// TrollStore 未签名环境下 HealthKit 可能不可用（entitlement 校验失败），
/// 所有失败都收敛到 statusText，不崩、不弹错误窗，开关自动回退关闭。
@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let enabled = "healthEnabled"
        static let weightSync = "healthWeightSync"
        static let activitySync = "healthActivitySync"
        static let sleepSync = "healthSleepSync"
    }

    // MARK: - 发布状态

    @Published var authorized = false
    @Published var errorMessage: String?

    var enabled: Bool {
        get { defaults.bool(forKey: Keys.enabled) && authorized }
        set { defaults.set(newValue, forKey: Keys.enabled) }
    }

    var weightSync: Bool {
        get { defaults.bool(forKey: Keys.weightSync) }
        set {
            defaults.set(newValue, forKey: Keys.weightSync)
            if newValue { observeWeight() } else { stopWeightObserver() }
        }
    }

    var activitySync: Bool {
        get { defaults.bool(forKey: Keys.activitySync) }
        set { defaults.set(newValue, forKey: Keys.activitySync) }
    }

    var sleepSync: Bool {
        get { defaults.bool(forKey: Keys.sleepSync) }
        set { defaults.set(newValue, forKey: Keys.sleepSync) }
    }

    var statusText: String {
        if !HKHealthStore.isHealthDataAvailable() {
            return "此设备上健康数据不可用"
        }
        if let error = errorMessage {
            return error
        }
        if authorized && enabled {
            return "已连接，数据实时同步"
        }
        if authorized {
            return "已授权，未启用"
        }
        return "开启后跳转授权页"
    }

    private init() {
        if HKHealthStore.isHealthDataAvailable() {
            // 启动时静默核对授权状态；首次开启时才弹系统授权页。
            checkAuthorization()
        }
    }

    // MARK: - 权限

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.workoutType(),
        ]
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        [HKObjectType.quantityType(forIdentifier: .bodyMass)!]
    }

    func requestAccess() {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "此设备上健康数据不可用"
            return
        }
        store.requestAuthorization(toShare: writeTypes, read: readTypes) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    self.authorized = true
                    self.errorMessage = nil
                    self.defaults.set(true, forKey: Keys.enabled)
                    if self.weightSync { self.observeWeight() }
                } else {
                    self.errorMessage = "授权被拒绝或失败：\(error?.localizedDescription ?? "未知原因")"
                }
            }
        }
    }

    /// 用户自己开过健康同步没有——不看当前授权状态。
    /// 新增权限类型（比如锻炼记录）还没决定过时，授权状态会回到「未授权」，
    /// 这时候仍然需要按用户的意愿去补权限、补数据。
    var enabledByUser: Bool { defaults.bool(forKey: Keys.enabled) }

    /// 补问新增的权限类型；已经决定过的类型系统不会重复弹窗。
    /// 返回是否走完授权流程（HealthKit 不告诉 App 用户是否拒绝读权限，只能靠查询结果判断）。
    func ensureAccess() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            authorized = true
            errorMessage = nil
            return true
        } catch {
            NSLog("[SummitScale] 补充健康授权失败: \(error)")
            return false
        }
    }

    private func checkAuthorization() {
        // 确定授权状态只能通过请求一次得知；静默请求不弹窗（已授权过的话）。
        store.getRequestStatusForAuthorization(toShare: writeTypes, read: readTypes) { [weak self] status, _ in
            Task { @MainActor in
                self?.authorized = (status == .unnecessary)
            }
        }
    }

    func disable() {
        defaults.set(false, forKey: Keys.enabled)
        stopWeightObserver()
    }

    /// HKObserverQuery 没有 invalidate，停掉要用 store.stopQuery。
    private func stopWeightObserver() {
        if let query = weightObserver {
            store.stop(query)
            weightObserver = nil
        }
    }

    // MARK: - 体重：读（健康 → App）

    /// 取最新体重（kg），失败返回 nil。
    func latestWeightKilograms(completion: @escaping (Double?) -> Void) {
        guard authorized, enabled,
              let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            completion(nil)
            return
        }
        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
            let kg = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .gramUnit(with: .kilo))
            Task { @MainActor in completion(kg) }
        }
        store.execute(query)
    }

    // MARK: - 体重：写（App → 健康）+ 监听外部变更

    private var weightObserver: HKObserverQuery?

    /// App 记体重时同步写入健康 App。
    func saveWeight(kilograms: Double, date: Date) {
        guard authorized, enabled, weightSync,
              let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms), start: date, end: date)
        store.save(sample) { [weak self] _, error in
            if let error {
                Task { @MainActor in self?.errorMessage = "写入体重失败：\(error.localizedDescription)" }
            }
        }
    }

    /// 监听健康 App 里的体重变化，变化时读最新值回写 App。
    private func observeWeight() {
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return }
        stopWeightObserver()
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, handler, _ in
            self?.latestWeightKilograms { kg in
                if let kg {
                    NotificationCenter.default.post(name: .healthWeightChanged, object: nil, userInfo: ["kilograms": kg])
                }
            }
            handler()
        }
        store.execute(query)
        weightObserver = query
    }

    // MARK: - 活动：今日步数 + 锻炼消耗（kcal）

    func todayActivityKcal(completion: @escaping (Double) -> Void) {
        guard authorized, enabled, activitySync else {
            completion(0)
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        var total = 0.0
        let group = DispatchGroup()

        // 活动能量
        if let burned = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            group.enter()
            let q = HKStatisticsQuery(quantityType: burned, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stat, _ in
                total += stat?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                group.leave()
            }
            store.execute(q)
        }

        // 步数折算：平均步幅 0.7m、每步约消耗 0.04 kcal（粗估，仅参考）。
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            group.enter()
            let q = HKStatisticsQuery(quantityType: steps, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stat, _ in
                let count = stat?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                total += count * 0.04
                group.leave()
            }
            store.execute(q)
        }

        group.notify(queue: .main) { completion(total) }
    }

    // MARK: - 活动明细：今日步数 / 锻炼消耗 / 锻炼时长

    /// 今日活动明细，供首页「今日活动」卡逐项展示。
    struct TodayActivity {
        var steps: Double = 0
        var activeKcal: Double = 0
        var exerciseMinutes: Double = 0
        var hasData: Bool { steps > 0 || activeKcal > 0 || exerciseMinutes > 0 }
    }

    /// 读今天的步数、锻炼活动消耗（kcal）与锻炼时长（分钟），分开返回。
    func todayActivityDetail(completion: @escaping (TodayActivity) -> Void) {
        guard authorized, enabled, activitySync else {
            Task { @MainActor in completion(TodayActivity()) }
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        var result = TodayActivity()
        let group = DispatchGroup()

        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            group.enter()
            let q = HKStatisticsQuery(quantityType: steps, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stat, _ in
                result.steps = stat?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                group.leave()
            }
            store.execute(q)
        }
        if let burned = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            group.enter()
            let q = HKStatisticsQuery(quantityType: burned, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stat, _ in
                result.activeKcal = stat?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                group.leave()
            }
            store.execute(q)
        }
        if let exercise = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) {
            group.enter()
            let q = HKStatisticsQuery(quantityType: exercise, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stat, _ in
                result.exerciseMinutes = stat?.sumQuantity()?.doubleValue(for: .minute()) ?? 0
                group.leave()
            }
            store.execute(q)
        }

        group.notify(queue: .main) { completion(result) }
    }

    /// 近 days 天每天的步数（含今天），按日升序；无数据的日子补 0。供趋势页步数柱。
    func dailySteps(days: Int, completion: @escaping ([(day: Date, steps: Double)]) -> Void) {
        guard authorized, enabled, activitySync,
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            Task { @MainActor in completion([]) }
            return
        }
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: Date())
        let startDay = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: anchor) ?? anchor
        let predicate = HKQuery.predicateForSamples(withStart: startDay, end: Date(), options: .strictStartDate)
        var interval = DateComponents()
        interval.day = 1

        let query = HKStatisticsCollectionQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: interval
        )
        query.initialResultsHandler = { _, collection, _ in
            var out: [(day: Date, steps: Double)] = []
            collection?.enumerateStatistics(from: startDay, to: Date()) { stat, _ in
                let day = calendar.startOfDay(for: stat.startDate)
                let steps = stat.sumQuantity()?.doubleValue(for: .count()) ?? 0
                out.append((day: day, steps: steps))
            }
            Task { @MainActor in completion(out) }
        }
        store.execute(query)
    }

    // MARK: - 每日步行+跑步距离（无锻炼样本时做每日汇总用）

    /// 近 days 天每天的步行+跑步距离（公里），按日升序；没权限时返回空数组。
    func dailyWalkingDistance(days: Int, completion: @escaping ([(day: Date, kilometers: Double)]) -> Void) {
        guard authorized, enabled, activitySync,
              let type = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else {
            Task { @MainActor in completion([]) }
            return
        }
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: Date())
        let startDay = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: anchor) ?? anchor
        let predicate = HKQuery.predicateForSamples(withStart: startDay, end: Date(), options: .strictStartDate)
        var interval = DateComponents()
        interval.day = 1

        let query = HKStatisticsCollectionQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: interval
        )
        query.initialResultsHandler = { _, collection, _ in
            var out: [(day: Date, kilometers: Double)] = []
            collection?.enumerateStatistics(from: startDay, to: Date()) { stat, _ in
                let day = calendar.startOfDay(for: stat.startDate)
                let meters = stat.sumQuantity()?.doubleValue(for: .meter()) ?? 0
                out.append((day: day, kilometers: meters / 1000))
            }
            Task { @MainActor in completion(out) }
        }
        store.execute(query)
    }

    // MARK: - 睡眠：昨晚时长（小时）

    func lastNightSleepHours(completion: @escaping (Double?) -> Void) {
        guard authorized, enabled, sleepSync,
              let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(nil)
            return
        }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            // 只统计睡眠中（非 InBed）样本，重叠区间合并后求总时长。
            let asleep = (samples as? [HKCategorySample])?.filter {
                $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                    || $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                    || $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
            } ?? []
            var seconds = 0.0
            var intervals: [(Date, Date)] = asleep.map { ($0.startDate, $0.endDate) }
            intervals.sort { $0.0 < $1.0 }
            var currentStart: Date?
            var currentEnd: Date?
            for (s, e) in intervals {
                if let ce = currentEnd, s <= ce {
                    // 与当前区间重叠或相接，扩展右端。
                    if e > ce { currentEnd = e }
                } else {
                    // 收上一个区间。
                    if let cs = currentStart, let ce = currentEnd {
                        seconds += ce.timeIntervalSince(cs)
                    }
                    currentStart = s
                    currentEnd = e
                }
            }
            if let cs = currentStart, let ce = currentEnd {
                seconds += ce.timeIntervalSince(cs)
            }
            Task { @MainActor in completion(seconds / 3600) }
        }
        store.execute(query)
    }

    // MARK: - 睡眠：近 days 天分期（深睡 / 浅睡 / REM，单位小时）

    /// 一晚的睡眠分期时长（小时），按「醒来那天」归属。
    struct SleepStageDay {
        let day: Date
        var deep: Double = 0
        var core: Double = 0
        var rem: Double = 0
        var total: Double { deep + core + rem }
        var hasData: Bool { total > 0 }
    }

    /// 近 days 天每晚睡眠分期（小时），按日升序补齐，无数据的日子各项为 0。
    /// 样本按「结束时刻所在日」归属（当天早上醒来算当天）。
    func dailySleepStages(days: Int, completion: @escaping ([SleepStageDay]) -> Void) {
        guard authorized, enabled, sleepSync,
              let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            Task { @MainActor in completion([]) }
            return
        }
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: Date())
        // 往前多取一天，覆盖跨午夜入睡的样本。
        let start = calendar.date(byAdding: .day, value: -(max(days, 1)), to: anchor) ?? anchor
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            var byDay: [Date: SleepStageDay] = [:]
            for sample in (samples as? [HKCategorySample]) ?? [] {
                let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600
                guard hours > 0 else { continue }
                let day = calendar.startOfDay(for: sample.endDate)
                var rec = byDay[day] ?? SleepStageDay(day: day)
                switch sample.value {
                case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                    rec.deep += hours
                case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                    rec.rem += hours
                case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                     HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                    // 核心睡眠 +（旧设备无分期的）通用睡眠，都并入「浅睡」。
                    rec.core += hours
                default:
                    break // inBed / awake 不计入睡眠时长
                }
                byDay[day] = rec
            }
            var result: [SleepStageDay] = []
            var cursor = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: anchor) ?? anchor
            while cursor <= anchor {
                result.append(byDay[cursor] ?? SleepStageDay(day: cursor))
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            Task { @MainActor in completion(result) }
        }
        store.execute(query)
    }

    // MARK: - 心率：近夜间平均 / 最低（bpm）

    /// 过去约 16 小时内的平均与最低心率（bpm），近似「昨晚睡眠心率」。读不到为 nil。
    func lastNightHeartRate(completion: @escaping (_ average: Double?, _ lowest: Double?) -> Void) {
        guard authorized, enabled, sleepSync,
              let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            Task { @MainActor in completion(nil, nil) }
            return
        }
        let start = Calendar.current.date(byAdding: .hour, value: -16, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let query = HKStatisticsQuery(quantityType: hrType, quantitySamplePredicate: predicate,
                                      options: [.discreteAverage, .discreteMin]) { _, stat, _ in
            let avg = stat?.averageQuantity()?.doubleValue(for: unit)
            let low = stat?.minimumQuantity()?.doubleValue(for: unit)
            Task { @MainActor in completion(avg, low) }
        }
        store.execute(query)
    }

    // MARK: - 锻炼记录（供自动落库）

    /// 一条「健康」里的锻炼，字段对齐本地活动表。
    struct WorkoutRecord {
        let externalID: String
        let start: Date
        let end: Date
        let kcal: Double
        let distanceKilometers: Double
        let kind: ActivityKind
        let title: String
    }

    /// 近 days 天的锻炼记录（HKWorkout），按开始时间升序；没权限或没数据时返回空数组。
    func recentWorkouts(days: Int, completion: @escaping ([WorkoutRecord]) -> Void) {
        guard authorized, enabled, activitySync else {
            Task { @MainActor in completion([]) }
            return
        }
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -max(days, 1), to: anchor) ?? anchor
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let query = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: sort) { _, samples, error in
            if let error {
                NSLog("[SummitScale] 读锻炼记录失败: \(error)")
            }
            let records = ((samples as? [HKWorkout]) ?? []).map { workout -> WorkoutRecord in
                let described = HealthKitManager.describe(workout.workoutActivityType)
                return WorkoutRecord(
                    externalID: workout.uuid.uuidString,
                    start: workout.startDate,
                    end: workout.endDate,
                    kcal: HealthKitManager.kilocalories(of: workout),
                    distanceKilometers: (workout.totalDistance?.doubleValue(for: .meter()) ?? 0) / 1000,
                    kind: described.kind,
                    title: described.title
                )
            }
            Task { @MainActor in completion(records) }
        }
        store.execute(query)
    }

    /// 单次锻炼的活跃消耗；totalEnergyBurned 已被废弃，优先读统计值。
    nonisolated private static func kilocalories(of workout: HKWorkout) -> Double {
        if let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
           let sum = workout.statistics(for: type)?.sumQuantity() {
            return sum.doubleValue(for: .kilocalorie())
        }
        return workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
    }

    /// 系统的运动类型 → App 的运动种类 + 中文名。
    nonisolated private static func describe(_ type: HKWorkoutActivityType) -> (kind: ActivityKind, title: String) {
        switch type {
        case .running:
            return (.running, "跑步")
        case .walking:
            return (.walking, "走路")
        case .cycling:
            return (.cycling, "骑行")
        case .swimming:
            return (.swimming, "游泳")
        case .hiking:
            return (.hiking, "爬山")
        case .traditionalStrengthTraining, .functionalStrengthTraining,
             .coreTraining, .crossTraining, .highIntensityIntervalTraining:
            return (.strength, "力量训练")
        case .yoga, .pilates, .flexibility:
            return (.yoga, "瑜伽")
        case .elliptical, .rowing, .stairClimbing, .jumpRope:
            return (.other, "有氧训练")
        default:
            return (.other, "锻炼")
        }
    }

    // MARK: - 每日活跃消耗（供运动趋势柱）

    /// 近 days 天每天的活跃消耗（kcal，含日常活动和锻炼），按日升序；没权限时返回空数组。
    func dailyActiveEnergy(days: Int, completion: @escaping ([(day: Date, kcal: Double)]) -> Void) {
        guard authorized, enabled, activitySync,
              let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            Task { @MainActor in completion([]) }
            return
        }
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: Date())
        let startDay = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: anchor) ?? anchor
        let predicate = HKQuery.predicateForSamples(withStart: startDay, end: Date(), options: .strictStartDate)
        var interval = DateComponents()
        interval.day = 1

        let query = HKStatisticsCollectionQuery(quantityType: type,
                                                quantitySamplePredicate: predicate,
                                                options: .cumulativeSum,
                                                anchorDate: anchor,
                                                intervalComponents: interval)
        query.initialResultsHandler = { _, collection, error in
            if let error {
                NSLog("[SummitScale] 读活跃消耗失败: \(error)")
            }
            var points: [(day: Date, kcal: Double)] = []
            collection?.enumerateStatistics(from: startDay, to: Date()) { stat, _ in
                points.append((day: calendar.startOfDay(for: stat.startDate),
                               kcal: stat.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0))
            }
            Task { @MainActor in completion(points) }
        }
        store.execute(query)
    }
}

extension Notification.Name {
    static let healthWeightChanged = Notification.Name("healthWeightChanged")
}
