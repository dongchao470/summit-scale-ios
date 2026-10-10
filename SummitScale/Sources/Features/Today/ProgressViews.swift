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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .foregroundColor(isOver ? Theme.warning : .primary)
                Text("/ \(Fmt.grams(target)) g")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.18))
                    Capsule()
                        .fill(isOver ? Theme.warning : color)
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
            MacroBar(title: "蛋白质", grams: protein, target: budget.macros.protein, color: Theme.protein)
            MacroBar(title: "碳水", grams: carbs, target: budget.macros.carbs, color: Theme.carbs)
            MacroBar(title: "脂肪", grams: fat, target: budget.macros.fat, color: Theme.fat)
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
                VStack(alignment: .trailing, spacing: 1) {
                    Text(progress >= 1 ? "已达标" : "还差 \(Fmt.kg(abs(remaining))) kg")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(progress >= 1 ? Theme.success : Theme.accent)
                    Text("目标 \(Fmt.kg(target)) kg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.accent.opacity(0.16))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent.opacity(0.75), Theme.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geometry.size.width * progress))
                    // 起点与终点标注，让进度有个参照。
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 8, height: 8)
                        .offset(x: max(0, geometry.size.width * progress) - 4)
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
