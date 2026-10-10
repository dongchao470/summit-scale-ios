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

        container.loadPersistentStores { description, error in
            guard let error = error as NSError? else { return }
            NSLog("[SummitScale] store 加载失败: \(error), \(error.userInfo)")

            // 自愈：本地存储损坏时删掉重建，别让用户看到启动即崩。
            if let url = description.url {
                let fm = FileManager.default
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
        model.entities = [weightEntity(), hikeEntity()]
        return model
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
