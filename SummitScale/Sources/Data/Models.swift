import CoreData
import Foundation

// MARK: - 体重

@objc(WeightEntry)
final class WeightEntry: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var date: Date
    @NSManaged var kilograms: Double
    @NSManaged var note: String?
    @NSManaged var createdAt: Date
    @NSManaged var source: String
    @NSManaged var externalID: String?
}

extension WeightEntry {
    @nonobjc
    class func fetchRequest() -> NSFetchRequest<WeightEntry> {
        NSFetchRequest<WeightEntry>(entityName: "WeightEntry")
    }

    static var dateDescending: [NSSortDescriptor] {
        [
            NSSortDescriptor(key: "date", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false),
        ]
    }

    static var dateAscending: [NSSortDescriptor] {
        [
            NSSortDescriptor(key: "date", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
        ]
    }
}

// MARK: - 爬山（v0.1 遗留）

/// 旧版爬山记录。v0.2 起统一用 `ActivityEntry`，这张表只为兼容既有数据保留，
/// 启动时会被 `migrateLegacyHikesIfNeeded()` 搬空。
@objc(Hike)
final class Hike: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var date: Date
    @NSManaged var title: String
    @NSManaged var distanceKilometers: Double
    @NSManaged var elevationGainMeters: Double
    @NSManaged var durationMinutes: Double
    @NSManaged var note: String?
    @NSManaged var createdAt: Date
    @NSManaged var source: String
    @NSManaged var externalID: String?
}

extension Hike {
    @nonobjc
    class func fetchRequest() -> NSFetchRequest<Hike> {
        NSFetchRequest<Hike>(entityName: "Hike")
    }

    static var dateDescending: [NSSortDescriptor] {
        [
            NSSortDescriptor(key: "date", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false),
        ]
    }

    static var dateAscending: [NSSortDescriptor] {
        [
            NSSortDescriptor(key: "date", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
        ]
    }
}

// MARK: - 用户档案

@objc(UserProfile)
final class UserProfile: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var sex: String
    @NSManaged var birthDate: Date
    @NSManaged var heightCentimeters: Double
    @NSManaged var startWeightKilograms: Double
    @NSManaged var activityLevel: String
    @NSManaged var goalType: String
    @NSManaged var targetWeightKilograms: Double
    /// 大于 0 时覆盖自动算出来的目标摄入量。
    @NSManaged var dailyCalorieOverride: Double
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
}

extension UserProfile {
    @nonobjc
    class func fetchRequest() -> NSFetchRequest<UserProfile> {
        NSFetchRequest<UserProfile>(entityName: "UserProfile")
    }

    var sexValue: Sex { Sex(rawValue: sex) ?? .female }

    var activityValue: ActivityLevel { ActivityLevel(rawValue: activityLevel) ?? .light }

    var goalValue: GoalType { GoalType(rawValue: goalType) ?? .maintain }

    /// 身高体重都填过了，才算能参与热量计算。
    var isComplete: Bool { heightCentimeters > 0 && startWeightKilograms > 0 }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "你" : name
    }
}

// MARK: - 饮食

@objc(FoodEntry)
final class FoodEntry: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var date: Date
    @NSManaged var name: String
    @NSManaged var mealType: String
    @NSManaged var grams: Double
    @NSManaged var kcal: Double
    @NSManaged var protein: Double
    @NSManaged var carbs: Double
    @NSManaged var fat: Double
    @NSManaged var foodID: String?
    /// 联网食物带回来的图片地址；本地库记录的为空。
    @NSManaged var imageURL: String?
    @NSManaged var note: String?
    @NSManaged var createdAt: Date
    @NSManaged var source: String
    @NSManaged var externalID: String?
}

extension FoodEntry {
    @nonobjc
    class func fetchRequest() -> NSFetchRequest<FoodEntry> {
        NSFetchRequest<FoodEntry>(entityName: "FoodEntry")
    }

    static var dateDescending: [NSSortDescriptor] {
        [
            NSSortDescriptor(key: "date", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false),
        ]
    }

    var mealValue: MealType { MealType(rawValue: mealType) ?? .snack }
}

// MARK: - 活动

@objc(ActivityEntry)
final class ActivityEntry: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var date: Date
    @NSManaged var kind: String
    @NSManaged var title: String
    @NSManaged var durationMinutes: Double
    @NSManaged var distanceKilometers: Double
    @NSManaged var elevationGainMeters: Double
    @NSManaged var kcal: Double
    @NSManaged var note: String?
    @NSManaged var createdAt: Date
    @NSManaged var source: String
    @NSManaged var externalID: String?
}

extension ActivityEntry {
    @nonobjc
    class func fetchRequest() -> NSFetchRequest<ActivityEntry> {
        NSFetchRequest<ActivityEntry>(entityName: "ActivityEntry")
    }

    static var dateDescending: [NSSortDescriptor] {
        [
            NSSortDescriptor(key: "date", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false),
        ]
    }

    var kindValue: ActivityKind { ActivityKind(rawValue: kind) ?? .other }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kindValue.title : title
    }
}

// MARK: - 列表渲染

/// SwiftUI 的 ForEach 要求元素可辨识，这几个模型的 id 本来就是 UUID。
extension WeightEntry: Identifiable {}

extension FoodEntry: Identifiable {}

extension ActivityEntry: Identifiable {}
