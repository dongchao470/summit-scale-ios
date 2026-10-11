import UIKit

/// 分类图标。
///
/// 成分表那 1503 条食材和中式成菜那 100 条没有照片，列表里全留白太难看，
/// 按分类给一个 SF Symbol 顶上。
///
/// 这里刻意用 switch 而不是 [String: String] 字面量：0.3.4 build 7 与 0.3.5 build 8
/// 两次真机崩溃都停在标准库的 dictionaryLiteral 路径上（见 FoodImages 的说明）。
/// 分类表虽然只有 15 项，也没必要留同一种写法 —— switch 不构造集合，没有初始化。
///
/// 符号名写错在真机上只会静默显示空白、不会崩，很难发现，所以每次取值都用
/// `UIImage(systemName:)` 验一遍，系统没有就退回 fork.knife。
/// 这样即使 iOS 16 上某个符号不存在，最坏也只是少一点区分度。
enum FoodCategorySymbol {
    private static let fallback = "fork.knife"

    /// 分类对应的符号名；不认识的分类交给 fallback。
    private static func name(for category: String) -> String {
        switch category {
        case "主食": return "takeoutbag.and.cup.and.straw.fill"
        case "家常菜": return fallback
        case "肉蛋": return "fish.fill"
        case "蛋奶": return "cup.and.saucer.fill"
        case "豆类": return "circle.hexagongrid.fill"
        case "蔬菜": return "leaf.fill"
        case "水果": return "carrot.fill"
        case "坚果": return "oval.fill"
        case "汤粥": return "mug.fill"
        case "火锅": return "flame.fill"
        case "快餐": return "bag.fill"
        case "零食": return "bag.fill"
        case "咖啡奶茶": return "cup.and.saucer.fill"
        case "饮品": return "waterbottle.fill"
        case "调味": return "drop.fill"
        default: return fallback
        }
    }

    static func symbol(for category: String) -> String {
        let candidate = name(for: category)
        return UIImage(systemName: candidate) == nil ? fallback : candidate
    }
}
