import SwiftUI

/// 小统计块：标题 + 大数字 + 单位。首页与趋势页共用。
struct StatTile: View {
    let title: String
    let value: String
    let unit: String
    var tint: Color = .primary
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let symbol = symbol {
                    Image(systemName: symbol)
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundColor(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.number(19))
                    .foregroundColor(tint)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value) \(unit)")
    }
}

/// 一条营养素进度：名称、已吃/目标、进度条。
struct MacroBar: View {
    let title: String
    let grams: Double
    let target: Double
    let color: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, grams / target))
    }

    private var isOver: Bool {
        target > 0 && grams > target * 1.02
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer(minLength: 4)
                Text("\(Fmt.grams(grams))")
                    .font(Theme.number(14, weight: .semibold))
                    .foregroundColor(isOver ? Theme.accent : .primary)
                Text("/ \(Fmt.grams(target)) g")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.track)
                    Capsule()
                        .fill(isOver ? Theme.accent : color)
                        .frame(width: max(0, geometry.size.width * progress))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，已摄入 \(Fmt.grams(grams)) 克，目标 \(Fmt.grams(target)) 克")
    }
}

/// 三大营养素进度条组。
struct MacroPanel: View {
    let protein: Double
    let carbs: Double
    let fat: Double
    let budget: CalorieBudget

    var body: some View {
        VStack(spacing: 12) {
            // 三条统一走强调色，靠左侧名称区分，不再红橙蓝三色同屏；超支由 MacroBar 内部转红。
            MacroBar(title: "蛋白质", grams: protein, target: budget.macros.protein, color: Theme.accent)
            MacroBar(title: "碳水", grams: carbs, target: budget.macros.carbs, color: Theme.accent)
            MacroBar(title: "脂肪", grams: fat, target: budget.macros.fat, color: Theme.accent)
        }
    }
}

/// 体重距目标的进度条：起点体重 → 目标体重，当前位置按比例落在中间。
struct GoalProgressBar: View {
    let current: Double
    let start: Double
    let target: Double

    private var remaining: Double { current - target }

    /// 已完成的行程比例。
    private var progress: Double {
        let total = start - target
        guard abs(total) > 0.05 else { return 1 }
        let done = (start - current) / total
        return min(1, max(0, done))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.kg(current))
                    .font(Theme.number(30))
                    .foregroundColor(.primary)
                Text("kg")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                // 「目标 XX kg」在下面那排标尺已经印了一次，这里不再重复，只留还差多少。
                Text(progress >= 1 ? "已达标" : "还差 \(Fmt.kg(abs(remaining))) kg")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.accent)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 轨道走系统填充灰，只有进度本身带色，这是 iOS 进度条的标准画法。
                    Capsule()
                        .fill(Theme.track)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(0, geometry.size.width * progress))
                }
            }
            .frame(height: 8)

            HStack {
                Text("起点 \(Fmt.kg(start)) kg")
                Spacer()
                Text("目标 \(Fmt.kg(target)) kg")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前体重 \(Fmt.kg(current)) 公斤，目标 \(Fmt.kg(target)) 公斤，已完成 \(Int(progress * 100))%")
    }
}
