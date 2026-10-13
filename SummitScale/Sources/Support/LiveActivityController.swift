import ActivityKit
import Foundation
import os

/// 实时活动的唯一入口：主 App 侧负责开始 / 刷新 / 结束「今日热量」活动。
///
/// 设计原则：实时活动是锦上添花，任何异常都不许影响主流程——
/// 所有 ActivityKit 调用都包在 Task 里，失败只记一行日志。
/// 只用 iOS 16.1 就存在的同步 / async API：
/// `Activity.request(attributes:contentState:pushType:)`、`update(using:)`、`end(using:dismissalPolicy:)`，
/// 不用 16.2 才有的 ActivityContent 版本，避免旧 SDK 编不过。
@available(iOS 16.1, *)
final class LiveActivityController {
    static let shared = LiveActivityController()

    private init() {}

    private let logger = Logger(subsystem: "com.dongchao470.summit-scale", category: "LiveActivity")

    // MARK: - 对外接口

    /// 确保今天有一个实时活动。已有当天的活动就什么都不做（不重复创建）。
    func startIfNeeded(targetKcal: Double, dayStart: Date) {
        // 目标为 0：没有可比较的对象，开了也没意义。
        guard targetKcal > 0 else { return }
        let state = TodayActivityAttributes.ContentState(
            intakeKcal: 0,
            burnKcal: 0,
            steps: 0,
            distanceKm: 0,
            remainingKcal: targetKcal,
            progress: 0,
            isOverBudget: false,
            updatedAt: Date(),
            hasData: false
        )
        Task { [self] in
            await apply(state: state, dayStart: dayStart, targetKcal: targetKcal)
        }
    }

    /// 按快照刷新内容：有活动就更新（只更最新的一个），没有就创建。
    func sync(snapshot: WidgetSnapshot) {
        // 目标为 0 不创建活动，直接退出。
        guard snapshot.targetKcal > 0 else {
            logger.debug("skip live activity: targetKcal is 0")
            return
        }
        // 隔夜快照不驱动今天的活动，顺手把过期活动收掉。
        guard snapshot.isToday else {
            end()
            return
        }
        let state = TodayActivityAttributes.ContentState(
            intakeKcal: snapshot.intakeKcal,
            burnKcal: snapshot.burnKcal,
            steps: snapshot.steps,
            distanceKm: snapshot.distanceKm,
            // 派生值直接取快照，口径只在 WidgetBridge 里维护一处。
            remainingKcal: snapshot.remainingKcal,
            progress: snapshot.progress,
            isOverBudget: snapshot.isOverBudget,
            updatedAt: Date(),
            hasData: true
        )
        Task { [self] in
            await apply(state: state, dayStart: snapshot.dayStart, targetKcal: snapshot.targetKcal)
        }
    }

    /// 结束所有本 App 的实时活动（用户在设置里关掉开关、或数据被清空时调用）。
    func end() {
        let activities = Activity<TodayActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        Task { [self] in
            for activity in activities {
                await activity.end(using: nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - 内部

    /// 幂等落地：同一天的活动就地更新，跨天先 end 旧的再按新的一天创建。
    private func apply(state: TodayActivityAttributes.ContentState, dayStart: Date, targetKcal: Double) async {
        // 用户在系统设置里关掉了实时活动：别去 request，会抛异常。
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.debug("live activities disabled by user")
            return
        }

        let activities = Activity<TodayActivityAttributes>.activities
        // 只认最新的一个（activity 列表理论上同类型只应有一个）。
        let latest = activities.max { $0.attributes.dayStart < $1.attributes.dayStart }

        guard let latest else {
            await request(state: state, dayStart: dayStart, targetKcal: targetKcal)
            return
        }

        if Calendar.current.isDate(latest.attributes.dayStart, inSameDayAs: dayStart) {
            // 今天的活动：原地更新内容。
            await latest.update(using: state)
            // 顺带收掉历史残留，避免锁屏挂两个。
            await endOthers(keeping: latest)
        } else {
            // 跨天：先结束旧活动，再按新的一天创建。
            for activity in activities {
                await activity.end(using: nil, dismissalPolicy: .immediate)
            }
            await request(state: state, dayStart: dayStart, targetKcal: targetKcal)
        }
    }

    private func request(state: TodayActivityAttributes.ContentState, dayStart: Date, targetKcal: Double) async {
        let attributes = TodayActivityAttributes(dayStart: dayStart, targetKcal: targetKcal)
        do {
            _ = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
        } catch {
            // 静默失败：权限被关、达到系统上限、未签名环境不支持等，都不影响主流程。
            logger.error("live activity request failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func endOthers(keeping kept: Activity<TodayActivityAttributes>) async {
        for activity in Activity<TodayActivityAttributes>.activities where activity.id != kept.id {
            await activity.end(using: nil, dismissalPolicy: .immediate)
        }
    }
}
