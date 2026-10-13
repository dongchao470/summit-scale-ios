import SwiftUI
import WidgetKit

/// 今日运动小组件（X 款：消耗大数 + 步数/活动两条）。
///
/// 数据口径：与今日热量组件同一份快照，全部字段健康优先、本地兜底：
///   - 消耗 = 快照 burnKcal（健康活跃消耗 + 手动记录；没健康时退回本地今日条目合计）
///   - 步数 = 快照 steps（仅健康来源；本地记录没有步数，读不到就是 0）
///   - 活动 = 快照 exerciseMinutes（健康健身环的「活动」分钟；没健康时是本地锻炼时长合计）
///   - 距离 = 快照 distanceKm（健康优先，中号第三行用）
/// 四项全 0 → 切躺平小人缺省图，不拿假数字糊弄。
struct SportWidgetView: View {
    let entry: TodayEntry

    private var snapshot: WidgetSnapshot? {
        guard let snap = entry.snapshot, snap.isToday else { return nil }
        return snap
    }

    var body: some View {
        Group {
            if let snapshot {
                familyView(snapshot)
            } else {
                EmptySportView()
            }
        }
        .modifier(SportContainerBackground())
    }

    @ViewBuilder
    private func familyView(_ snapshot: WidgetSnapshot) -> some View {
        if #available(iOS 17.0, *) {
            switch family {
            case .systemMedium: SportMediumLayout(snapshot: snapshot)
            default: SportSmallLayout(snapshot: snapshot)
            }
        } else {
            switch family {
            case .systemMedium: SportMediumLayout(snapshot: snapshot)
            default: SportSmallLayout(snapshot: snapshot)
            }
        }
    }

    // 系统按 widget 所在槽位给 family；这里只在真正拿到中号时用中号版式。
    @Environment(\.widgetFamily) private var family
}

// MARK: - 小号

private struct SportSmallLayout: View {
    let snapshot: WidgetSnapshot

    /// 消耗/步数/活动全 0 才算「今天没动过」，只缺一项不算。
    private var isEmpty: Bool {
        snapshot.burnKcal <= 0 && snapshot.steps <= 0 && snapshot.exerciseMinutes <= 0
    }

    var body: some View {
        if isEmpty {
            EmptySportView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("今日运动")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                    Spacer(minLength: 6)
                    updatedLabel(snapshot)
                }

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Int(snapshot.burnKcal) >= 0 ? "\(Int(snapshot.burnKcal))" : "0")
                        .font(Theme.number(38, weight: .bold))
                        .foregroundColor(Theme.primaryText)
                        .minimumScaleFactor(0.5)
                    Text("kcal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                }

                VStack(alignment: .leading, spacing: 7) {
                    SportDotRow(
                        color: barBlue,
                        label: "步数",
                        value: snapshot.steps > 0 ? "\(Int(snapshot.steps))" : "—",
                        progress: min(1, snapshot.steps / 10000)
                    )
                    SportDotRow(
                        color: barGreen,
                        label: "活动",
                        value: snapshot.exerciseMinutes > 0 ? "\(Int(snapshot.exerciseMinutes))分" : "—",
                        progress: min(1, snapshot.exerciseMinutes / 30)
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 中号

private struct SportMediumLayout: View {
    let snapshot: WidgetSnapshot

    private var isEmpty: Bool {
        snapshot.burnKcal <= 0 && snapshot.steps <= 0 && snapshot.exerciseMinutes <= 0
    }

    var body: some View {
        if isEmpty {
            EmptySportView()
        } else {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(max(0, Int(snapshot.burnKcal)))")
                            .font(Theme.number(38, weight: .bold))
                            .foregroundColor(Theme.primaryText)
                            .minimumScaleFactor(0.5)
                        Text("kcal")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                    }
                    Text("今日运动")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.primaryText)
                }

                VStack(alignment: .leading, spacing: 9) {
                    SportDotRow(
                        color: barBlue,
                        label: "步数",
                        value: snapshot.steps > 0 ? "\(Int(snapshot.steps))" : "—",
                        progress: min(1, snapshot.steps / 10000)
                    )
                    SportDotRow(
                        color: barGreen,
                        label: "活动",
                        value: snapshot.exerciseMinutes > 0 ? "\(Int(snapshot.exerciseMinutes))分" : "—",
                        progress: min(1, snapshot.exerciseMinutes / 30)
                    )
                    SportDotRow(
                        color: barOrange,
                        label: "距离",
                        value: snapshot.distanceKm > 0 ? String(format: "%.1fkm", snapshot.distanceKm) : "—",
                        progress: min(1, snapshot.distanceKm / 5)
                    )
                    updatedLabel(snapshot)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 缺省图：躺平小人

/// 消耗/步数/活动全 0 时的占位：一个躺平的小人 +「今天还没动起来」。
private struct EmptySportView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.stand")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(Theme.secondaryText.opacity(0.6))
                .rotationEffect(.degrees(90))
                .frame(height: 40)
            Text("今天还没动起来")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 行组件

/// 一行：圆点 + 标识 + 数值 + 进度条。
private struct SportDotRow: View {
    let color: Color
    let label: String
    let value: String
    let progress: Double

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Theme.secondaryText)
            SportBar(progress: progress, color: color)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.secondaryText)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }
}

/// 细进度条。
private struct SportBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.secondaryText.opacity(0.2))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }
}

/// 更新时间小字（与热量组件同款）。
private func updatedLabel(_ snapshot: WidgetSnapshot) -> Text {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "HH:mm"
    return Text("更新 \(formatter.string(from: snapshot.savedAt))")
        .font(.system(size: 9, weight: .medium))
        .foregroundColor(Theme.secondaryText)
}

private let barOrange = Color(red: 1.0, green: 0.62, blue: 0.26)   // #FF9F43
private let barGreen = Color(red: 0.20, green: 0.83, blue: 0.60)   // #34D399
private let barBlue = Color(red: 0.376, green: 0.647, blue: 0.980) // #60A5FA

// MARK: - Widget 注册

struct SportTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SportTodayWidget", provider: TodayProvider()) { entry in
            SportWidgetView(entry: entry)
        }
        .configurationDisplayName("今日运动")
        .description("消耗、步数与活动分钟，动没动一眼就知道。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - 容器背景

/// iOS 17 起 widget 必须自己声明容器背景；iOS 16 保留系统默认材质。
private struct SportContainerBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(for: .widget) { Theme.cardBackground }
        } else {
            content
        }
    }
}
