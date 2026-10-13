import ActivityKit
import SwiftUI
import WidgetKit

/// 「今日热量」的锁屏实时活动 + 灵动岛。
///
/// 配色只用 Theme token（主题蓝），不在这里新造颜色；
/// 数字全部来自 ContentState，视图侧不做业务计算（口径唯一来源是 WidgetBridge）。
@available(iOS 16.1, *)
struct TodayLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TodayActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Theme.cardBackground)
                .activitySystemActionForegroundColor(Theme.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.accent)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("今日热量")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.secondaryText)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RemainingText(state: context.state, size: 20, showUnit: true)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if context.state.hasData {
                            ProgressBar(
                                progress: context.state.progress,
                                isOverBudget: context.state.isOverBudget
                            )
                            StatsRow(state: context.state)
                        } else {
                            Text("打开 App 同步")
                                .font(.caption)
                                .foregroundColor(Theme.secondaryText)
                        }
                    }
                }
            } compactLeading: {
                // 留一个能一眼认出「热量」的小图标。
                Image(systemName: "flame.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Theme.accent)
            } compactTrailing: {
                CompactRemaining(state: context.state)
            } minimal: {
                MinimalRing(state: context.state)
            }
            .keylineTint(Theme.accent)
        }
    }
}

// MARK: - 时间格式

@available(iOS 16.1, *)
private enum LiveActivityClock {
    /// 锁屏底部「更新于 HH:mm」，固定 24 小时制，跟 App 内其它时间戳风格一致。
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

// MARK: - 共用小组件

/// 剩余可吃的大数字：超支走警示色，没有数据时显示引导文案而不是假数字。
@available(iOS 16.1, *)
private struct RemainingText: View {
    let state: TodayActivityAttributes.ContentState
    let size: CGFloat
    let showUnit: Bool

    var body: some View {
        if state.hasData {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Fmt.kcal(abs(state.remainingKcal)))
                    .font(Theme.number(size, weight: .bold))
                    .foregroundColor(state.isOverBudget ? Theme.warning : Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if showUnit {
                    Text("kcal")
                        .font(.system(size: max(9, size * 0.42), weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                }
            }
        } else {
            Text("打开 App 同步")
                .font(.system(size: max(11, size * 0.5), weight: .medium))
                .foregroundColor(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// 蓝色渐变进度条：底衬 Theme.track，填充由浅蓝过渡到主题蓝。
@available(iOS 16.1, *)
private struct ProgressBar: View {
    let progress: Double
    let isOverBudget: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.track)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                (isOverBudget ? Theme.warning : Theme.accent).opacity(0.55),
                                isOverBudget ? Theme.warning : Theme.accent
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * min(1, max(0, progress)))
            }
        }
        .frame(height: 8)
    }
}

/// 摄入 / 消耗 / 步数 三小项，锁屏和灵动岛 bottom 共用。
@available(iOS 16.1, *)
private struct StatsRow: View {
    let state: TodayActivityAttributes.ContentState
    var updatedAt: Date?

    var body: some View {
        HStack(spacing: 14) {
            item("fork.knife", "摄入", Fmt.kcal(state.intakeKcal))
            item("flame.fill", "消耗", Fmt.kcal(state.burnKcal))
            item("figure.walk", "步数", state.steps.formatted(.number.precision(.fractionLength(0))))
            if let updatedAt {
                Spacer(minLength: 0)
                Text("更新于 \(LiveActivityClock.formatter.string(from: updatedAt))")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.tertiaryText)
                    .lineLimit(1)
            }
        }
    }

    private func item(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(Theme.tertiaryText)
                Text(value)
                    .font(Theme.number(13, weight: .semibold))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

// MARK: - 锁屏

@available(iOS 16.1, *)
private struct LockScreenView: View {
    let state: TodayActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "mountain.2.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Theme.accent)
                Text("山与秤 · 今日热量")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.secondaryText)
                Spacer(minLength: 0)
            }

            RemainingText(state: state, size: 34, showUnit: true)

            if state.hasData {
                ProgressBar(progress: state.progress, isOverBudget: state.isOverBudget)
                StatsRow(state: state, updatedAt: state.updatedAt)
            } else {
                Text("打开「山与秤」同步今日数据")
                    .font(.footnote)
                    .foregroundColor(Theme.tertiaryText)
            }
        }
        .padding(14)
    }
}

// MARK: - 灵动岛

/// 紧凑尾区：只放剩余数字，超支时换成警示色。
@available(iOS 16.1, *)
private struct CompactRemaining: View {
    let state: TodayActivityAttributes.ContentState

    var body: some View {
        Text(state.hasData ? Fmt.kcal(abs(state.remainingKcal)) : "--")
            .font(Theme.number(14, weight: .semibold))
            .foregroundColor(state.isOverBudget ? Theme.warning : Theme.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// 迷你态：进度环 + 剩余数字，没数据时只留灰环。
@available(iOS 16.1, *)
private struct MinimalRing: View {
    let state: TodayActivityAttributes.ContentState

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.track, lineWidth: 3)
            if state.hasData {
                Circle()
                    .trim(from: 0, to: min(1, max(0, state.progress)))
                    .stroke(
                        state.isOverBudget ? Theme.warning : Theme.accent,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 22, height: 22)
        .overlay {
            Text(state.hasData ? Fmt.kcal(abs(state.remainingKcal)) : "")
                .font(Theme.number(8, weight: .semibold))
                .foregroundColor(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(2)
    }
}
