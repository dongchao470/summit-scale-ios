import Foundation
import WidgetKit

/// 小组件共享快照：主 App 负责算好、写进来，widget 只读不算。
///
/// 为什么走 App Group 而不是让 widget 自己查：摄入总量来自 App 自己的 CoreData
/// （食物条目），HealthKit 里没有，widget 进程读不到主 App 的沙盒。
///
/// 这个文件同时被主 App 和 widget extension 编译（见 project.yml），
/// 所以只放扁平值类型，别引用 Store / CoreData / UIKit，否则 widget 侧连带一大串依赖。
struct WidgetSnapshot: Codable, Equatable {
    /// 写入时刻，用于判断快照新鲜度。
    var savedAt: Date
    /// 数据归属日（当天 0 点）。跨天后 widget 会认为快照过期。
    var dayStart: Date

    var intakeKcal: Double
    var targetKcal: Double
    var burnKcal: Double
    var steps: Double
    var distanceKm: Double
    var exerciseMinutes: Double
    var weightKg: Double?
    var targetWeightKg: Double?
    /// 健康活跃消耗（Apple 口径，含锻炼）。
    /// 后台刷新时读不到 App 里的 CoreData，所以把口径拆开存：后台只替换健康那一半，
    /// 手动记录保持原值——不拆开就只能二选一，要么丢手动记录、要么后台不刷消耗。
    var healthBurnKcal: Double
    /// 手动记录的运动消耗（不含健康导入条目）。
    var manualBurnKcal: Double

    // MARK: - 派生值
    // 与 DayLedger（Sources/Domain/Calories.swift）同一套算法。
    // 主 App 改口径时，这里必须同步，否则又会出现「两边数字对不上」。

    /// 还能吃多少：目标 + 运动消耗 − 已吃。
    var remainingKcal: Double { targetKcal + burnKcal - intakeKcal }

    /// 净摄入 = 吃进去的 − 运动掉的。
    var netKcal: Double { intakeKcal - burnKcal }

    /// 画环用的完成度，限制在 0～1。
    var progress: Double {
        guard targetKcal > 0 else { return 0 }
        return min(1, max(0, netKcal / targetKcal))
    }

    var isOverBudget: Bool { remainingKcal < 0 }

    /// 快照是不是今天的。不是就当没有数据，避免 widget 显示隔夜旧数字。
    var isToday: Bool { Calendar.current.isDateInToday(dayStart) }

    /// 占位数据（只用于 widget 的 placeholder / 预览，不写盘）。
    static let placeholder = WidgetSnapshot(
        savedAt: Date(),
        dayStart: Calendar.current.startOfDay(for: Date()),
        intakeKcal: 860,
        targetKcal: 1680,
        burnKcal: 320,
        steps: 6421,
        distanceKm: 4.6,
        exerciseMinutes: 32,
        weightKg: 70.4,
        targetWeightKg: 65,
        healthBurnKcal: 245,
        manualBurnKcal: 75
    )
}

/// 主 App ↔ widget 的唯一通道。
enum WidgetBridge {
    static let appGroupID = "group.com.dongchao470.summit-scale"
    private static let key = "widget.snapshot.v1"

    /// 共享容器。未签名 / 非标准安装环境下可能拿不到，拿不到就返回 nil。
    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// 共享通道是否真的可用。设置页拿它做诊断——装机后一眼就能看出通道通不通。
    static var isSharedContainerAvailable: Bool { sharedContainerURL != nil }

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// 主 App 侧调用：写快照 + 让系统刷新时间线。
    static func publish(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        sharedDefaults?.set(data, forKey: key)
        // 同时在主 App 沙盒留一份，纯粹给设置页诊断用（widget 读不到这份）。
        UserDefaults.standard.set(data, forKey: key)
        reload()
    }

    /// widget 侧调用：读快照。
    static func read() -> WidgetSnapshot? {
        guard let data = sharedDefaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
