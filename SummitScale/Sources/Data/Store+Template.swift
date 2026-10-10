import CoreData
import Foundation

/// 套餐的读写与入账。
extension Persistence {

    // MARK: - 查询

    func allTemplates() -> [MealTemplate] {
        let request = MealTemplate.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortIndex", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
        ]
        return (try? container.viewContext.fetch(request)) ?? []
    }

    func templates(for meal: MealType) -> [MealTemplate] {
        allTemplates().filter { $0.meal == meal }
    }

    // MARK: - 增删改

    @discardableResult
    func addTemplate(name: String, meal: MealType, items: [TemplateItem]) -> MealTemplate {
        let template = MealTemplate(context: container.viewContext)
        template.id = UUID()
        template.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        template.mealType = meal.rawValue
        template.items = items
        template.autoFillEnabled = false
        template.autoFillHour = Int16(meal.templateDefaultHour)
        template.autoFillMinute = 0
        template.sortIndex = Int16(allTemplates().count)
        template.createdAt = Date()
        template.updatedAt = Date()
        save()
        return template
    }

    func updateTemplate(_ template: MealTemplate, name: String, meal: MealType, items: [TemplateItem]) {
        template.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        template.mealType = meal.rawValue
        template.items = items
        template.updatedAt = Date()
        save()
    }

    func setAutoFill(_ template: MealTemplate, enabled: Bool, hour: Int, minute: Int) {
        template.autoFillEnabled = enabled
        template.autoFillHour = Int16(hour)
        template.autoFillMinute = Int16(minute)
        template.updatedAt = Date()
        save()
    }

    // MARK: - 入账

    /// 一键入账：把套餐里的东西整份写进某一天。
    /// `portions` 支持 1.5 份这种缩放；返回写入的条数。
    @discardableResult
    func applyTemplate(
        _ template: MealTemplate,
        to date: Date,
        meal: MealType? = nil,
        portions: Double = 1
    ) -> Int {
        writeItems(
            template.items,
            templateName: template.name,
            meal: meal ?? template.meal,
            date: date,
            portions: portions,
            externalID: nil
        )
    }

    @discardableResult
    private func writeItems(
        _ items: [TemplateItem],
        templateName: String,
        meal: MealType,
        date: Date,
        portions: Double,
        externalID: String?
    ) -> Int {
        guard !items.isEmpty else { return 0 }
        var written = 0
        for item in items where item.grams > 0 || item.kcal > 0 {
            let scaled = portions == 1 ? item : item.scaled(by: portions)
            let entry = FoodEntry(context: container.viewContext)
            entry.id = UUID()
            entry.date = date
            entry.name = scaled.name
            entry.mealType = meal.rawValue
            entry.grams = scaled.grams
            entry.kcal = scaled.kcal
            entry.protein = scaled.protein
            entry.carbs = scaled.carbs
            entry.fat = scaled.fat
            entry.foodID = scaled.foodID
            entry.imageURL = scaled.imageURL
            entry.note = "来自套餐「\(templateName)」"
            entry.createdAt = Date()
            entry.source = "template"
            entry.externalID = externalID
            written += 1
        }
        save()
        return written
    }

    // MARK: - 到点自动填

    static func autoFillKey(template: MealTemplate, on date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return "template:\(template.id.uuidString):\(formatter.string(from: date))"
    }

    /// 这个套餐当天是不是已经自动填过了。
    func hasAutoFilled(template: MealTemplate, on date: Date) -> Bool {
        let request = FoodEntry.fetchRequest()
        request.predicate = NSPredicate(
            format: "externalID == %@",
            Self.autoFillKey(template: template, on: date)
        )
        request.fetchLimit = 1
        return ((try? container.viewContext.fetch(request))?.isEmpty == false)
    }

    /// 补填当天已经到点、但还没填过的套餐。
    ///
    /// iOS 后台不给普通 App 随意跑代码，所以这里不靠后台任务：
    /// 打开 App / 从后台回来时各查一次，够用且不会漏。
    /// 返回补上的套餐名，调用方拿去提示用户。
    func runAutoFill(now: Date = Date()) -> [String] {
        var filled: [String] = []
        let calendar = Calendar.current

        for template in allTemplates() where template.autoFillEnabled {
            guard !template.items.isEmpty else { continue }
            guard !hasAutoFilled(template: template, on: now) else { continue }
            guard let trigger = calendar.date(
                bySettingHour: Int(template.autoFillHour),
                minute: Int(template.autoFillMinute),
                second: 0,
                of: now
            ), now >= trigger else { continue }

            writeItems(
                template.items,
                templateName: template.name,
                meal: template.meal,
                date: now,
                portions: 1,
                externalID: Self.autoFillKey(template: template, on: now)
            )
            filled.append(template.name)
        }
        return filled
    }
}

extension MealType {
    /// 新建套餐时给个合理的默认提醒时间。
    var templateDefaultHour: Int {
        switch self {
        case .breakfast: return 7
        case .lunch: return 12
        case .dinner: return 18
        case .snack: return 15
        }
    }
}
