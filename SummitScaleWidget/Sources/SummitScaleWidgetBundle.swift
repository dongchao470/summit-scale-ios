import SwiftUI
import WidgetKit

@main
struct SummitScaleWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayCalorieWidget()

        // 锁屏实时活动：ActivityKit 要 iOS 16.1 起，低版本系统把这一项摘掉。
        if #available(iOS 16.1, *) {
            TodayLiveActivityWidget()
        }
    }
}
