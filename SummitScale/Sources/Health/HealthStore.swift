import CoreData
import Foundation
import HealthKit

/// 从「健康」里读数据的入口。
///
/// 现实约束：TrollStore 装的无签名包大概率拿不到 HealthKit entitlement，
/// 那种情况下授权会失败，这里全部优雅降级，界面只会看到一句提示，不会崩。
@MainActor
final class HealthStore {
    static let shared = HealthStore()

    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        let identifiers: [HKQuantityTypeIdentifier] = [
            .bodyMass,
            .bodyFatPercentage,
            .activeEnergyBurned,
            .stepCount,
        ]
        for identifier in identifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func authorizationStatus() -> HKAuthorizationStatus {
        guard let weight = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            return .notDetermined
        }
        return store.authorizationStatus(for: weight)
    }

    /// 申请读取权限；拿到（或已经授权过）返回 true。
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            NSLog("[SummitScale] HealthKit 授权失败: \(error)")
            return false
        }
    }

    // MARK: - 导入体重

    /// 读最近若干天的体重样本，按 externalID 去重后写进本地库。
    @discardableResult
    func importWeight(days: Int = 90) async -> ImportResult {
        guard isAvailable else { return .unavailable }
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            return .unavailable
        }
        guard await requestAuthorization() else { return .notAuthorized }

        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: Date(),
            options: .strictStartDate
        )
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 500,
                sortDescriptors: sort
            ) { _, results, error in
                if let error = error {
                    NSLog("[SummitScale] 读体重样本失败: \(error)")
                }
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }

        guard !samples.isEmpty else { return .noData }

        let unit = HKUnit.gramUnit(with: .kilo)
        let context = Persistence.shared.container.viewContext
        var inserted = 0
        var skipped = 0

        for sample in samples {
            let externalID = sample.uuid.uuidString
            if weightExists(externalID: externalID) {
                skipped += 1
                continue
            }
            let entry = WeightEntry(context: context)
            entry.id = UUID()
            entry.date = sample.endDate
            entry.kilograms = sample.quantity.doubleValue(for: unit)
            entry.note = "来自「健康」"
            entry.createdAt = Date()
            entry.source = "healthkit"
            entry.externalID = externalID
            inserted += 1
        }

        if inserted > 0 {
            Persistence.shared.save()
        }
        return .imported(inserted: inserted, skipped: skipped)
    }

    private func weightExists(externalID: String) -> Bool {
        let context = Persistence.shared.container.viewContext
        let request = WeightEntry.fetchRequest()
        request.predicate = NSPredicate(format: "externalID == %@", externalID)
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }
}

/// 导入结果，界面直接显示 `message`。
enum ImportResult {
    case unavailable
    case notAuthorized
    case noData
    case imported(inserted: Int, skipped: Int)

    var message: String {
        switch self {
        case .unavailable:
            return "这台设备没有「健康」数据，或者这个安装包拿不到 HealthKit 权限。"
        case .notAuthorized:
            return "没拿到「健康」的读取权限。去「设置 - 健康 - 数据访问」里允许再试。"
        case .noData:
            return "最近 90 天健康里也没有体重记录。"
        case .imported(let inserted, let skipped):
            if inserted == 0 {
                return "没有新数据，已有的 \(skipped) 条都在。"
            }
            if skipped > 0 {
                return "导入 \(inserted) 条体重，跳过 \(skipped) 条重复的。"
            }
            return "导入 \(inserted) 条体重。"
        }
    }
}
