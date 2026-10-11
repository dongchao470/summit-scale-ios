import CoreData
import Foundation

/// 视图层用的写入出口，把上下文样板收在一处。
extension Persistence {

    // MARK: - 通用

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

    func delete(_ object: NSManagedObject) {
        container.viewContext.delete(object)
        save()
    }

    // MARK: - 体重

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

    // MARK: - 爬山（v0.1 兼容）

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

    // MARK: - 档案

    func currentProfile() -> UserProfile? {
        let request = UserProfile.fetchRequest()
        request.fetchLimit = 1
        return (try? container.viewContext.fetch(request))?.first
    }

    /// 取档案；第一次启动时建一个空壳，等引导流程填。
    @discardableResult
    func ensureProfile() -> UserProfile {
        if let existing = currentProfile() { return existing }

        let profile = UserProfile(context: container.viewContext)
        profile.id = UUID()
        profile.name = ""
        profile.sex = Sex.female.rawValue
        profile.birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
        profile.heightCentimeters = 0
        profile.startWeightKilograms = 0
        profile.activityLevel = ActivityLevel.light.rawValue
        profile.goalType = GoalType.lose.rawValue
        profile.targetWeightKilograms = 0
        profile.dailyCalorieOverride = 0
        profile.createdAt = Date()
        profile.updatedAt = Date()
        save()
        return profile
    }

    func updateProfile(
        _ profile: UserProfile,
        name: String,
        sex: Sex,
        birthDate: Date,
        heightCentimeters: Double,
        startWeightKilograms: Double,
        activity: ActivityLevel,
        goal: GoalType,
        targetWeightKilograms: Double,
        dailyCalorieOverride: Double
    ) {
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.sex = sex.rawValue
        profile.birthDate = birthDate
        profile.heightCentimeters = heightCentimeters
        profile.startWeightKilograms = startWeightKilograms
        profile.activityLevel = activity.rawValue
        profile.goalType = goal.rawValue
        profile.targetWeightKilograms = targetWeightKilograms
        profile.dailyCalorieOverride = dailyCalorieOverride
        profile.updatedAt = Date()
        save()
    }

    /// 按档案 + 当前体重算热量预算；关键数值缺失时返回 nil。
    func calorieBudget(for profile: UserProfile, currentKilograms: Double?) -> CalorieBudget? {
        let kilograms = currentKilograms ?? profile.startWeightKilograms
        guard profile.heightCentimeters > 0, kilograms > 0 else { return nil }
        let override = profile.dailyCalorieOverride > 0 ? profile.dailyCalorieOverride : nil
        return CalorieBudget.make(
            sex: profile.sexValue,
            kilograms: kilograms,
            heightCentimeters: profile.heightCentimeters,
            ageYears: CalorieMath.ageYears(birthDate: profile.birthDate),
            level: profile.activityValue,
            goal: profile.goalValue,
            overrideKcal: override
        )
    }

    // MARK: - 饮食

    @discardableResult
    func addFood(
        name: String,
        meal: MealType,
        grams: Double,
        kcal: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        foodID: String?,
        note: String?,
        date: Date,
        imageURL: String? = nil,
        source: String = FoodSource.manual,
        externalID: String? = nil
    ) -> FoodEntry {
        let entry = FoodEntry(context: container.viewContext)
        entry.id = UUID()
        entry.date = date
        entry.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.mealType = meal.rawValue
        entry.grams = grams
        entry.kcal = kcal
        entry.protein = protein
        entry.carbs = carbs
        entry.fat = fat
        entry.foodID = foodID
        entry.imageURL = imageURL
        entry.note = (note?.isEmpty ?? true) ? nil : note
        entry.createdAt = Date()
        entry.source = source
        entry.externalID = externalID
        save()
        return entry
    }

    /// 就地改一条饮食记录。
    ///
    /// 只动传进来的这几项，配图、来源和外部 id 原样保留，
    /// 免得编辑一次把图和去重信息弄丢。
    func updateFood(
        _ entry: FoodEntry,
        name: String,
        meal: MealType,
        grams: Double,
        kcal: Double,
        date: Date
    ) {
        entry.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.mealType = meal.rawValue
        entry.grams = grams
        entry.kcal = kcal
        entry.date = date
        save()
    }

    // MARK: - 活动

    @discardableResult
    func addActivity(
        kind: ActivityKind,
        title: String,
        date: Date,
        durationMinutes: Double,
        distanceKilometers: Double,
        elevationGainMeters: Double,
        kcal: Double,
        note: String?
    ) -> ActivityEntry {
        let entry = ActivityEntry(context: container.viewContext)
        entry.id = UUID()
        entry.date = date
        entry.kind = kind.rawValue
        entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.durationMinutes = durationMinutes
        entry.distanceKilometers = distanceKilometers
        entry.elevationGainMeters = elevationGainMeters
        entry.kcal = kcal
        entry.note = (note?.isEmpty ?? true) ? nil : note
        entry.createdAt = Date()
        entry.source = "manual"
        entry.externalID = nil
        save()
        return entry
    }

    // MARK: - 一次性迁移

    /// 把 v0.1 的 Hike 记录搬进统一的活动表，搬完删掉旧的，避免两边都显示。
    func migrateLegacyHikesIfNeeded() {
        let context = container.viewContext
        let request = Hike.fetchRequest()
        guard let legacy = try? context.fetch(request), !legacy.isEmpty else { return }

        for hike in legacy {
            let activity = ActivityEntry(context: context)
            activity.id = hike.id
            activity.date = hike.date
            activity.kind = ActivityKind.hiking.rawValue
            activity.title = hike.title
            activity.durationMinutes = hike.durationMinutes
            activity.distanceKilometers = hike.distanceKilometers
            activity.elevationGainMeters = hike.elevationGainMeters
            activity.kcal = 0
            activity.note = hike.note
            activity.createdAt = hike.createdAt
            activity.source = hike.source
            activity.externalID = hike.externalID
            context.delete(hike)
        }
        save()
        NSLog("[SummitScale] 已迁移 \(legacy.count) 条旧爬山记录")
    }
}
