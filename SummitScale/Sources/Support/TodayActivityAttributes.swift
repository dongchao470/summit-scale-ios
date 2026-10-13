import Foundation
import ActivityKit

/// 实时活动（锁屏 + 灵动岛）的数据契约。
///
/// 这个文件被主 App 和 widget 扩展**同时编译**（见 project.yml 的 widget target 清单），
/// 所以只允许依赖 Foundation / ActivityKit：一旦 import UIKit / CoreData / HealthKit，
/// 小组件会被连带拖进半个 App 的依赖与权限面。
@available(iOS 16.1, *)
struct TodayActivityAttributes: ActivityAttributes {

    /// 动态部分：每次同步（sync）整体换一份。
    struct ContentState: Codable, Hashable {
        /// 今日摄入（千卡）。
        var intakeKcal: Double
        /// 今日运动消耗（千卡）。
        var burnKcal: Double
        var steps: Double
        var distanceKm: Double
        /// 还能吃多少：目标 + 运动 − 已吃。直接取 WidgetSnapshot.remainingKcal，
        /// 口径只在 WidgetBridge 里维护一处，这里不重新发明算法。
        var remainingKcal: Double
        /// 完成度 0...1，超支也夹在 1。
        var progress: Double
        var isOverBudget: Bool
        /// 内容生成时刻，锁屏底部显示「更新于 HH:mm」。
        var updatedAt: Date
        /// 有没有拿到今天的真实数据。false 时视图显示「打开 App 同步」，不显示假数字。
        var hasData: Bool
    }

    /// 数据归属日（当天 0 点）。跨天靠它判断活动是否过期。
    var dayStart: Date
    /// 今日热量目标。活动期间不变，放静态部分省得每次同步都传。
    var targetKcal: Double
}
