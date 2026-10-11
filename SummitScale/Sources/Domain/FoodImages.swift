import Foundation

/// 本地食物库的配图。
///
/// 图片来自下厨房搜索页，按食物名匹配；0.3.5 起压到 256×256 打包进 Assets 的
/// FoodImages 组，资源名是 food_<食物 id>，断网也有图。
///
/// 这里刻意不留任何 id 名单。0.3.4 build 7 和 0.3.5 build 8 两次真机崩溃，栈帧都停在
/// 「配图表的懒加载 -> 标准库 dictionaryLiteral -> EXC_BREAKPOINT / SIGTRAP」。
/// 换掉字典写法、把名单搬进字符串常量，都只是「换一条看起来安全的路径」，而这份名单
/// 本来就只是「这个食物有没有图」的缓存 —— 那还不如让 UIImage(named:) 直接回答：
/// 没有对应资源就返回 nil，界面自动退回分类图标。
///
/// 于是这里只剩一个纯函数：没有静态存储，没有懒加载，也没有初始化这回事。
enum FoodImages {
    /// 打包进 App 的配图资源名。这个 id 没配图时，UIImage(named:) 会返回 nil。
    static func assetName(for id: String) -> String {
        "food_" + id
    }
}
