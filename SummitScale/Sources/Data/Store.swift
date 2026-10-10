import CoreData
import Foundation

/// 视图层用的写入出口，把上下文样板收在一处。
extension Persistence {
    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            NSLog("[SummitScale] 保存失败: \(error)")
        }
    }

    @discardableResult
    func addWeight(kilograms: Double, date: Date, note: String?) -> WeightEntry {
        let entry = WeightEntry(context: container.viewContext)
        entry.id = UUID()
        entry.date = date
        entry.kilograms = kilograms
        entry.note = (note?.isEmpty ?? true) ? nil : note
        entry.createdAt = Date()
        entry.source = "manual"
        entry.externalID = nil
        save()
        return entry
    }

    @discardableResult
    func addHike(
        title: String,
        date: Date,
        distanceKilometers: Double,
        elevationGainMeters: Double,
        durationMinutes: Double,
        note: String?
    ) -> Hike {
        let hike = Hike(context: container.viewContext)
        hike.id = UUID()
        hike.date = date
        hike.title = title.isEmpty ? "徒步" : title
        hike.distanceKilometers = distanceKilometers
        hike.elevationGainMeters = elevationGainMeters
        hike.durationMinutes = durationMinutes
        hike.note = (note?.isEmpty ?? true) ? nil : note
        hike.createdAt = Date()
        hike.source = "manual"
        hike.externalID = nil
        save()
        return hike
    }

    func delete(_ object: NSManagedObject) {
        container.viewContext.delete(object)
        save()
    }
}
