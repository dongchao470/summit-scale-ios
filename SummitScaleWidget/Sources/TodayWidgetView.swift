import SwiftUI
import WidgetKit

/// 小组件视图（方案 B · 双色双条，严格按 v2.html 设计稿渲染）。
///
/// 小号：标题 → 40pt 大数字 → 两条「圆点 + 进度条 + 百分比」行。
/// 中号：左侧大数字块（数字 / kcal / 橙色「还可吃」），右侧三行
///       「圆点 + 进度条 + 绝对值」（摄入 / 消耗 / 步数，蓝色步数行）。
/// 不用 GeometryReader 排整体，只在进度条内部用它算填充宽度（固定 6pt 高，安全）。
struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.isToday {
                switch family {
                case .systemMedium:
                    MediumLayout(snapshot: snapshot)
                default:
                    SmallLayout(snapshot: snapshot)
                }
            } else {
                EmptyLayout()
            }
        }
        .widgetCanvas()
        .onAppear { WidgetDiagnostics.recordViewRendered() }
    }
}

// MARK: - 画布

private extension View {
    /// iOS 17 起 widget 必须自己声明容器背景；iOS 16 保留系统默认材质。
    @ViewBuilder
    func widgetCanvas() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { Theme.cardBackground }
        } else {
            self
        }
    }
}

// MARK: - 进度条

private struct Bar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.track)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.85), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * progress))
            }
        }
        .frame(height: 6)
    }
}

/// 设计稿的进度行：圆点 6pt + 弹性条 + 右侧定宽数字（稿 .b-pct width:30）。
private struct DotBarRow: View {
    let dot: Color
    let progress: Double
    let trailing: String
    /// 可选的行首标识文字（设计稿上没有，用户加要的）。
    var label: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
            if let label {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
            }
            Bar(progress: progress, color: dot)
            Text(trailing)
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(Theme.secondaryText)
                .frame(width: 34, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - 摄入 / 消耗 / 步数 进度

private enum WidgetProgress {
    static func intake(_ s: WidgetSnapshot) -> Double {
        guard s.targetKcal > 0 else { return 0 }
        let v = s.intakeKcal / s.targetKcal
        guard v.isFinite else { return 0 }
        return min(max(v, 0), 1)
    }

    static func burn(_ s: WidgetSnapshot) -> Double {
        let v = s.burnKcal / 500
        guard v.isFinite else { return 0 }
        return min(max(v, 0), 1)
    }

    static func steps(_ s: WidgetSnapshot) -> Double {
        let v = s.steps / 10_000
        guard v.isFinite else { return 0 }
        return min(max(v, 0), 1)
    }

    static func pct(_ p: Double) -> String {
        "\(Int((p * 100).rounded()))%"
    }
}

private let barOrange = Color(red: 1.0, green: 0.624, blue: 0.263)   // #FF9F43
private let barGreen = Color(red: 0.204, green: 0.827, blue: 0.600)   // #34D399
private let barBlue = Color(red: 0.376, green: 0.647, blue: 0.980)    // #60A5FA

/// 更新时间用的 "HH:mm"（Fmt.stamp 带日期，小组件里太占地方）。
private let updateTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.dateFormat = "HH:mm"
    return f
}()

/// 一行小字「更新 13:09」。
private func updatedLabel(_ snapshot: WidgetSnapshot) -> Text {
    Text("更新 \(updateTimeFormatter.string(from: snapshot.savedAt))")
        .font(.system(size: 9, weight: .medium))
        .foregroundColor(Theme.secondaryText)
}

// MARK: - 小号：标题 + 40pt 大数字 + 双进度行

private struct SmallLayout: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.isOverBudget ? "已超出" : "还可吃")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                updatedLabel(snapshot)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Fmt.kcal(abs(snapshot.remainingKcal)))
                    .font(Theme.number(40, weight: .bold))
                    .foregroundColor(snapshot.isOverBudget ? Theme.warning : Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("kcal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 7) {
                DotBarRow(
                    dot: barOrange,
                    progress: WidgetProgress.intake(snapshot),
                    trailing: WidgetProgress.pct(WidgetProgress.intake(snapshot)),
                    label: "摄入"
                )
                DotBarRow(
                    dot: barGreen,
                    progress: WidgetProgress.burn(snapshot),
                    trailing: WidgetProgress.pct(WidgetProgress.burn(snapshot)),
                    label: "消耗"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

// MARK: - 中号：左侧大数字块 + 右侧三行进度（摄入 / 消耗 / 步数）

private struct MediumLayout: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.kcal(abs(snapshot.remainingKcal)))
                        .font(Theme.number(38, weight: .bold))
                        .foregroundColor(snapshot.isOverBudget ? Theme.warning : Theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("kcal")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                }
                Text(snapshot.isOverBudget ? "已超出" : "还可吃")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(barOrange)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 9) {
                DotBarRow(
                    dot: barOrange,
                    progress: WidgetProgress.intake(snapshot),
                    trailing: Fmt.kcal(snapshot.intakeKcal)
                )
                DotBarRow(
                    dot: barGreen,
                    progress: WidgetProgress.burn(snapshot),
                    trailing: Fmt.kcal(snapshot.burnKcal)
                )
                DotBarRow(
                    dot: barBlue,
                    progress: WidgetProgress.steps(snapshot),
                    trailing: "\(Int(snapshot.steps))"
                )
                updatedLabel(snapshot)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 20)
    }
}

// MARK: - 空态

private struct EmptyLayout: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.track)
            Text("打开「山与秤」同步")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
