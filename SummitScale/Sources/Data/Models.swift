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

// MARK: - 爬山

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
