import SwiftUI

/// 一天热量的圆环：实心弧表示已摄入占目标的比例，中心写剩余额度。
struct CalorieRingView: View {
    let ledger: DayLedger

    private var isOver: Bool { ledger.remainingKcal < 0 }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ring
            legend
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.15), lineWidth: 12)

            Circle()
                .trim(from: 0, to: min(1, max(0, ledger.progress)))
                .stroke(
                    isOver ? Color.orange : Color.accentColor,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text(Fmt.kcal(abs(ledger.remainingKcal)))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(isOver ? .orange : .primary)
                Text(isOver ? "超出" : "还能吃")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 112, height: 112)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            legendRow(
                title: "目标",
                value: Fmt.kcal(ledger.budget.intakeTarget),
                color: .secondary
            )
            legendRow(
                title: "已吃",
                value: Fmt.kcal(ledger.intakeKcal),
                color: .primary
            )
            legendRow(
                title: "运动",
                value: ledger.burnKcal > 0 ? "+" + Fmt.kcal(ledger.burnKcal) : "0",
                color: ledger.burnKcal > 0 ? .green : .secondary
            )
        }
    }

    private func legendRow(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(width: 34, alignment: .leading)
            Text(value)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundColor(color)
            Text("kcal")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var accessibilityText: String {
        let head = "今日热量。目标 \(Fmt.kcal(ledger.budget.intakeTarget)) 千卡，已摄入 \(Fmt.kcal(ledger.intakeKcal)) 千卡，运动消耗 \(Fmt.kcal(ledger.burnKcal)) 千卡。"
        if isOver {
            return head + "已超出 \(Fmt.kcal(abs(ledger.remainingKcal))) 千卡。"
        }
        return head + "还可以吃 \(Fmt.kcal(ledger.remainingKcal)) 千卡。"
    }
}

/// 三个数字并排的小指标，今日页和详情页共用。
struct MetricTile: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
