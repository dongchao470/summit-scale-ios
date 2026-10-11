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
    ///
    /// 入账的同时打上「这天已记过」的标记：手动记过的套餐，到点不该再被自动补一遍。
    ///
    /// 这里也写 `autoFillKey`（以前是 nil），有两个原因：
    /// 一是列表要能看出这几条属于同一份套餐、折叠成一行；
    /// 二是 `hasAutoFilled` 本来就查这个键，写上之后「先一键加、后到点自动补」
    /// 就不会在同一天重复写第二份。
    @discardableResult
    func applyTemplate(
        _ template: MealTemplate,
        to date: Date,
        meal: MealType? = nil,
        portions: Double = 1
    ) -> Int {
        let written = writeItems(
            template.items,
            templateName: template.name,
            meal: meal ?? template.meal,
            date: date,
            portions: portions,
            externalID: Self.autoFillKey(template: template, on: date)
        )
        if written > 0 {
            markAutoFilled(template: template, on: date)
        }
        return written
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
            entry.source = FoodSource.template
            entry.externalID = externalID
            written += 1
        }
        save()
        return written
    }

    // MARK: - 到点自动填

    /// 套餐入账去重用的日期戳。
    private static func dayStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    /// 自动补录写进条目的 externalID，方便排查「这条是哪次补的」。
    static func autoFillKey(template: MealTemplate, on date: Date) -> String {
        "template:\(template.id.uuidString):\(Self.dayStamp(date))"
    }

    /// 「这个套餐这天已经入过账」的独立标记。
    ///
    /// 单独记一份，而不是只靠条目里的 externalID：用户自己手动记过之后，
    /// 或者把自动补的那几条删掉之后，都不该在下次启动时被再补一遍。
    private static func autoFillFlagKey(template: MealTemplate, on date: Date) -> String {
        "autofill.\(template.id.uuidString).\(Self.dayStamp(date))"
    }

    /// 这个套餐当天是不是已经记过了，手动一键加也算。
    func hasAutoFilled(template: MealTemplate, on date: Date) -> Bool {
        if UserDefaults.standard.bool(forKey: Self.autoFillFlagKey(template: template, on: date)) {
            return true
        }
        // 兼容 0.3.1 之前只写了 externalID 的旧数据。
        let request = FoodEntry.fetchRequest()
        request.predicate = NSPredicate(
            format: "externalID == %@",
            Self.autoFillKey(template: template, on: date)
        )
        request.fetchLimit = 1
        return ((try? container.viewContext.fetch(request))?.isEmpty == false)
    }

    /// 记下「这个套餐这天已经入过账」。
    private func markAutoFilled(template: MealTemplate, on date: Date) {
        UserDefaults.standard.set(true, forKey: Self.autoFillFlagKey(template: template, on: date))
    }

    /// 到点了、但还没补过的套餐——**只算不写**。
    ///
    /// iOS 后台不给普通 App 随意跑代码，所以「到点自动入账」只能做成
    /// 「你打开 App 时补上」。但补之前必须先问一句：点通知只会把 App 拉到前台，
    /// 系统不会告诉我们用户到底想不想记。所以这里只把候选挑出来交给界面，
    /// 等用户点头再调 `applyAutoFills`。
    func pendingAutoFills(now: Date = Date()) -> [MealTemplate] {
        var pending: [MealTemplate] = []
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

            pending.append(template)
        }
        return pending
    }

    /// 用户点头之后，才把挑出来的套餐补进今天。返回补上的套餐名。
    @discardableResult
    func applyAutoFills(_ templates: [MealTemplate], now: Date = Date()) -> [String] {
        var filled: [String] = []

        for template in templates {
            guard !template.items.isEmpty else { continue }
            // 确认弹窗挂着的这段时间里可能已经手动记过了，写之前再查一遍。
            guard !hasAutoFilled(template: template, on: now) else { continue }

            writeItems(
                template.items,
                templateName: template.name,
                meal: template.meal,
                date: now,
                portions: 1,
                externalID: Self.autoFillKey(template: template, on: now)
            )
            markAutoFilled(template: template, on: now)
            filled.append(template.name)
        }
        return filled
    }

    /// 用户说「今天不用」：记下这天已经处理过，免得每次回前台都再问一遍。
    func skipAutoFills(_ templates: [MealTemplate], now: Date = Date()) {
        for template in templates {
            markAutoFilled(template: template, on: now)
        }
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
