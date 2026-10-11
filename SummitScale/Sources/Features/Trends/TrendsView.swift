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

    /// 热力图专用：固定取最近 17 周（约 4 个月），不跟随上面的 7/30/90 天切换。
    private var heatmapIntake: [DayValue] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(17 * 7 - 1), to: today) ?? today
        var byDay: [Date: Double] = [:]
        for entry in foods where entry.date >= start {
            byDay[calendar.startOfDay(for: entry.date), default: 0] += entry.kcal
        }
        var result: [DayValue] = []
        var cursor = start
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
            List {
                Section {
                    Picker("时间范围", selection: $span) {
                        ForEach(Span.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                summarySection
                recordSection
                weightSection
                intakeSection
                activitySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("趋势")
        }
    }

    /// 分组标题统一带一个强调色小图标，跟今天页的餐次标题一个路数。
    private func sectionHeader(_ text: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.accent)
                .accessibilityHidden(true)
            Text(text)
        }
        .textCase(nil)
    }

    private var summarySection: some View {
        Section {
            // 参考风格：一个大号黑体 hero 数字领头，次级统计走中性灰，不再三块彩色数字抢眼。
            VStack(alignment: .leading, spacing: 2) {
                Text("平均每日摄入")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(averageIntake > 0 ? Fmt.kcal(averageIntake) : "—")
                        .font(Theme.number(42, weight: .bold))
                        .foregroundColor(.primary)
                    Text("kcal")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                Text(budget.map { "每日目标 \(Fmt.kcal($0.intakeTarget)) kcal" } ?? "先完成档案，才会算出目标")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)

            HStack(spacing: 0) {
                miniStat(title: "累计运动", value: Fmt.kcal(totalBurn), unit: "kcal")
                Divider().frame(height: 34)
                miniStat(title: "记录天数", value: "\(loggedDays)", unit: "天")
            }
        } header: {
            sectionHeader("这段时间", symbol: "calendar")
        }
    }

    /// 记录热度：仿参考图的热力网格，按每天摄入占目标的比例着色，只用强调色深浅表达，不掺红绿。
    private var recordSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                RecordHeatmap(days: heatmapIntake, target: budget?.intakeTarget)

                HStack(spacing: 6) {
                    Text("少")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    ForEach(0..<5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(RecordHeatmap.color(for: level))
                            .frame(width: 11, height: 11)
                    }
                    Text("多")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                    Text("\(loggedDays)/\(dailyIntake.count) 天有记录")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("记录热度，这段时间 \(dailyIntake.count) 天里有 \(loggedDays) 天记录了饮食")
        } header: {
            sectionHeader("记录热度", symbol: "square.grid.2x2.fill")
        }
    }

    /// 次级小统计：灰标题 + 黑数字，水平均分，参考风格里的底排小字。
    private func miniStat(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.number(20))
                    .foregroundColor(.primary)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value) \(unit)")
    }

    private var weightSection: some View {
        Section {
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
                        // 目标线走中性灰虚线，不抢体重曲线的强调色，也不再用绿色。
                        RuleMark(y: .value("目标", target))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Theme.secondaryText)
                            .annotation(position: .top, alignment: .leading) {
                                Text("目标 \(Fmt.kg(target)) kg")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
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
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "scalemass.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.accent)
                    .accessibilityHidden(true)
                Text("体重走向")
                Spacer()
                if let change = weightChange {
                    // 方向靠箭头字形表达，颜色只在"下降（达成方向）"时点一下强调色，增重则走中性灰，不用红绿。
                    Text(change <= 0 ? "↓ \(Fmt.kg(abs(change))) kg" : "↑ \(Fmt.kg(change)) kg")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(change <= 0 ? Theme.accent : .secondary)
                }
            }
            .textCase(nil)
        }
    }

    private var intakeSection: some View {
        Section {
            if loggedDays == 0 {
                emptyHint("还没有饮食记录")
            } else {
                Chart {
                    ForEach(dailyIntake) { item in
                        BarMark(
                            x: .value("日期", item.day),
                            y: .value("摄入", item.value)
                        )
                        .foregroundStyle(Theme.accent.opacity(0.85))
                        .cornerRadius(4)
                    }

                    if let budget = budget {
                        RuleMark(y: .value("目标", budget.intakeTarget))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                            .foregroundStyle(Theme.secondaryText)
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
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "fork.knife")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.accent)
                    .accessibilityHidden(true)
                Text("每日摄入")
                Spacer()
                if let budget = budget {
                    Text("目标线 \(Fmt.kcal(budget.intakeTarget))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .textCase(nil)
        }
    }

    private var activitySection: some View {
        Section {
            if activities.filter({ $0.date >= startDay }).isEmpty {
                emptyHint("这段时间还没有运动记录")
            } else {
                let recent = Array(activities.filter { $0.date >= startDay }.prefix(6))
                ForEach(recent, id: \.objectID) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.kindValue.symbol)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(Theme.accent)
                            .frame(width: 26)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.displayTitle)
                                .font(.subheadline)
                            Text(Fmt.relativeDay(entry.date))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer(minLength: 4)

                        Text("-\(Fmt.kcal(entry.kcal)) 千卡")
                            .font(Theme.number(15))
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            sectionHeader("运动消耗", symbol: "figure.walk")
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.secondary)
    }

    private struct DayValue: Identifiable {
        let day: Date
        let value: Double
        var id: Date { day }
    }

    /// GitHub 式记录热力网格：列=周、行=星期，格子颜色按当天摄入占目标的比例取强调色深浅。
    private struct RecordHeatmap: View {
        let days: [DayValue]
        let target: Double?

        /// 把一天折算成 0–4 的热度档位：0 没记录，1–4 越吃越深。
        private func level(for value: Double) -> Int {
            guard value > 0 else { return 0 }
            guard let target = target, target > 0 else { return 2 }
            let ratio = value / target
            if ratio < 0.5 { return 1 }
            if ratio < 0.85 { return 2 }
            if ratio <= 1.1 { return 3 }
            return 4
        }

        /// 档位配色：只用强调色透明度表达深浅，空白走中性轨道灰。
        static func color(for level: Int) -> Color {
            switch level {
            case 1: return Theme.accent.opacity(0.28)
            case 2: return Theme.accent.opacity(0.48)
            case 3: return Theme.accent.opacity(0.72)
            case 4: return Theme.accent
            default: return Color(.systemGray5)
            }
        }

        /// 周列视图数据：每列是该周日一到日（按系统首日）的 7 格，空缺为 nil。
        private var columns: [[DayValue?]] {
            let calendar = Calendar.current
            // 按日期定位周偏移，缺日自动留空，不再依赖「连续日子」假设。
            var byWeek: [Int: [DayValue?]] = [:]
            let base = calendar.dateInterval(of: .weekOfYear, for: calendar.startOfDay(for: Date())).map {
                calendar.startOfDay(for: $0.start)
            } ?? Date()
            for day in days {
                let start = calendar.startOfDay(for: day.day)
                let weekOffset = calendar.dateComponents([.weekOfYear], from: base, to: start).weekOfYear ?? 0
                let slot = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
                byWeek[weekOffset, default: Array(repeating: nil, count: 7)][slot] = day
            }
            let maxWeek = byWeek.keys.max() ?? 0
            let minWeek = min(0, byWeek.keys.min() ?? 0)
            return (minWeek...maxWeek).map { byWeek[$0] ?? Array(repeating: nil, count: 7) }
        }

        var body: some View {
            let cols = max(columns.count, 1)
            let gap: CGFloat = 3
            // 行宽交给布局系统量，别用写死的 330——在不同屏宽的 List 行里会溢出错位。
            GeometryReader { geo in
                let size = max(10, min(22, (geo.size.width - CGFloat(cols - 1) * gap) / CGFloat(cols)))
                HStack(alignment: .top, spacing: gap) {
                    ForEach(columns.indices, id: \.self) { c in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { r in
                                let cell = columns[c][r]
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(cell == nil ? Color.clear : RecordHeatmap.color(for: level(for: cell!.value)))
                                    .frame(width: size, height: size)
                                    .opacity(cell == nil ? 0 : 1)
                                    .scaleEffect(cell == nil ? 0.5 : 1)
                                    .animation(.spring(response: 0.35, dampingFraction: 0.75)
                                        .delay(Double(c * 7 + r) * 0.01), value: cell?.value)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 7 * 22 + 6 * 3)
        }
    }
}
