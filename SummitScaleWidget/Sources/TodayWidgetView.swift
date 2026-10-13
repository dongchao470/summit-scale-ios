import SwiftUI
import WidgetKit

/// 小组件视图（方案 A · 环，最小高度版）。
///
/// 上一版按「widget 外框 − 系统边距」推算内容区高度，真机上环外的字被裁掉，
/// 说明推出来的高度偏大。这一版先按「绝不溢出」排：
/// - 小号只放一个环，数字与标签都在环内，**不放任何额外占高度的行**；
/// - 中号高度也只由环决定（右侧三行都排在环的高度之内）。
/// 真实可用尺寸由 provider 写进共享容器（`diag.displaySize`），拿到后再精调。
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

// MARK: - 环

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

            // 数字与标签都塞进环内：小号高度就只由环决定，没有东西会被裁。
            VStack(spacing: -1) {
                Text(Fmt.kcal(abs(snapshot.remainingKcal)))
                    .font(Theme.number(size * 0.30, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(snapshot.isOverBudget ? Theme.warning : Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(snapshot.isOverBudget ? "已超出" : "还可吃")
                    .font(.system(size: size * 0.13, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, lineWidth + 4)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 小号：只有一个环

private struct SmallLayout: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Ring(snapshot: snapshot, size: 72, lineWidth: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 中号：环 + 右侧信息（整体高度 = 环高）

private struct MediumLayout: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 14) {
            Ring(snapshot: snapshot, size: 72, lineWidth: 8)

            VStack(alignment: .leading, spacing: 0) {
                infoRow(symbol: "fork.knife", label: "摄入", value: Fmt.kcal(snapshot.intakeKcal))
                Spacer(minLength: 0)
                infoRow(symbol: "flame.fill", label: "消耗", value: Fmt.kcal(snapshot.burnKcal))
                Spacer(minLength: 0)
                infoRow(symbol: "figure.walk", label: "步数",
                        value: snapshot.steps.formatted(.number.precision(.fractionLength(0))))
            }
            .frame(maxHeight: .infinity)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func infoRow(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Theme.accent)
                .frame(width: 11)
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
