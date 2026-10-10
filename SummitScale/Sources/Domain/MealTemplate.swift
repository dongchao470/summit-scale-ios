import CoreData
import Foundation

/// 一套常用餐（比如「标准早餐」）：一组食物，可以一键入账，也可以到点自动填。
@objc(MealTemplate)
public final class MealTemplate: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var mealType: String
    @NSManaged public var itemsJSON: String
    @NSManaged public var autoFillEnabled: Bool
    @NSManaged public var autoFillHour: Int16
    @NSManaged public var autoFillMinute: Int16
    @NSManaged public var sortIndex: Int16
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
}

extension MealTemplate: Identifiable {}

extension MealTemplate {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<MealTemplate> {
        NSFetchRequest<MealTemplate>(entityName: "MealTemplate")
    }

    /// 套餐归属的餐次。
    var meal: MealType {
        MealType(rawValue: mealType) ?? .breakfast
    }

    /// 套餐里的食物项。
    var items: [TemplateItem] {
        get { TemplateItem.decode(itemsJSON) }
        set { itemsJSON = TemplateItem.encode(newValue) }
    }

    /// 整套热量。
    var totalKcal: Double {
        items.reduce(0) { $0 + $1.kcal }
    }

    var itemCount: Int {
        items.count
    }

    /// 「08:00」这种展示文本。
    var autoFillTimeText: String {
        String(format: "%02d:%02d", autoFillHour, autoFillMinute)
    }
}

/// 套餐里的单项，序列化进 `MealTemplate.itemsJSON`。
///
/// 用 JSON 而不是 Core Data 关系，是为了避开程序化模型里反向关系写错就启动崩的坑；
/// 套餐条目数量少、结构固定，JSON 完全够用。
struct TemplateItem: Codable, Identifiable, Hashable {
    var id: String
    var foodID: String?
    var name: String
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var imageURL: String?

    init(
        id: String = UUID().uuidString,
        foodID: String? = nil,
        name: String,
        grams: Double,
        kcal: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        imageURL: String? = nil
    ) {
        self.id = id
        self.foodID = foodID
        self.name = name
        self.grams = grams
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.imageURL = imageURL
    }

    static func decode(_ json: String) -> [TemplateItem] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([TemplateItem].self, from: data)) ?? []
    }

    static func encode(_ items: [TemplateItem]) -> String {
        guard let data = try? JSONEncoder().encode(items) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// 按份数缩放，用来支持「1.5 份早餐」。
    func scaled(by factor: Double) -> TemplateItem {
        TemplateItem(
            id: id,
            foodID: foodID,
            name: name,
            grams: grams * factor,
            kcal: kcal * factor,
            protein: protein * factor,
            carbs: carbs * factor,
            fat: fat * factor,
            imageURL: imageURL
        )
    }
}
