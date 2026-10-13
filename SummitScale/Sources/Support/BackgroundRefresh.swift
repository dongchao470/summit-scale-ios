import BackgroundTasks
import Foundation

/// 后台刷新：App 不在前台时，也把「健康」那部分数字补进共享快照，让桌面 widget 有新数据。
///
/// 只补健康数据的理由：摄入总量、手动记录的运动都存在 App 的 CoreData 里，
/// 而 App 没打开时用户也不会新增这些记录（唯一入口就是 App 自己），
/// 所以读上一份快照、只替换健康来源的字段就够了，不必在后台拉起整套 CoreData。
/// 想完整重算（含当天新吃的、新记的运动），还是得等用户打开 App——
/// TodayView 的 publishWidgetSnapshot() 会重写整份快照。
///
/// 注意：BGAppRefreshTask 的 earliestBeginDate 只是「最早什么时候可以叫醒我」的建议，
/// 系统按电量与使用习惯自行决定，可能几十分钟来一次，也可能十几个小时不来。
/// 所以 widget 必须显示 savedAt（数据更新时间），不能让用户以为那是实时值。
enum BackgroundRefresh {
    /// 必须与 Info.plist 的 BGTaskSchedulerPermittedIdentifiers 完全一致。
    static let identifier = "com.dongchao470.summit-scale.refresh"
    /// 最早间隔给 30 分钟；再密也没用，系统不会照着给。
    static let earliestInterval: TimeInterval = 30 * 60

    /// 启动阶段注册一次：BGTaskScheduler 要求注册发生在启动完成前，
    /// 放在 SummitScaleApp.init() 里最稳。
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    /// App 进后台时排下一轮；在前台时也顺手排一次，不冲突。
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // 排不上不致命：回到 App 时会重写快照。
            print("[BackgroundRefresh] 排程失败：\(error.localizedDescription)")
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // 先把下一轮排上：这次无论成败，之后还得接着刷。
        schedule()

        let work = Task {
            let ok = await refreshSnapshot()
            task.setTaskCompleted(success: ok)
        }
        // 系统要收回时间就取消任务，别占着唤醒配额。
        task.expirationHandler = { work.cancel() }
    }

    /// 拉健康今日活动 → 合并进旧快照 → 写回共享容器。返回是否真的写了。
    /// HealthKitManager 是主 actor 隔离的，这里跟着它走——后台刷新本来也不争这点时间。
    @MainActor
    private static func refreshSnapshot() async -> Bool {
        guard HealthKitManager.shared.enabledByUser else { return false }

        let activity = await withCheckedContinuation { (continuation: CheckedContinuation<HealthKitManager.TodayActivity, Never>) in
            HealthKitManager.shared.todayActivityDetail { continuation.resume(returning: $0) }
        }
        if Task.isCancelled { return false }
        guard activity.steps > 0 || activity.activeKcal > 0 else { return false }

        let today = Calendar.current.startOfDay(for: Date())
        let previous = WidgetBridge.read()
        // 跨天：摄入与手动运动归零，只延续目标值——昨天的账不能记到今天头上。
        let base = (previous?.dayStart == today) ? previous : nil
        let target = base?.targetKcal ?? previous?.targetKcal ?? 0
        guard target > 0 else { return false }

        let snapshot = WidgetSnapshot(
            savedAt: Date(),
            dayStart: today,
            intakeKcal: base?.intakeKcal ?? 0,
            targetKcal: target,
            burnKcal: activity.activeKcal + (base?.manualBurnKcal ?? 0),
            steps: Double(activity.steps),
            distanceKm: base?.distanceKm ?? 0,
            exerciseMinutes: Double(activity.exerciseMinutes),
            weightKg: base?.weightKg,
            targetWeightKg: base?.targetWeightKg,
            healthBurnKcal: activity.activeKcal,
            manualBurnKcal: base?.manualBurnKcal ?? 0
        )
        WidgetBridge.publish(snapshot)

        // 锁屏实时活动跟着一起刷新；iOS 16.1 以下没有这东西。
        if #available(iOS 16.1, *) {
            LiveActivityController.shared.sync(snapshot: snapshot)
        }
        return true
    }
}
