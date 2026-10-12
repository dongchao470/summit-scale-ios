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
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
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
            store.stopQuery(query)
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
}

extension Notification.Name {
    static let healthWeightChanged = Notification.Name("healthWeightChanged")
}
