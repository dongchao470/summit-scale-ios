import Foundation
import SwiftUI
import WidgetKit

/// widget 根视图：小号 / 中号两种布局，没数据就退到引导态。
///
/// 版式刻意只用「固定尺寸 + Spacer 弹性」，**不碰 GeometryReader 按比例分配**：
/// 0.6.2 那版就是那么写的，结果桌面整块白屏——连空态文字都不显示，只能回退。
/// 想再玩花活，先在真机上验证过再说。
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

// MARK: - 背景

private extension View {
    /// iOS 17 起 widget 必须自己声明容器背景（否则 StandBy / iPad 上显示异常）；
    /// iOS 16 保留系统默认材质——比自己糊一层不透明色好看，也更贴壁纸。
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

private struct Ring: View {
    let progress: Double
    let isOver: Bool
    let size: CGFloat
    let lineWidth: CGFloat

    /// 底圈轨道 + 一段角向渐变的进度弧。比纯色描边多一点层次，
    /// 但仍然只是 `Circle().trim()`，不做任何尺寸测量。
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamp01(progress))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: isOver
                            ? [Theme.warning.opacity(0.7), Theme.warning]
                            : [Theme.accent.opacity(0.6), Theme.accent]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

/// 进度只接受 0…1。宁可画成空环，也不能把 NaN / 无穷丢给 `trim`——
/// 那种值会让整条路径画不出来。
private func clamp01(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
}

// MARK: - 时间

private enum WidgetClock {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("Hm")
        return f
    }()

    static func short(_ date: Date) -> String { formatter.string(from: date) }

    /// 快照超过 1 小时没动过就配个同步图标——别让人以为这是实时值。
    static func isStale(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) > 3600
    }
}

// MARK: - 小号

private struct SmallLayout: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.accent)
                Text("今日")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                Spacer(minLength: 0)
                if WidgetClock.isStale(snapshot.savedAt) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.tertiaryText)
                }
                Text(WidgetClock.short(snapshot.savedAt))
                    .font(Theme.number(10, weight: .medium))
                    .foregroundColor(Theme.tertiaryText)
            }

            ZStack {
                Ring(
                    progress: snapshot.progress,
                    isOver: snapshot.isOverBudget,
                    size: 72,
                    lineWidth: 9
                )
                VStack(spacing: -1) {
                    Text(Fmt.kcal(abs(snapshot.remainingKcal)))
                        .font(Theme.number(21, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(snapshot.isOverBudget ? Theme.warning : Theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(snapshot.isOverBudget ? "已超出" : "还可吃")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                footStat("flame.fill", Fmt.kcal(snapshot.burnKcal))
                Spacer(minLength: 8)
                footStat("figure.walk", stepsLabel)
            }
        }
    }

    private var stepsLabel: String {
        snapshot.steps.formatted(.number.precision(.fractionLength(0)))
    }

    private func footStat(_ icon: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Theme.accent)
            Text(value)
                .font(Theme.number(12, weight: .semibold))
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
        HStack(spacing: 14) {
            ZStack {
                Ring(
                    progress: snapshot.progress,
                    isOver: snapshot.isOverBudget,
                    size: 92,
                    lineWidth: 11
                )
                VStack(spacing: -1) {
                    Text(Fmt.kcal(abs(snapshot.remainingKcal)))
                        .font(Theme.number(26, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(snapshot.isOverBudget ? Theme.warning : Theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(snapshot.isOverBudget ? "已超出" : "还可吃")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Text("今日 · 目标 \(Fmt.kcal(snapshot.targetKcal)) kcal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if WidgetClock.isStale(snapshot.savedAt) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.tertiaryText)
                    }
                    Text(WidgetClock.short(snapshot.savedAt))
                        .font(Theme.number(10, weight: .medium))
                        .foregroundColor(Theme.tertiaryText)
                        .lineLimit(1)
                }

                HStack(spacing: 14) {
                    stat("fork.knife", "摄入", Fmt.kcal(snapshot.intakeKcal))
                    stat("flame.fill", "消耗", Fmt.kcal(snapshot.burnKcal))
                }
                HStack(spacing: 14) {
                    stat("figure.walk", "步数", snapshot.steps.formatted(.number.precision(.fractionLength(0))))
                    stat("location.fill", "距离", String(format: "%.1f", snapshot.distanceKm))
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func stat(_ icon: String, _ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.accent)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.tertiaryText)
            }
            Text(value)
                .font(Theme.number(15, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minWidth: 56, alignment: .leading)
    }
}

// MARK: - 空态

private struct EmptyLayout: View {
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.accent)
            Text("打开「山与秤」同步今日数据")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.horizontal, 6)
    }
}
