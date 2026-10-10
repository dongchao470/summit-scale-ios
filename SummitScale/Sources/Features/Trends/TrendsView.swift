import Charts
import CoreData
import SwiftUI

/// 趋势页：体重走向、每日热量对比目标、运动消耗。
struct TrendsView: View {
    enum Span: String, CaseIterable, Identifiable {
        case week
        case month
        case quarter

        var id: String { rawValue }

        var title: String {
            switch self {
            case .week: return "7 天"
            case .month: return "30 天"
            case .quarter: return "90 天"
            }
        }

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            }
        }
    }

    @FetchRequest(sortDescriptors: WeightEntry.dateDescending, animation: .default)
    private var weights: FetchedResults<WeightEntry>

    @FetchRequest(sortDescriptors: FoodEntry.dateDescending, animation: .default)
    private var foods: FetchedResults<FoodEntry>

    @FetchRequest(sortDescriptors: ActivityEntry.dateDescending, animation: .default)
    private var activities: FetchedResults<ActivityEntry>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)],
        animation: .default
    )
    private var profiles: FetchedResults<UserProfile>

    @State private var span: Span = .week

    // MARK: - 派生数据

    private var profile: UserProfile? { profiles.first }

    private var startDay: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -(span.days - 1), to: today) ?? today
    }

    private var budget: CalorieBudget? {
        guard let profile = profile else { return nil }
        return Persistence.shared.calorieBudget(for: profile, currentKilograms: weights.first?.kilograms)
    }

    /// 体重点，一天多次只留最新那次。
    private var weightPoints: [DayValue] {
        let calendar = Calendar.current
        var byDay: [Date: Double] = [:]
        for entry in weights where entry.date >= startDay {
            let day = calendar.startOfDay(for: entry.date)
            if byDay[day] == nil {
                byDay[day] = entry.kilograms
            }
        }
        return byDay.map { DayValue(day: $0.key, value: $0.value) }.sorted { $0.day < $1.day }
    }

    /// 每天的摄入热量，没记录的日子补 0，柱状图不会缺格。
    private var dailyIntake: [DayValue] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var byDay: [Date: Double] = [:]
        for entry in foods where entry.date >= startDay {
            byDay[calendar.startOfDay(for: entry.date), default: 0] += entry.kcal
        }

        var result: [DayValue] = []
        var cursor = startDay
        while cursor <= today {
            result.append(DayValue(day: cursor, value: byDay[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// 只统计真正记过东西的日子，否则平均值会被空白日拉低。
    private var averageIntake: Double {
        let logged = dailyIntake.filter { $0.value > 0 }
        guard !logged.isEmpty else { return 0 }
        return logged.reduce(0) { $0 + $1.value } / Double(logged.count)
    }

    private var totalBurn: Double {
        activities.filter { $0.date >= startDay }.reduce(0) { $0 + $1.kcal }
    }

    private var loggedDays: Int {
        dailyIntake.filter { $0.value > 0 }.count
    }

    private var weightChange: Double? {
        guard let first = weightPoints.first, let last = weightPoints.last, weightPoints.count >= 2 else { return nil }
        return last.value - first.value
    }

    private var weightDomain: ClosedRange<Double> {
        var values = weightPoints.map { $0.value }
        if let target = profile?.targetWeightKilograms { values.append(target) }
        guard let low = values.min(), let high = values.max() else { return 50...80 }
        let padding = max(0.8, (high - low) * 0.3)
        return (low - padding)...(high + padding)
    }

    private var calorieDomain: ClosedRange<Double> {
        let peak = max(dailyIntake.map { $0.value }.max() ?? 0, budget?.intakeTarget ?? 0)
        return 0...(max(peak * 1.15, 500))
    }

    // MARK: - 视图

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.stackSpacing) {
                    Picker("时间范围", selection: $span) {
                        ForEach(Span.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    summaryCard
                    weightCard
                    intakeCard
                    activityCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 96)
            }
            .background(Theme.pageBackground)
            .navigationTitle("趋势")
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "这段时间", symbol: "calendar")

            HStack(spacing: 8) {
                StatTile(
                    title: "平均摄入",
                    value: averageIntake > 0 ? Fmt.kcal(averageIntake) : "—",
                    unit: "kcal",
                    tint: Theme.accent
                )
                StatTile(
                    title: "累计运动",
                    value: Fmt.kcal(totalBurn),
                    unit: "kcal",
                    tint: Theme.success
                )
                StatTile(
                    title: "记录天数",
                    value: "\(loggedDays)",
                    unit: "天"
                )
            }

            Text(budget.map { "每日摄入目标 \(Fmt.kcal($0.intakeTarget)) kcal" } ?? "先完成档案，才会算出目标")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .card()
    }

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle(text: "体重走向", symbol: "scalemass.fill")
                Spacer()
                if let change = weightChange {
                    Text(change <= 0 ? "↓ \(Fmt.kg(abs(change))) kg" : "↑ \(Fmt.kg(change)) kg")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(change <= 0 ? Theme.success : Theme.warning)
                }
            }

            if weightPoints.count < 2 {
                emptyHint("这段区间至少记两次体重，曲线才画得出来")
            } else {
                Chart {
                    ForEach(weightPoints) { point in
                        LineMark(
                            x: .value("日期", point.day),
                            y: .value("体重", point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.accent)

                        PointMark(
                            x: .value("日期", point.day),
                            y: .value("体重", point.value)
                        )
                        .foregroundStyle(Theme.accent)
                        .symbolSize(30)
                    }

                    if let target = profile?.targetWeightKilograms {
                        RuleMark(y: .value("目标", target))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Theme.success)
                            .annotation(position: .top, alignment: .leading) {
                                Text("目标 \(Fmt.kg(target)) kg")
                                    .font(.caption2)
                                    .foregroundColor(Theme.success)
                            }
                    }
                }
                .chartYScale(domain: weightDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .frame(height: 190)
            }
        }
        .card()
    }

    private var intakeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle(text: "每日摄入", symbol: "fork.knife")
                Spacer()
                if let budget = budget {
                    Text("目标线 \(Fmt.kcal(budget.intakeTarget))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if loggedDays == 0 {
                emptyHint("还没有饮食记录")
            } else {
                Chart {
                    ForEach(dailyIntake) { item in
                        BarMark(
                            x: .value("日期", item.day),
                            y: .value("摄入", item.value)
                        )
                        .foregroundStyle(
                            item.value > (budget?.intakeTarget ?? .infinity)
                                ? Theme.warning
                                : Theme.accent.opacity(0.85)
                        )
                        .cornerRadius(4)
                    }

                    if let budget = budget {
                        RuleMark(y: .value("目标", budget.intakeTarget))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                            .foregroundStyle(Theme.success)
                    }
                }
                .chartYScale(domain: calorieDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: span == .week ? 7 : 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .frame(height: 170)
            }
        }
        .card()
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "运动消耗", symbol: "figure.walk")

            if activities.filter({ $0.date >= startDay }).isEmpty {
                emptyHint("这段时间还没有运动记录")
            } else {
                let recent = activities.filter { $0.date >= startDay }.prefix(6)
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.objectID) { index, entry in
                        HStack(spacing: 10) {
                            Image(systemName: entry.kindValue.symbol)
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(Theme.success)
                                .frame(width: 26, height: 26)
                                .background(Theme.success.opacity(0.14), in: Circle())

                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.displayTitle)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Text(Fmt.relativeDay(entry.date))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text("-\(Fmt.kcal(entry.kcal)) kcal")
                                .font(Theme.number(15))
                                .foregroundColor(Theme.success)
                        }
                        .padding(.vertical, 8)

                        if index < recent.count - 1 {
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
        }
        .card()
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
    }

    private struct DayValue: Identifiable {
        let day: Date
        let value: Double
        var id: Date { day }
    }
}
