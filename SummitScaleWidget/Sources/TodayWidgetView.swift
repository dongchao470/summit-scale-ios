import SwiftUI
import WidgetKit

/// 小组件视图（方案 A · 环）。
///
/// 所有尺寸都按「内容区」算，不靠 GeometryReader 按比例分配：
/// - 小号 158×158，系统四周各留 16pt → 内容区 126×126
/// - 中号 338×158 → 内容区 306×126
/// 每一行给固定行高，余量交给弹性 Spacer 吸收，这样字号放大、数字变长都不会互相挤。
/// （上一版就是按比例分配，元素挤成一团，看起来像错位。）
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

// MARK: - 环

/// 环形进度：底圈 + 渐变弧，中间放主数字。尺寸由外部给定，自己不做任何测量。
private struct Ring: View {
    let snapshot: WidgetSnapshot
    let size: CGFloat
    let lineWidth: CGFloat

    private var progress: Double {
        let value = snapshot.progress
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.track, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: snapshot.isOverBudget
                            ? [Theme.warning.opacity(0.7), Theme.warning]
                            : [Theme.accent.opacity(0.6), Theme.accent]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: -2) {
                Text(Fmt.kcal(abs(snapshot.remainingKcal)))
                    .font(Theme.number(size * 0.29, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(snapshot.isOverBudget ? Theme.warning : Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(snapshot.isOverBudget ? "已超出" : "还可吃")
                    .font(.system(size: size * 0.12, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, lineWidth + 2)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 小号（内容区 126×126）

private struct SmallLayout: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(spacing: 0) {
            // 行高 14：标题 + 同步时间
            HStack(spacing: 4) {
                Text("今日剩余")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(WidgetClock.time(snapshot.savedAt))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(Theme.tertiaryText)
                    .lineLimit(1)
            }
            .frame(height: 14)

            Spacer(minLength: 0)

            Ring(snapshot: snapshot, size: 76, lineWidth: 9)

            Spacer(minLength: 0)

            // 行高 14：消耗 + 步数
            HStack(spacing: 0) {
                footStat(symbol: "flame.fill", value: Fmt.kcal(snapshot.burnKcal))
                Spacer(minLength: 8)
                footStat(symbol: "figure.walk",
                         value: snapshot.steps.formatted(.number.precision(.fractionLength(0))))
            }
            .frame(height: 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func footStat(symbol: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Theme.accent)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(Theme.secondaryText)
                .lineLimit(1)
        }
    }
}

// MARK: - 中号（内容区 306×126）

private struct MediumLayout: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 0) {
            Ring(snapshot: snapshot, size: 88, lineWidth: 10)

            Spacer(minLength: 14)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("今日 · 目标 \(Fmt.kcal(snapshot.targetKcal)) kcal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text("更新于 \(WidgetClock.time(snapshot.savedAt))")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(Theme.tertiaryText)
                        .lineLimit(1)
                }
                .frame(height: 14)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    stat(symbol: "fork.knife", label: "摄入", value: Fmt.kcal(snapshot.intakeKcal))
                    Spacer(minLength: 8)
                    stat(symbol: "flame.fill", label: "消耗", value: Fmt.kcal(snapshot.burnKcal))
                }
                .frame(height: 32)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    stat(symbol: "figure.walk", label: "步数",
                         value: snapshot.steps.formatted(.number.precision(.fractionLength(0))))
                    Spacer(minLength: 8)
                    stat(symbol: "location.fill", label: "距离",
                         value: String(format: "%.1f km", snapshot.distanceKm))
                }
                .frame(height: 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stat(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Theme.accent)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.tertiaryText)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

// MARK: - 空态

private struct EmptyLayout: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(Theme.track)
            Text("打开「山与秤」同步今日数据")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 时间

private enum WidgetClock {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("Hm")
        return f
    }()

    static func time(_ date: Date) -> String { formatter.string(from: date) }
}
