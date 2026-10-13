import Foundation
import SwiftUI
import WidgetKit

/// widget 根视图：小号 / 中号两种布局，没数据或快照跨天就退到引导态。
///
/// v0.6.1 重做版式，专治「环被挤扁、元素叠在一起」：
/// 1. 尺寸不再写死 72 / 92pt：外层 GeometryReader 给出真实可用边长，环放进 VStack 的
///    弹性格里取正方形——空间不够先缩环，绝不压到上下两行文字。
/// 2. 所有文本 lineLimit(1) + minimumScaleFactor(0.6)，主数字 monospacedDigit，只缩不挤不截断。
/// 3. 间距走 snap4() 吸到 4 的倍数；字号用 clamp() 按边长比例夹上下限，随尺寸连续变化。
/// 4. 层级：环心主数字（最大最粗） > 进度环 > 次级统计 > 说明文字与时间。
///    颜色只取 Theme，无渐变背景、无阴影；数据新旧靠 savedAt 显示的「更新于 HH:mm」体现。
/// 扩展自己的版本号，直接画在 widget 上。
///
/// 为什么要在界面上暴露这种东西：排查「桌面一片空白」时，最要紧的是先分清
/// 「新包根本没装上」和「装上了但扩展没被系统加载」——有这行字，装上就能自证。
private enum WidgetBuild {
    static let short: String =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.isToday {
                let stale = isStale(snapshot, at: entry.date)
                switch family {
                case .systemMedium:
                    MediumLayout(snapshot: snapshot, isStale: stale)
                default:
                    SmallLayout(snapshot: snapshot, isStale: stale)
                }
            } else {
                // 跨天（isToday == false）与从没同步过都走空态，避免桌面整天挂昨天的数字。
                EmptyLayout(kind: entry.snapshot == nil ? .noData : .expired)
            }
        }
        .widgetCanvas()
    }

    /// 快照写入超过 1 小时视为陈旧：不拦内容，只在时间旁挂一个小图标提示可能没同步。
    private func isStale(_ snapshot: WidgetSnapshot, at date: Date) -> Bool {
        date.timeIntervalSince(snapshot.savedAt) > 60 * 60
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

// MARK: - 尺度与时间工具

/// 夹上下限：小尺寸下算出来的值别变成 0 或负数。
private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
    min(max(value, lower), upper)
}

/// 间距一律吸到 4 的倍数，整屏节奏统一。
private func snap4(_ value: CGFloat) -> CGFloat {
    max(4, (value / 4).rounded() * 4)
}

/// 只显示「几点几分」，用来交代这份数字是几点同步的。
private enum WidgetClock {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("Hm")
        return formatter
    }()

    static func time(_ date: Date) -> String {
        formatter.string(from: date)
    }
}

// MARK: - 环

/// 进度环：底圈 track + 角向渐变的填充（浅色起步、收尾用满强度），圆头收口。
private struct Ring: View {
    let progress: Double
    let isOver: Bool
    let diameter: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamp(CGFloat(progress), 0, 1))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [tint.opacity(0.45), tint]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    /// 只有超支才切警示色，其余一律主题蓝。
    private var tint: Color { isOver ? Theme.warning : Theme.accent }
}

/// 环 + 环心读数。环在所在格子里取正方形，读左右各留 22% 半径的安全边，
/// 所以「12800」这种长数字也只会缩字号，不会压到描边或溢出。
private struct RingReadout: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        GeometryReader { geo in
            let side = max(24, min(geo.size.width, geo.size.height))
            let lineWidth = clamp(side * 0.11, 5, 12)
            let numberSize = clamp(side * 0.27, 13, 30)
            let labelSize = clamp(side * 0.11, 8, 11)

            ZStack {
                Ring(
                    progress: snapshot.progress,
                    isOver: snapshot.isOverBudget,
                    diameter: side,
                    lineWidth: lineWidth
                )

                VStack(spacing: 0) {
                    Text(Fmt.kcal(abs(snapshot.remainingKcal)))
                        .font(Theme.number(numberSize, weight: .bold))
                        .foregroundColor(snapshot.isOverBudget ? Theme.warning : Theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(snapshot.isOverBudget ? "已超出" : "还可吃")
                        .font(.system(size: labelSize, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, side * 0.22)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - 小号

/// 小号：一行标题（含更新时间）+ 弹性环 + 一行三项次要数据。
/// 中间那段是弹性的——高度不够时先缩环，头和脚的位置永远不动。
private struct SmallLayout: View {
    let snapshot: WidgetSnapshot
    let isStale: Bool

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let gap = snap4(side * 0.05)
            let titleSize = clamp(side * 0.10, 9, 12)
            let footSize = clamp(side * 0.11, 9, 13)

            VStack(spacing: gap) {
                header(titleSize: titleSize)
                RingReadout(snapshot: snapshot)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer(size: footSize)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func header(titleSize: CGFloat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: titleSize * 0.85, weight: .bold))
                .foregroundColor(Theme.accent)
                .accessibilityHidden(true)
            Text("今日")
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundColor(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 4)

            if isStale {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: titleSize * 0.8, weight: .semibold))
                    .foregroundColor(Theme.tertiaryText)
                    .accessibilityHidden(true)
            }
            // 小号只放「HH:mm」，交代这份数字是几点同步的；后面缀扩展版本号，便于确认新包是否真装上。
            Text("\(WidgetClock.time(snapshot.savedAt)) · \(WidgetBuild.short)")
                .font(Theme.number(titleSize * 0.95, weight: .medium))
                .foregroundColor(Theme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// 三项等宽平分，每项最多 1/3 宽，数字长了就缩字号，绝不横向溢出。
    private func footer(size: CGFloat) -> some View {
        HStack(spacing: 4) {
            footStat("fork.knife", Fmt.kcal(snapshot.intakeKcal), size: size)
            footStat("flame.fill", Fmt.kcal(snapshot.burnKcal), size: size)
            footStat("figure.walk", stepsLabel, size: size)
        }
    }

    private func footStat(_ icon: String, _ value: String, size: CGFloat) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: size * 0.8, weight: .semibold))
                .foregroundColor(Theme.accent)
                .accessibilityHidden(true)
            Text(value)
                .font(Theme.number(size, weight: .semibold))
                .foregroundColor(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var stepsLabel: String {
        snapshot.steps.formatted(.number.precision(.fractionLength(0)))
    }
}

// MARK: - 中号

/// 中号：左边环当焦点，右边一列「今日 · 目标」+ 2x2 统计 + 底行更新时间。
/// 右侧两列等宽平分（不再用 minWidth 硬撑），窗口再窄也只是字号缩，不会挤到截断。
private struct MediumLayout: View {
    let snapshot: WidgetSnapshot
    let isStale: Bool

    var body: some View {
        GeometryReader { geo in
            let ring = clamp(min(geo.size.height * 0.92, geo.size.width * 0.32), 44, geo.size.height)
            let gap = snap4(geo.size.width * 0.035)
            let rowGap = snap4(geo.size.height * 0.06)
            let titleSize = clamp(geo.size.height * 0.105, 10, 13)
            let labelSize = clamp(geo.size.height * 0.085, 9, 11)
            let valueSize = clamp(geo.size.height * 0.13, 12, 17)

            HStack(spacing: gap) {
                RingReadout(snapshot: snapshot)
                    .frame(width: ring, height: ring)

                VStack(alignment: .leading, spacing: rowGap) {
                    header(titleSize: titleSize, labelSize: labelSize)

                    HStack(spacing: gap) {
                        stat("fork.knife", "摄入", Fmt.kcal(snapshot.intakeKcal), labelSize: labelSize, valueSize: valueSize)
                        stat("flame.fill", "消耗", Fmt.kcal(snapshot.burnKcal), labelSize: labelSize, valueSize: valueSize)
                    }
                    HStack(spacing: gap) {
                        stat("figure.walk", "步数", stepsLabel, labelSize: labelSize, valueSize: valueSize)
                        stat("location.fill", "距离", String(format: "%.1f", snapshot.distanceKm), labelSize: labelSize, valueSize: valueSize)
                    }

                    footer(labelSize: labelSize)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func header(titleSize: CGFloat, labelSize: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text("今日")
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundColor(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("目标 \(Fmt.kcal(snapshot.targetKcal)) kcal")
                .font(.system(size: labelSize, weight: .regular))
                .foregroundColor(Theme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
    }

    /// 底行：数据新旧一眼可见；陈旧时补一个同步图标，不额外占一行。
    private func footer(labelSize: CGFloat) -> some View {
        HStack(spacing: 3) {
            if isStale {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: labelSize * 0.85, weight: .semibold))
                    .foregroundColor(Theme.tertiaryText)
                    .accessibilityHidden(true)
            }
            Text("更新于 \(WidgetClock.time(snapshot.savedAt)) · \(WidgetBuild.short)")
                .font(.system(size: labelSize, weight: .medium))
                .foregroundColor(Theme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
    }

    private func stat(
        _ icon: String,
        _ label: String,
        _ value: String,
        labelSize: CGFloat,
        valueSize: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: labelSize * 0.85, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(size: labelSize, weight: .medium))
                    .foregroundColor(Theme.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(value)
                .font(Theme.number(valueSize, weight: .bold))
                .foregroundColor(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var stepsLabel: String {
        snapshot.steps.formatted(.number.precision(.fractionLength(0)))
    }
}

// MARK: - 空态

/// 引导态两种：从没同步过、快照跨天过期。同一个蓝色山形徽标 + 一句话，风格与主体一致。
private struct EmptyLayout: View {
    enum Kind {
        /// 共享通道没数据 / 从没打开过 App。
        case noData
        /// 有快照但属于昨天，按过期处理。
        case expired
    }

    @Environment(\.widgetFamily) private var family
    let kind: Kind

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Theme.track)
                    .frame(width: badge, height: badge)
                Image(systemName: symbol)
                    .font(.system(size: badge * 0.48, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .accessibilityHidden(true)
            }

            Text(message)
                .font(.system(size: textSize, weight: .medium))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)

            // 空态也标版本：如果连这行都不显示，说明扩展压根没被系统加载，而不是「没数据」。
            Text("扩展 \(WidgetBuild.short)")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    private var symbol: String {
        switch kind {
        case .noData: return "mountain.2.fill"
        case .expired: return "clock.arrow.circlepath"
        }
    }

    private var message: String {
        switch kind {
        case .noData:
            return "打开「山与秤」同步今日数据"
        case .expired:
            return "昨日数据已过期\n打开「山与秤」同步"
        }
    }

    private var badge: CGFloat { family == .systemMedium ? 40 : 34 }
    private var textSize: CGFloat { family == .systemMedium ? 12 : 11 }
}
