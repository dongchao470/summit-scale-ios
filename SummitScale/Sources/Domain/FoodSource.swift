import Foundation

/// 一条饮食记录的来源。
///
/// 0.3.2 之前这里没有区分：不管是从本地食物库挑的、联网搜来的，
/// 还是手动敲的，`FoodEntry.source` 一律写成 "manual"，
/// 结果统计和排查都没法按来源分开看。这里补上明确的取值。
enum FoodSource {
    /// 手动敲的热量。
    static let manual = "manual"
    /// 从本地食物库挑的。
    static let library = "library"
    /// 联网搜索来的（下厨房 / Open Food Facts 等）。
    static let remote = "remote"
    /// 套餐入账，和 `Store+Template` 里写的保持一致。
    static let template = "template"

    /// 界面上显示用的名字。
    static func title(_ raw: String?) -> String {
        switch raw {
        case library: return "食物库"
        case remote: return "联网"
        case template: return "套餐"
        default: return "手动"
        }
    }
}
