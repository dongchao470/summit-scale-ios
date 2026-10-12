import Foundation

// MARK: - 基础枚举

/// 生理性别。只影响基础代谢公式里的常数项，不做其他用途，也不会显示在别处。
enum Sex: String, CaseIterable, Identifiable {
    case male
    case female

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male: return "男"
        case .female: return "女"
        }
    }
}

/// 日常活动量，用来把基础代谢放大成一天的总消耗。
enum ActivityLevel: String, CaseIterable, Identifiable {
    case sedentary
    case light
    case moderate
    case active
    case veryActive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sedentary: return "久坐"
        case .light: return "轻度活动"
        case .moderate: return "中度活动"
        case .active: return "高度活动"
        case .veryActive: return "极高强度"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: return "日常上班坐着、不专门运动。想单独记录爬山/健身等运动就选这档，避免重复计算"
        case .light: return "每周运动 1～3 次，已算进消耗，不再单独记运动"
        case .moderate: return "每周运动 3～5 次，已算进消耗，不再单独记运动"
        case .active: return "每周运动 6～7 次，已算进消耗，不再单独记运动"
        case .veryActive: return "体力工作或每天高强度训练，已算进消耗，不再单独记运动"
        }
    }

    /// 活动系数。
    var factor: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }
}

/// 目标方向。
enum GoalType: String, CaseIterable, Identifiable {
    case lose
    case maintain
    case gain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lose: return "减重"
        case .maintain: return "保持"
        case .gain: return "增重"
        }
    }

    var detail: String {
        switch self {
        case .lose: return "每天留出约 500 千卡缺口"
        case .maintain: return "吃到刚好，不掉也不涨"
        case .gain: return "每天多吃约 300 千卡"
        }
    }
}

/// 一餐的分类。
enum MealType: String, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: return "早餐"
        case .lunch: return "午餐"
        case .dinner: return "晚餐"
        case .snack: return "加餐"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon"
        case .snack: return "cup.and.saucer"
        }
    }

    var sortIndex: Int {
        switch self {
        case .breakfast: return 0
        case .lunch: return 1
        case .dinner: return 2
        case .snack: return 3
        }
    }
}

/// 运动种类，附带代谢当量（MET）。
enum ActivityKind: String, CaseIterable, Identifiable {
    case hiking
    case walking
    case running
    case cycling
    case swimming
    case strength
    case yoga
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hiking: return "爬山"
        case .walking: return "走路"
        case .running: return "跑步"
        case .cycling: return "骑行"
        case .swimming: return "游泳"
        case .strength: return "力量训练"
        case .yoga: return "瑜伽"
        case .other: return "其他"
        }
    }

    var symbol: String {
        switch self {
        case .hiking: return "figure.hiking"
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .strength: return "figure.strengthtraining.traditional"
        case .yoga: return "figure.yoga"
        case .other: return "figure.mixed.cardio"
        }
    }

    /// 代谢当量，粗略取自体力活动能量消耗汇编的档位。
    var mets: Double {
        switch self {
        case .walking: return 3.5
        case .hiking: return 6.0
        case .running: return 9.8
        case .cycling: return 7.5
        case .swimming: return 6.0
        case .strength: return 5.0
        case .yoga: return 2.5
        case .other: return 4.0
        }
    }

    /// 是否值得让用户填距离与爬升。
    var wantsRoute: Bool {
        switch self {
        case .hiking, .walking, .running, .cycling: return true
        default: return false
        }
    }
}

// MARK: - 换算

/// 热量换算。全是纯函数，不碰任何状态，方便单独验证。
enum CalorieMath {
    /// 1 公斤脂肪约等于 7700 千卡。
    static let kcalPerKilogramFat: Double = 7700

    /// 1 千卡 = 4.184 千焦，国内食品标签多用千焦。
    static func kilojoules(fromKilocalories kcal: Double) -> Double {
        kcal * 4.184
    }

    static func kilocalories(fromKilojoules kilojoules: Double) -> Double {
        kilojoules / 4.184
    }

    /// Mifflin-St Jeor 基础代谢率。
    static func bmr(sex: Sex, kilograms: Double, heightCentimeters: Double, ageYears: Int) -> Double {
        let base = 10 * kilograms + 6.25 * heightCentimeters - 5 * Double(ageYears)
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        }
    }

    /// 一天总消耗 = 基础代谢 × 活动系数。
    static func tdee(bmr: Double, level: ActivityLevel) -> Double {
        bmr * level.factor
    }

    /// 目标摄入量。减重按每天 500 千卡缺口，但不低于安全下限。
    static func intakeTarget(tdee: Double, goal: GoalType, sex: Sex) -> Double {
        switch goal {
        case .lose:
            let floor: Double = (sex == .male) ? 1500 : 1200
            return max(floor, tdee - 500)
        case .maintain:
            return tdee
        case .gain:
            return tdee + 300
        }
    }

    /// 三大营养素目标。
    ///
    /// 先按体重定蛋白（减脂期要保住肌肉，给得高一点），再按比例划脂肪，
    /// 剩下的热量全给碳水 —— 比死抠固定百分比更符合实际吃喝。
    /// 蛋白额外加一道上限：不超过总热量的 35%，避免极端体重下算出离谱数字。
    static func macroTargets(intakeKcal: Double, kilograms: Double, goal: GoalType) -> MacroTargets {
        guard intakeKcal > 0, kilograms > 0 else {
            return MacroTargets(protein: 0, carbs: 0, fat: 0)
        }
        let proteinPerKilogram: Double
        switch goal {
        case .lose: proteinPerKilogram = 1.8
        case .maintain: proteinPerKilogram = 1.5
        case .gain: proteinPerKilogram = 1.6
        }
        let protein = min(kilograms * proteinPerKilogram, intakeKcal * 0.35 / 4)
        let fat = intakeKcal * 0.27 / 9
        let carbs = max(0, (intakeKcal - protein * 4 - fat * 9) / 4)
        return MacroTargets(protein: protein, carbs: carbs, fat: fat)
    }

    /// 运动消耗：MET × 3.5 × 体重(kg) / 200 × 分钟数。
    static func burn(kind: ActivityKind, minutes: Double, kilograms: Double) -> Double {
        guard minutes > 0, kilograms > 0 else { return 0 }
        return kind.mets * 3.5 * kilograms / 200 * minutes
    }

    /// 按生日算周岁。
    static func ageYears(birthDate: Date, now: Date = Date()) -> Int {
        let components = Calendar.current.dateComponents([.year], from: birthDate, to: now)
        return max(0, components.year ?? 0)
    }

    /// 用掉秤数反推实际日均热量差。仅供参考，不做医疗建议。
    static func observedDailyDeficit(kilogramsLost: Double, days: Int) -> Double? {
        guard days > 0 else { return nil }
        return kilogramsLost * kcalPerKilogramFat / Double(days)
    }
}

// MARK: - 预算与流水

/// 一天三大营养素的目标量，单位克。
struct MacroTargets: Equatable {
    let protein: Double
    let carbs: Double
    let fat: Double
}

/// 三大营养素的累计摄入。
struct MacroIntake: Equatable {
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    /// 相对目标的完成度，已夹在 0～1。
    func progress(_ value: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, value / target))
    }
}

/// 一天的热量预算快照。
struct CalorieBudget: Equatable {
    let bmr: Double
    let tdee: Double
    let intakeTarget: Double
    let goal: GoalType
    /// 三大营养素目标。
    let macros: MacroTargets

    /// 相对总消耗的日均热量差，正数表示缺口。
    var dailyDeficit: Double { tdee - intakeTarget }

    /// 按这个缺口，一周大约的体重变化，正数表示掉秤。
    var estimatedWeeklyChange: Double {
        dailyDeficit * 7 / CalorieMath.kcalPerKilogramFat
    }

    /// 距离目标体重还需要几周；方向不对或已经达标时返回 nil。
    func estimatedWeeks(currentKilograms: Double, targetKilograms: Double) -> Double? {
        guard abs(estimatedWeeklyChange) > 0.001 else { return nil }
        let weeks = (currentKilograms - targetKilograms) / estimatedWeeklyChange
        return weeks > 0 ? weeks : nil
    }

    /// 从档案的原始数值算预算，`overrideKcal` 有值时以它为准。
    static func make(
        sex: Sex,
        kilograms: Double,
        heightCentimeters: Double,
        ageYears: Int,
        level: ActivityLevel,
        goal: GoalType,
        overrideKcal: Double? = nil
    ) -> CalorieBudget {
        let bmr = CalorieMath.bmr(
            sex: sex,
            kilograms: kilograms,
            heightCentimeters: heightCentimeters,
            ageYears: ageYears
        )
        let tdee = CalorieMath.tdee(bmr: bmr, level: level)
        let target = overrideKcal ?? CalorieMath.intakeTarget(tdee: tdee, goal: goal, sex: sex)
        let macros = CalorieMath.macroTargets(intakeKcal: target, kilograms: kilograms, goal: goal)
        return CalorieBudget(
            bmr: bmr,
            tdee: tdee,
            intakeTarget: target,
            goal: goal,
            macros: macros
        )
    }
}

/// 某一天的热量流水。
struct DayLedger: Equatable {
    let budget: CalorieBudget
    let intakeKcal: Double
    let burnKcal: Double

    /// 还能吃多少。运动消耗可以加回来。
    var remainingKcal: Double { budget.intakeTarget + burnKcal - intakeKcal }

    /// 净摄入 = 吃进去的 − 运动掉的。
    var netKcal: Double { intakeKcal - burnKcal }

    /// 相对总消耗的真实缺口，正数表示今天确实在缺。
    var actualDeficit: Double { budget.tdee + burnKcal - intakeKcal }

    /// 用于画环的完成度，限制在 0～1。
    var progress: Double {
        guard budget.intakeTarget > 0 else { return 0 }
        return min(1, max(0, netKcal / budget.intakeTarget))
    }

    /// 是否已经超出预算。
    var isOverBudget: Bool { remainingKcal < 0 }
}
