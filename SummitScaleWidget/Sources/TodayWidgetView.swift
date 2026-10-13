import SwiftUI
import WidgetKit

/// 小组件视图（方案 B · 双色双条）。
///
/// 顶部大数字先给答案（还可吃），下面两条进度条分开回答「吃了多少 / 动了多少」：
/// 橙色 = 摄入（相对目标），绿色 = 活动消耗（以 500kcal 为满格）。
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
                    .fill(color)
                    .frame(width: max(0, geo.size.width * progress))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - 小号：大数字 + 双条

private struct SmallLayout: View {
    let snapshot: WidgetSnapshot

    private var intakeProgress: Double {
        guard snapshot.targetKcal > 0 else { return 0 }
        let v = snapshot.intakeKcal / snapshot.targetKcal
        guard v.isFinite else { return 0 }
        return min(max(v, 0), 1)
    }

    private var burnProgress: Double {
        let v = snapshot.burnKcal / 500
        guard v.isFinite else { return 0 }
        return min(max(v, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.isOverBudget ? "已超出" : "还可吃")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.secondaryText)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Fmt.kcal(abs(snapshot.remainingKcal)))
                    .font(Theme.number(34, weight: .bold))
                    .foregroundColor(snapshot.isOverBudget ? Theme.warning : Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("kcal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
            }

            Bar(progress: intakeProgress, color: Color(uiColor: .systemOrange))
            HStack(spacing: 4) {
                Text("摄入 \(Fmt.kcal(snapshot.intakeKcal))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text("\(Int((intakeProgress * 100).rounded()))%")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Theme.secondaryText)
            }

            Bar(progress: burnProgress, color: Theme.success)
            HStack(spacing: 4) {
                Text("消耗 \(Fmt.kcal(snapshot.burnKcal)) · \(Int(snapshot.steps))步")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text("\(Int((burnProgress * 100).rounded()))%")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - 中号：左侧大数字双条 + 右侧明细

private struct MediumLayout: View {
    let snapshot: WidgetSnapshot

    private var intakeProgress: Double {
        guard snapshot.targetKcal > 0 else { return 0 }
        let v = snapshot.intakeKcal / snapshot.targetKcal
        guard v.isFinite else { return 0 }
        return min(max(v, 0), 1)
    }

    private var burnProgress: Double {
        let v = snapshot.burnKcal / 500
        guard v.isFinite else { return 0 }
        return min(max(v, 0), 1)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.isOverBudget ? "已超出" : "还可吃")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.kcal(abs(snapshot.remainingKcal)))
                        .font(Theme.number(34, weight: .bold))
                        .foregroundColor(snapshot.isOverBudget ? Theme.warning : Theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("kcal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                }
                Bar(progress: intakeProgress, color: Color(uiColor: .systemOrange))
                Bar(progress: burnProgress, color: Theme.success)
            }
            .frame(width: 150, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                statRow(label: "摄入", value: Fmt.kcal(snapshot.intakeKcal))
                Spacer(minLength: 0)
                statRow(label: "目标", value: Fmt.kcal(snapshot.targetKcal))
                Spacer(minLength: 0)
                statRow(label: "消耗", value: Fmt.kcal(snapshot.burnKcal))
                Spacer(minLength: 0)
                statRow(label: "步数", value: "\(Int(snapshot.steps))")
            }
            .frame(maxHeight: .infinity)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.tertiaryText)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
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
