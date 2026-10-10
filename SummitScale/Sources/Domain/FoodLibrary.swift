import Foundation

/// 单个食物的营养值，统一按每 100 克计。
struct FoodItem: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let kcalPer100g: Double
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double
    /// 常见一份的克数。
    let commonGrams: Double
    /// 常见一份的说法。
    let commonLabel: String

    /// 按克数换算这一份的热量。
    func kcal(grams: Double) -> Double { kcalPer100g * grams / 100 }

    func protein(grams: Double) -> Double { proteinPer100g * grams / 100 }

    func carbs(grams: Double) -> Double { carbsPer100g * grams / 100 }

    func fat(grams: Double) -> Double { fatPer100g * grams / 100 }
}

/// 常见食物热量表。数值取自《中国食物成分表》常见档位，粗算够用，不做医疗依据。
///
/// 数据写成一个紧凑的多行字符串再解析，比几百行构造器短，也方便逐条校对。
enum FoodLibrary {
    static let items: [FoodItem] = parse(raw)

    static var categories: [String] {
        var seen: [String] = []
        for item in items where !seen.contains(item.category) {
            seen.append(item.category)
        }
        return seen
    }

    static func items(in category: String) -> [FoodItem] {
        items.filter { $0.category == category }
    }

    static func item(id: String) -> FoodItem? {
        items.first { $0.id == id }
    }

    /// 按名称模糊搜，空词返回全部。
    static func search(_ keyword: String) -> [FoodItem] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.name.contains(trimmed) || $0.category.contains(trimmed) || $0.id.contains(trimmed.lowercased())
        }
    }

    private static func parse(_ text: String) -> [FoodItem] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 9,
                  let kcal = Double(parts[3]),
                  let protein = Double(parts[4]),
                  let carbs = Double(parts[5]),
                  let fat = Double(parts[6]),
                  let grams = Double(parts[7])
            else { return nil }
            return FoodItem(
                id: parts[0],
                name: parts[1],
                category: parts[2],
                kcalPer100g: kcal,
                proteinPer100g: protein,
                carbsPer100g: carbs,
                fatPer100g: fat,
                commonGrams: grams,
                commonLabel: parts[8]
            )
        }
    }

    private static let raw = """
    rice_cooked|米饭（蒸）|主食|116|2.6|25.9|0.3|150|1 碗
    rice_brown|糙米饭|主食|112|2.6|23.5|0.9|150|1 碗
    mantou|馒头|主食|223|7.0|47.0|1.1|100|1 个
    noodles|面条（煮）|主食|110|2.7|24.3|0.2|200|1 碗
    congee|白粥|主食|46|1.1|9.9|0.2|250|1 碗
    rice_noodle|米粉（煮）|主食|109|2.4|24.9|0.2|200|1 碗
    youtiao|油条|主食|388|6.9|51.0|17.6|60|1 根
    baozi|包子（猪肉）|主食|227|7.8|32.0|8.0|100|1 个
    dumpling|饺子（猪肉）|主食|240|9.0|30.0|9.0|120|6 个
    bread_whole|全麦面包|主食|246|9.0|46.0|3.3|35|1 片
    bread_toast|吐司面包|主食|312|8.3|58.6|3.5|35|1 片
    oats|燕麦片（干）|主食|377|15.0|66.9|6.7|40|1 份
    corn|玉米（煮）|主食|112|4.0|22.8|1.2|200|1 根
    sweet_potato|红薯（蒸）|主食|86|1.6|20.1|0.2|150|1 个
    potato|土豆（蒸）|主食|81|2.0|17.8|0.2|150|1 个
    chicken_breast|鸡胸肉|肉蛋|133|19.4|2.5|5.0|100|1 块
    chicken_leg|鸡腿|肉蛋|181|16.0|0|13.0|100|1 只
    chicken_wing|鸡翅|肉蛋|194|17.4|4.6|11.8|90|2 只
    pork_lean|猪里脊|肉蛋|155|20.2|0.7|7.9|100|1 份
    pork_belly|猪肉（肥瘦）|肉蛋|395|13.2|2.4|37.0|100|1 份
    pork_rib|猪大排|肉蛋|264|18.3|1.7|20.4|100|2 块
    beef_lean|牛肉（瘦）|肉蛋|106|20.2|1.2|2.3|100|1 份
    lamb_lean|羊肉（瘦）|肉蛋|118|20.5|0.2|3.9|100|1 份
    duck|鸭肉|肉蛋|240|15.5|0.2|19.7|100|1 份
    salmon|三文鱼|肉蛋|139|17.2|0|7.8|100|1 块
    hairtail|带鱼|肉蛋|127|17.7|3.1|4.9|100|1 段
    bass|鲈鱼|肉蛋|105|18.6|0|3.4|100|1 条
    shrimp|青虾|肉蛋|87|16.4|1.4|1.5|100|8 只
    bacon|培根|肉蛋|181|22.3|0|9.3|30|2 片
    ham_sausage|火腿肠|肉蛋|212|14.0|10.0|14.0|45|1 根
    egg_boiled|鸡蛋（煮）|蛋奶|144|13.3|2.8|8.8|50|1 个
    egg_fried|煎蛋|蛋奶|200|13.5|1.4|15.0|60|1 个
    egg_white|鸡蛋白|蛋奶|60|11.6|3.1|0.1|33|1 个
    milk_whole|全脂牛奶|蛋奶|65|3.3|4.9|3.6|250|1 杯
    milk_skim|脱脂牛奶|蛋奶|34|3.4|4.8|0.3|250|1 杯
    yogurt|酸奶（原味）|蛋奶|72|2.5|9.3|2.7|150|1 杯
    yogurt_greek|希腊酸奶|蛋奶|97|9.0|3.6|5.0|150|1 杯
    cheese|奶酪|蛋奶|328|25.7|3.5|23.5|20|1 片
    soy_milk|豆浆（无糖）|蛋奶|31|3.0|1.2|1.6|250|1 杯
    tofu_north|豆腐（北）|豆类|98|12.2|1.5|4.8|100|1 块
    tofu_south|豆腐（南）|豆类|87|6.2|2.4|4.8|100|1 块
    dried_tofu|豆干|豆类|140|16.2|4.5|6.9|80|1 份
    fuzhu|腐竹|豆类|459|44.6|22.3|21.7|30|1 份
    soybean|黄豆|豆类|390|35.0|34.2|16.0|50|1 份
    mung_bean|绿豆|豆类|329|21.6|62.0|0.8|50|1 份
    broccoli|西兰花|蔬菜|36|4.1|4.3|0.6|150|1 份
    spinach|菠菜|蔬菜|28|2.6|4.5|0.3|150|1 份
    cabbage|白菜|蔬菜|20|1.5|3.4|0.1|200|1 份
    cucumber|黄瓜|蔬菜|16|0.8|2.9|0.2|150|1 根
    tomato|番茄|蔬菜|20|0.9|4.0|0.2|150|1 个
    green_pepper|青椒|蔬菜|22|1.4|5.4|0.3|100|1 个
    carrot|胡萝卜|蔬菜|39|1.0|8.8|0.2|100|1 根
    lettuce|生菜|蔬菜|15|1.4|2.0|0.4|100|1 份
    youmaicai|油麦菜|蔬菜|15|1.4|2.1|0.4|150|1 份
    shiitake|香菇（鲜）|蔬菜|26|2.2|5.2|0.3|100|1 份
    eggplant|茄子|蔬菜|23|1.1|4.9|0.2|150|1 根
    onion|洋葱|蔬菜|40|1.1|9.0|0.2|100|1 个
    apple|苹果|水果|53|0.2|13.5|0.2|200|1 个
    banana|香蕉|水果|93|1.4|22.0|0.2|120|1 根
    orange|橙子|水果|48|0.8|11.1|0.2|180|1 个
    grape|葡萄|水果|45|0.5|10.3|0.2|150|1 串
    watermelon|西瓜|水果|32|0.6|7.9|0.1|300|1 块
    pear|梨|水果|51|0.4|13.1|0.2|200|1 个
    strawberry|草莓|水果|32|1.0|7.1|0.2|150|8 颗
    blueberry|蓝莓|水果|57|0.7|14.5|0.3|100|1 份
    kiwi|猕猴桃|水果|61|0.8|14.5|0.6|100|1 个
    peach|桃子|水果|51|0.9|12.2|0.1|180|1 个
    mango|芒果|水果|60|0.6|15.0|0.4|150|1 个
    avocado|牛油果|水果|171|2.0|7.4|15.3|100|1 个
    walnut|核桃（干）|坚果|646|14.9|19.1|58.8|30|3 个
    almond|杏仁|坚果|578|22.5|23.9|45.4|25|1 小把
    peanut|花生（炒）|坚果|601|21.7|23.8|48.0|30|1 小把
    cashew|腰果|坚果|559|17.3|41.6|36.7|25|1 小把
    pistachio|开心果|坚果|614|20.6|21.9|53.0|25|1 小把
    sunflower_seed|瓜子|坚果|606|19.1|12.5|53.4|30|1 小把
    cola|可乐|饮品|43|0|10.8|0|330|1 罐
    cola_zero|无糖可乐|饮品|0|0|0|0|330|1 罐
    orange_juice|橙汁（鲜榨）|饮品|45|0.7|10.4|0.2|250|1 杯
    beer|啤酒|饮品|32|0.4|3.1|0|330|1 罐
    wine_red|红酒|饮品|85|0.1|2.5|0|150|1 杯
    baijiu|白酒（52 度）|饮品|322|0|0.1|0|50|1 两
    americano|美式咖啡|饮品|2|0.1|0.3|0|240|1 杯
    latte|拿铁|饮品|55|3.0|4.5|3.0|240|1 杯
    milk_tea|奶茶（全糖）|饮品|70|0.8|13.0|1.8|500|1 杯
    sports_drink|运动饮料|饮品|26|0|6.4|0|500|1 瓶
    burger|汉堡（牛肉）|快餐|250|12.0|28.0|10.0|200|1 个
    fried_chicken|炸鸡|快餐|279|19.0|12.0|17.0|100|2 块
    fries|薯条|快餐|298|4.0|38.0|14.0|100|1 中份
    pizza|披萨|快餐|266|11.0|33.0|10.0|100|2 片
    sandwich|三明治|快餐|240|11.0|28.0|9.0|180|1 个
    instant_noodle|泡面|快餐|472|9.5|61.0|21.0|100|1 包
    malatang|麻辣烫|快餐|130|6.0|12.0|6.5|400|1 份
    fried_dumpling|煎饺|快餐|240|8.0|28.0|10.0|120|6 个
    chips|薯片|零食|548|6.5|52.0|35.0|50|1 小包
    dark_chocolate|黑巧克力|零食|586|7.8|45.0|40.0|30|2 块
    ice_cream|冰淇淋|零食|127|2.4|17.3|5.3|100|1 份
    cream_cake|奶油蛋糕|零食|379|4.5|40.0|22.0|100|1 块
    soda_cracker|苏打饼干|零食|408|8.4|76.2|7.7|30|3 片
    jelly|果冻|零食|60|0.1|15.0|0|100|1 个
    vegetable_oil|植物油|调味|899|0|0|99.9|10|1 勺
    lard|猪油|调味|897|0|0|99.6|10|1 勺
    butter|黄油|调味|888|1.4|0|98.0|10|1 片
    mayonnaise|沙拉酱|调味|724|1.1|3.0|78.0|15|1 勺
    soy_sauce|酱油|调味|63|5.6|10.1|0.1|10|1 勺
    sugar|白糖|调味|400|0|99.9|0|10|1 勺
    honey|蜂蜜|调味|321|0.4|75.6|1.9|20|1 勺
    peanut_butter|花生酱|调味|600|25.0|20.0|50.0|15|1 勺
    """
}
