import SwiftUI
import WidgetKit

/// 小组件视图（方案 A · 环，收紧版）。
///
/// 尺寸策略：**不再假设内容区是 126×126**。
/// 上一版按「158 − 16×2」算，真机上小号文字被挤出边界，说明系统留的边距比想象的大。
/// 现在两条腿一起走：
/// 1. 布局按更保守的值排（小号：行高 12 + 环 64 + 行高 12 = 88，留足余量）；
/// 2. 右下角用 8pt 小字画出系统真正给到的内容区尺寸——装一次就能读到准确值，下次照它精调。
struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        GeometryReader { geo in
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
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .bottomTrailing) {
                Text("\(Int(geo.size.width))×\(Int(geo.size.height))")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(Theme.tertiaryText)
                    .opacity(0.55)
            }
        }
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

/// 环形进度：底圈 + 渐变弧，中间放主数字。尺寸完全由外部给定，自己不做测量。
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

            VStack(spacing: -1) {
                Text(Fmt.kcal(abs(snapshot.remainingKcal)))
                    .font(Theme.number(size * 0.27, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(snapshot.isOverBudget ? Theme.warning : Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(snapshot.isOverBudget ? "已超出" : "还可吃")
                    .font(.system(size: max(8, size * 0.11), weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, lineWidth + 3)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 小号（保守按内容区 100×100 也能放下）

private struct SmallLayout: View {
    let snapshot: WidgetSnapshot

    private var stepsText: String {
        snapshot.steps.formatted(.number.precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("今日剩余")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(WidgetClock.time(snapshot.savedAt))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(Theme.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(height: 12)

            Spacer(minLength: 2)

            Ring(snapshot: snapshot, size: 64, lineWidth: 7)

            Spacer(minLength: 2)

            HStack(spacing: 0) {
                footStat(symbol: "flame.fill", value: Fmt.kcal(snapshot.burnKcal))
                Spacer(minLength: 6)
                footStat(symbol: "figure.walk", value: stepsText)
            }
            .frame(height: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func footStat(symbol: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Theme.accent)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - 中号

private struct MediumLayout: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 0) {
            Ring(snapshot: snapshot, size: 76, lineWidth: 9)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("今日 · 目标 \(Fmt.kcal(snapshot.targetKcal)) kcal")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Text("更新于 \(WidgetClock.time(snapshot.savedAt))")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(Theme.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(height: 12)

                Spacer(minLength: 2)

                HStack(spacing: 8) {
                    stat(symbol: "fork.knife", label: "摄入", value: Fmt.kcal(snapshot.intakeKcal))
                    Spacer(minLength: 8)
                    stat(symbol: "flame.fill", label: "消耗", value: Fmt.kcal(snapshot.burnKcal))
                }
                .frame(height: 28)

                Spacer(minLength: 2)

                HStack(spacing: 8) {
                    stat(symbol: "figure.walk", label: "步数",
                         value: snapshot.steps.formatted(.number.precision(.fractionLength(0))))
                    Spacer(minLength: 8)
                    stat(symbol: "location.fill", label: "距离",
                         value: String(format: "%.1f km", snapshot.distanceKm))
                }
                .frame(height: 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stat(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Theme.accent)
                .frame(width: 11)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.tertiaryText)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
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
        VStack(spacing: 6) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Theme.track)
            Text("打开「山与秤」同步今日数据")
                .font(.system(size: 11, weight: .medium))
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
