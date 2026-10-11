import UIKit

/// 分类图标。
///
/// 成分表那 1503 条食材和中式成菜那 100 条没有照片，列表里全留白太难看，
/// 按分类给一个 SF Symbol 顶上。
///
/// 符号名写错在真机上只会静默显示空白、不会崩，很难发现，所以每次取值都用
/// `UIImage(systemName:)` 验一遍，系统没有就退回 fork.knife。
/// 这样即使 iOS 16 上某个符号不存在，最坏也只是少一点区分度。
enum FoodCategorySymbol {
    private static let fallback = "fork.knife"

    private static let table: [String: String] = [
        "主食": "takeoutbag.and.cup.and.straw.fill",
        "家常菜": "fork.knife",
        "肉蛋": "fish.fill",
        "蛋奶": "cup.and.saucer.fill",
        "豆类": "circle.hexagongrid.fill",
        "蔬菜": "leaf.fill",
        "水果": "carrot.fill",
        "坚果": "oval.fill",
        "汤粥": "mug.fill",
        "火锅": "flame.fill",
        "快餐": "bag.fill",
        "零食": "bag.fill",
        "咖啡奶茶": "cup.and.saucer.fill",
        "饮品": "waterbottle.fill",
        "调味": "drop.fill",
    ]

    static func symbol(for category: String) -> String {
        let name = table[category] ?? fallback
        return UIImage(systemName: name) == nil ? fallback : name
    }
}
