import SwiftUI
import WidgetKit

@main
struct SummitScaleWidgetBundle: WidgetBundle {
    var body: some Widget {
        // 只注册主屏小组件。
        //
        // 排查记录：0.6.2 起桌面一直整块白屏，连「只有四行文字」的最小视图都不显示，
        // 而扩展没有任何崩溃记录——说明扩展压根没被系统加载。
        // 0.6.2 相对 0.6.0 唯一新增的、与扩展加载有关的变量就是 ActivityKit（锁屏实时活动），
        // 所以这一版把实时活动整体移出编译清单，先确认 widget 能不能活过来。
        // （文件在 git 历史里，没丢；确认后再决定加不加回来。）
        TodayCalorieWidget()
    }
}
