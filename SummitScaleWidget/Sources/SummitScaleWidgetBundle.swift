import SwiftUI
import WidgetKit

@main
struct SummitScaleWidgetBundle: WidgetBundle {
    var body: some Widget {
        // 只注册主屏小组件。
        //
        // 锁屏实时活动（TodayLiveActivityWidget，代码还在 TodayLiveActivity.swift 里）这一版先不注册：
        // 0.6.2 起桌面小组件整块白屏，排查时把「新视图」和「新增的注册项」一起摘掉，
        // 先确认 widget 能正常显示，再一项一项加回来——一次只动一个变量，免得又白一轮。
        TodayCalorieWidget()
    }
}
