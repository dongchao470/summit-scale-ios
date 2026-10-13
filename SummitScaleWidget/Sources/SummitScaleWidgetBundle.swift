import SwiftUI
import WidgetKit

@main
struct SummitScaleWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayCalorieWidget()

        // 运动款：消耗大数 + 步数/活动/距离，没数据时躺平小人。
        SportTodayWidget()

        // 锁屏实时活动：ActivityKit 要 iOS 16.1 起，低版本系统把这一项摘掉。
        if #available(iOS 16.1, *) {
            TodayLiveActivityWidget()
        }
    }
}
