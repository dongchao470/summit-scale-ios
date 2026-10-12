import CoreData
import Foundation

/// Core Data 栈。
///
/// 数据模型用 `NSManagedObjectModel` 程序化构建，不依赖 `.xcdatamodeld`：
/// 源码即模型，改字段只改一处，也不怕生成器/资源编译在 CI 上打架。
final class Persistence {
    static let shared = Persistence()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let model = Persistence.makeModel()
        let container = NSPersistentContainer(name: "SummitScale", managedObjectModel: model)
        self.container = container

        if inMemory, let description = container.persistentStoreDescriptions.first {
            description.url = URL(fileURLWithPath: "/dev/null")
        }

        // 新增字段（心率）靠轻量迁移补齐：显式打开迁移与模型推断，避免默认值变化直接丢库。
        for description in container.persistentStoreDescriptions {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        container.loadPersistentStores { description, error in
            guard let error = error as NSError? else { return }
            NSLog("[SummitScale] store 加载失败: \(error), \(error.userInfo)")

            // 自愈：本地存储损坏或模型不兼容时删掉重建，别让用户看到启动即崩。
            // 先改名留个备份，万一只是模型没迁移上，数据还能捞回来。
            if let url = description.url {
                let fm = FileManager.default
                let backup = url.appendingPathExtension("broken-backup")
                try? fm.removeItem(at: backup)
                if fm.fileExists(atPath: url.path) {
                    try? fm.moveItem(at: url, to: backup)
                }
                try? fm.removeItem(at: url)
                try? fm.removeItem(at: url.appendingPathExtension("wal"))
                try? fm.removeItem(at: url.appendingPathExtension("shm"))
            }
            container.loadPersistentStores { _, retryError in
                if let retryError = retryError as NSError? {
                    NSLog("[SummitScale] store 重建后仍失败: \(retryError)")
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.shouldDeleteInaccessibleFaults = true
        container.viewContext.name = "viewContext"
    }
}

// MARK: - 模型定义

extension Persistence {
    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = [
            weightEntity(),
            hikeEntity(),
            profileEntity(),
            foodEntity(),
            activityEntity(),
            mealTemplateEntity(),
        ]
        return model
    }

    private static func mealTemplateEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "MealTemplate"
        entity.managedObjectClassName = "MealTemplate"
        entity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType, default: ""),
            attribute("mealType", .stringAttributeType, default: "breakfast"),
            attribute("itemsJSON", .stringAttributeType, default: "[]"),
            attribute("autoFillEnabled", .booleanAttributeType, default: false),
            attribute("autoFillHour", .integer16AttributeType, default: Int16(8)),
            attribute("autoFillMinute", .integer16AttributeType, default: Int16(0)),
            attribute("sortIndex", .integer16AttributeType, default: Int16(0)),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
        ]
        return entity
    }

    private static func weightEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "WeightEntry"
        entity.managedObjectClassName = "WeightEntry"
        entity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("date", .dateAttributeType, indexed: true),
            attribute("kilograms", .doubleAttributeType),
            attribute("note", .stringAttributeType, optional: true),
            attribute("createdAt", .dateAttributeType),
            attribute("source", .stringAttributeType, default: "manual"),
            attribute("externalID", .stringAttributeType, optional: true),
        ]
        return entity
    }

    private static func hikeEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "Hike"
        entity.managedObjectClassName = "Hike"
        entity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("date", .dateAttributeType, indexed: true),
            attribute("title", .stringAttributeType, default: "徒步"),
            attribute("distanceKilometers", .doubleAttributeType),
            attribute("elevationGainMeters", .doubleAttributeType),
            attribute("durationMinutes", .doubleAttributeType),
            attribute("note", .stringAttributeType, optional: true),
            attribute("createdAt", .dateAttributeType),
            attribute("source", .stringAttributeType, default: "manual"),
            attribute("externalID", .stringAttributeType, optional: true),
        ]
        return entity
    }

    private static func profileEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "UserProfile"
        entity.managedObjectClassName = "UserProfile"
        entity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType, default: ""),
            attribute("sex", .stringAttributeType, default: "female"),
            attribute("birthDate", .dateAttributeType),
            attribute("heightCentimeters", .doubleAttributeType, default: 0.0),
            attribute("startWeightKilograms", .doubleAttributeType, default: 0.0),
            attribute("activityLevel", .stringAttributeType, default: "light"),
            attribute("goalType", .stringAttributeType, default: "lose"),
            attribute("targetWeightKilograms", .doubleAttributeType, default: 0.0),
            attribute("dailyCalorieOverride", .doubleAttributeType, default: 0.0),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
        ]
        return entity
    }

    private static func foodEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "FoodEntry"
        entity.managedObjectClassName = "FoodEntry"
        entity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("date", .dateAttributeType, indexed: true),
            attribute("name", .stringAttributeType, default: ""),
            attribute("mealType", .stringAttributeType, default: "snack"),
            attribute("grams", .doubleAttributeType, default: 0.0),
            attribute("kcal", .doubleAttributeType, default: 0.0),
            attribute("protein", .doubleAttributeType, default: 0.0),
            attribute("carbs", .doubleAttributeType, default: 0.0),
            attribute("fat", .doubleAttributeType, default: 0.0),
            attribute("foodID", .stringAttributeType, optional: true),
            attribute("imageURL", .stringAttributeType, optional: true),
            attribute("note", .stringAttributeType, optional: true),
            attribute("createdAt", .dateAttributeType),
            attribute("source", .stringAttributeType, default: "manual"),
            attribute("externalID", .stringAttributeType, optional: true),
        ]
        return entity
    }

    private static func activityEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "ActivityEntry"
        entity.managedObjectClassName = "ActivityEntry"
        entity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("date", .dateAttributeType, indexed: true),
            attribute("kind", .stringAttributeType, default: "hiking"),
            attribute("title", .stringAttributeType, default: ""),
            attribute("durationMinutes", .doubleAttributeType, default: 0.0),
            attribute("distanceKilometers", .doubleAttributeType, default: 0.0),
            attribute("elevationGainMeters", .doubleAttributeType, default: 0.0),
            attribute("kcal", .doubleAttributeType, default: 0.0),
            attribute("note", .stringAttributeType, optional: true),
            attribute("createdAt", .dateAttributeType),
            attribute("source", .stringAttributeType, default: "manual"),
            attribute("externalID", .stringAttributeType, optional: true),
            attribute("averageHeartRate", .doubleAttributeType, default: 0.0),
            attribute("maximumHeartRate", .doubleAttributeType, default: 0.0),
        ]
        return entity
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = false,
        indexed: Bool = false,
        default defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        attribute.isIndexed = indexed
        attribute.defaultValue = defaultValue
        return attribute
    }
}
