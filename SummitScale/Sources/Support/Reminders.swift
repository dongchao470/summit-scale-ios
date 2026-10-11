import Foundation
import UserNotifications

/// 套餐到点提醒的本地通知。
///
/// 两层配合：通知由系统在设定时间弹出（App 不在后台也能到），
/// 真正的自动入账还是打开 App 时补一次 —— iOS 不给普通 App 随意跑后台代码。
enum Reminders {
    /// 申请通知权限。用户拒绝也返回 false，不抛错。
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            NSLog("[SummitScale] 通知授权失败：\(error.localizedDescription)")
            return false
        }
    }

    /// 按套餐的设定重建每日提醒。关掉自动填就顺手撤销。
    static func sync(_ template: MealTemplate) {
        let center = UNUserNotificationCenter.current()
        let id = identifier(for: template)
        center.removePendingNotificationRequests(withIdentifiers: [id])

        guard template.autoFillEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "该记\(template.meal.title)了"
        content.body = template.items.isEmpty
            ? "「\(template.name)」还是空的，先把内容配好。"
            : "「\(template.name)」到点了，打开 App 确认一下就记上，约 \(Fmt.kcal(template.totalKcal)) 千卡。"
        content.sound = .default
        // 挂上套餐身份，通知点开时才知道是哪条套餐的提醒。
        // （App 目前还没接 UNUserNotificationCenterDelegate，先把信息备好。）
        content.userInfo = [
            "templateID": template.id.uuidString,
            "templateName": template.name,
        ]

        var components = DateComponents()
        components.hour = Int(template.autoFillHour)
        components.minute = Int(template.autoFillMinute)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { error in
            if let error = error {
                NSLog("[SummitScale] 提醒注册失败：\(error.localizedDescription)")
            }
        }
    }

    static func cancel(_ template: MealTemplate) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: template)])
    }

    /// 当前已排上的提醒数量，设置页拿来显示状态。
    static func pendingCount() async -> Int {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.count)
            }
        }
    }

    /// 冷启动时把该排的提醒补排一遍。
    ///
    /// 用户一开始拒了通知权限、后来又去系统设置里打开的话，
    /// 之前 `sync` 失败的提醒不会自己回来——这里重排一次补上。
    /// `sync` 内部是「先撤销再登记」，重复调用没有副作用。
    static func resyncAll(_ templates: [MealTemplate]) {
        for template in templates where template.autoFillEnabled {
            sync(template)
        }
    }

    private static func identifier(for template: MealTemplate) -> String {
        "mealtemplate-\(template.id.uuidString)"
    }
}
