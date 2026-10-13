import SwiftUI
import WidgetKit

/// 今日运动小组件（X 款：消耗大数 + 步数/活动两条；中号加一行距离）。
///
/// 数据口径：与今日热量组件同一份快照，全部字段健康优先、本地兜底：
///   - 消耗 = 快照 burnKcal（健康活跃消耗 + 手动记录；没健康时退回本地今日条目合计）
///   - 步数 = 快照 steps（仅健康来源；本地记录没有步数，读不到就是 0）
///   - 活动 = 快照 exerciseMinutes（健康健身环的「活动」分钟；没健康时是本地锻炼时长合计）
///   - 距离 = 快照 distanceKm（健康优先，中号第三行用）
/// 四项全 0 → 切躺平小人缺省图，不拿假数字糊弄。
///
/// 结构刻意与 TodayWidgetView 保持一致：`body` 里裸 `switch family`，
/// 不把 family 分支塞进 `if #available` —— 之前那样写会让 WidgetKit 枚举预览时
/// 拿不到稳定视图类型，导致组件在「添加小组件」里被静默丢掉。
struct SportWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.isToday {
                switch family {
                case .systemMedium:
                    SportMediumLayout(snapshot: snapshot)
                default:
                    SportSmallLayout(snapshot: snapshot)
                }
            } else {
                EmptySportView()
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
                    Text("\(max(0, Int(snapshot.burnKcal)))")
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
        .padding(12)
    }
}

// MARK: - 进度点行

/// 一行「圆点 + 标签 + 数值 + 细进度条」，与热量组件同款视觉。
private struct SportDotRow: View {
    let color: Color
    let label: String
    let value: String
    let progress: Double

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.secondaryText)
                .frame(width: 26, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.track)
                    Capsule()
                        .fill(color)
                        .frame(width: max(3, geo.size.width * min(1, max(0, progress))))
                }
            }
            .frame(height: 6)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.primaryText)
                .monospacedDigit()
                .frame(minWidth: 34, alignment: .trailing)
        }
    }
}

private let barGreen = Color(red: 0.20, green: 0.83, blue: 0.60)   // #34D399
private let barBlue = Color(red: 0.376, green: 0.647, blue: 0.980) // #60A5FA
private let barOrange = Color(red: 0.98, green: 0.58, blue: 0.235) // #FA943C（Theme 无橙色，本地定义）

// MARK: - 更新时间

private let updateTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()

/// 右下角「更新 HH:mm」，取快照写入时间 savedAt。
private func updatedLabel(_ snapshot: WidgetSnapshot) -> Text {
    Text("更新 \(updateTimeFormatter.string(from: snapshot.savedAt))")
        .font(.system(size: 9, weight: .medium))
        .foregroundColor(Theme.secondaryText)
}

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
