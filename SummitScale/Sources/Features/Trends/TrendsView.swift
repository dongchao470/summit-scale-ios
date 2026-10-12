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
    /// 健康提供的昨晚睡眠时长（小时），未启用为 nil。
    @State private var sleepHours: Double?
    /// 健康提供的每日步数（含今天），未启用为空；供体重×步数叠图。
    @State private var dailyStepPoints: [DayValue] = []
    /// 健康提供的每日活跃消耗（kcal，含日常活动），未启用为空数组；供运动消耗趋势柱。
    @State private var healthBurnPoints: [DayValue] = []
    /// 记录热度中被点选的那一天，nil 表示未展开详情卡。
    @State private var selectedHeatmapDay: DayValue?
    /// 健康提供的近 N 天睡眠分期（深/浅/REM），未启用或无数据为空。
    @State private var sleepStageDays: [HealthKitManager.SleepStageDay] = []
    /// 昨晚睡眠期间的平均 / 最低心率（bpm），未读到为 nil。
    @State private var sleepHeartAverage: Double?
    @State private var sleepHeartLowest: Double?
    /// 健康提供的每日心率（只含有数据的日子，日升序），未启用或无数据为空；供心率区块。
    @State private var heartRatePoints: [HeartRateDay] = []

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

    /// 区间内总消耗：有健康数据就用健康口径（含日常活动），否则用运动记录合计。
    private var totalBurn: Double {
        if !healthBurnPoints.isEmpty {
            return healthBurnPoints.reduce(0) { $0 + $1.value }
        }
        return activities.filter { $0.date >= startDay }.reduce(0) { $0 + $1.kcal }
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

    /// 区间内有步数记录的日子（去掉 0）。
    private var stepsLogged: [Double] {
        dailyStepPoints.map { $0.value }.filter { $0 > 0 }
    }

    /// 把步数线性映射到体重域下半部，作为体重曲线背后的强弱柱。
    private func stepBarY(_ steps: Double) -> Double {
        guard let maxSteps = dailyStepPoints.map({ $0.value }).max(), maxSteps > 0 else {
            return weightDomain.lowerBound
        }
        let lo = weightDomain.lowerBound
        let span = weightDomain.upperBound - lo
        return lo + (steps / maxSteps) * span * 0.5
    }

    /// 体重×步数解读：这段时间体重方向 + 日均步数。
    private var trendInsight: String? {
        guard let change = weightChange, !stepsLogged.isEmpty else { return nil }
        let avg = Int((stepsLogged.reduce(0, +) / Double(stepsLogged.count)).rounded())
        let dir = change <= 0 ? "↓ \(Fmt.kg(abs(change))) kg" : "↑ \(Fmt.kg(change)) kg"
        return "这段时间体重 \(dir)，日均 \(avg.formatted()) 步。"
    }

    private var calorieDomain: ClosedRange<Double> {
        let peak = max(dailyIntake.map { $0.value }.max() ?? 0, budget?.intakeTarget ?? 0)
        return 0...(max(peak * 1.15, 500))
    }

    // MARK: - 睡眠派生数据

    /// 读健康睡眠分期 + 夜间心率，span 变化或页面出现时调用。
    private func loadSleep(days: Int) {
        HealthKitManager.shared.dailySleepStages(days: days) { stages in
            sleepStageDays = stages
        }
        HealthKitManager.shared.lastNightHeartRate { avg, low in
            sleepHeartAverage = avg
            sleepHeartLowest = low
        }
    }

    /// 健康口径的每日活跃消耗；读不到就是空数组，趋势柱自己退回运动记录口径。
    private func loadHealthBurn(days: Int) {
        HealthKitManager.shared.dailyActiveEnergy(days: days) { points in
            healthBurnPoints = points.map { DayValue(day: $0.day, value: $0.kcal) }
        }
    }

    // MARK: - 心率派生数据

    /// 读健康的每日心率（只返回有数据的天）；无权限或无数据就是空数组，心率区块整体不出现。
    private func loadHeartRate(days: Int) {
        HealthKitManager.shared.dailyHeartRate(days: days) { points in
            heartRatePoints = points
                .filter { $0.average > 0 }
                .map { HeartRateDay(day: $0.day, average: $0.average, maximum: $0.maximum) }
                .sorted { $0.day < $1.day }
        }
    }

    /// 区间内平均心率再平均，只按有数据的日子算；没数据为 0。
    private var averageHeartBpm: Double {
        guard !heartRatePoints.isEmpty else { return 0 }
        return heartRatePoints.reduce(0) { $0 + $1.average } / Double(heartRatePoints.count)
    }

    /// 心率图的 Y 轴上界：留 20% 余量，至少到 120 bpm，免得曲线贴顶。
    private var heartRateDomain: ClosedRange<Double> {
        let peak = heartRatePoints.map { $0.maximum }.max() ?? 0
        return 0...(max(peak * 1.2, 120))
    }

    /// 有睡眠数据的日子（去掉全 0 的空白夜）。
    private var sleepLoggedDays: [HealthKitManager.SleepStageDay] {
        sleepStageDays.filter { $0.hasData }
    }

    /// 平均每晚总睡眠（小时），只按有数据的夜计算。
    private var averageSleep: Double {
        guard !sleepLoggedDays.isEmpty else { return 0 }
        return sleepLoggedDays.reduce(0) { $0 + $1.total } / Double(sleepLoggedDays.count)
    }

    /// 最近一个有数据的夜晚，用于副文「昨晚 深睡…」。
    private var latestSleepNight: HealthKitManager.SleepStageDay? {
        sleepLoggedDays.last
    }

    /// 睡眠堆叠柱的 Y 轴上界，留 15% 余量，至少 8 小时。
    private var sleepDomain: ClosedRange<Double> {
        let peak = sleepStageDays.map { $0.total }.max() ?? 0
        return 0...(max(peak * 1.15, 8))
    }

    /// 把分期小时数格式化成「X 小时 Y 分」或「Y 分」。
    private func sleepDurationText(_ hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        let h = total / 60
        let m = total % 60
        if h > 0 { return "\(h):\(String(format: "%02d", m))" }
        return "\(m) 分"
    }

    // MARK: - 运动消耗趋势派生数据

    /// 每天运动消耗（kcal），区间内补齐，无记录的日子为 0。供运动趋势柱。
    private var dailyBurn: [DayValue] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var byDay: [Date: Double] = [:]
        for entry in activities where entry.date >= startDay {
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

    /// 图上真正画的那条线：有健康数据就用健康口径，否则退回本地运动记录。
    private var burnSeries: [DayValue] {
        healthBurnPoints.isEmpty ? dailyBurn : healthBurnPoints
    }

    /// 消耗数字的来源，标出来免得看不懂。
    private var burnSourceNote: String {
        healthBurnPoints.isEmpty
            ? "来自你的运动记录"
            : "来自 Apple 健康 · 含日常活动的每日活跃消耗"
    }

    /// 运动消耗日均（只算动过的日子），作柱状图参考虚线。
    private var averageBurnLoggedDay: Double {
        let logged = burnSeries.filter { $0.value > 0 }
        guard !logged.isEmpty else { return 0 }
        return logged.reduce(0) { $0 + $1.value } / Double(logged.count)
    }

    private var burnDomain: ClosedRange<Double> {
        let peak = burnSeries.map { $0.value }.max() ?? 0
        return 0...(max(peak * 1.15, 300))
    }

    private var burnActiveDays: Int { burnSeries.filter { $0.value > 0 }.count }

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
                sleepSection
                heartRateSection
                activitySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("趋势")
            .onAppear {
                HealthKitManager.shared.lastNightSleepHours { sleepHours = $0 }
                HealthKitManager.shared.dailySteps(days: span.days) { points in
                    dailyStepPoints = points.map { DayValue(day: $0.day, value: $0.steps) }
                }
                loadSleep(days: span.days)
                loadHealthBurn(days: span.days)
                loadHeartRate(days: span.days)
                // 顺手把「健康」里的锻炼补进运动记录，列表和趋势才不是空的。
                WorkoutSync.importRecent(days: span.days)
            }
            .onChange(of: span) { newSpan in
                HealthKitManager.shared.dailySteps(days: newSpan.days) { points in
                    dailyStepPoints = points.map { DayValue(day: $0.day, value: $0.steps) }
                }
                loadSleep(days: newSpan.days)
                loadHealthBurn(days: newSpan.days)
                loadHeartRate(days: newSpan.days)
                WorkoutSync.importRecent(days: newSpan.days)
            }
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

    /// 昨晚睡眠行：只在健康接入且读到数据时出现。
    @ViewBuilder
    private var sleepRow: some View {
        if let hours = sleepHours, hours > 0 {
            HStack {
                Label("昨晚睡眠", systemImage: "bed.double")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.1f 小时", hours))
                    .font(.subheadline.weight(.medium).monospacedDigit())
            }
            .accessibilityElement(children: .combine)
        }
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
                RecordHeatmap(
                    days: heatmapIntake,
                    target: budget?.intakeTarget,
                    selectedDay: selectedHeatmapDay?.day,
                    onSelect: { day in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            if selectedHeatmapDay?.day == day.day {
                                selectedHeatmapDay = nil
                            } else {
                                selectedHeatmapDay = day
                            }
                        }
                    }
                )

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

                if let selected = selectedHeatmapDay {
                    heatmapDetailCard(for: selected)
                        .transition(.opacity.combined(with: .move(edge: .top)))
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

    /// 热度格点选后的当天详情卡：日期 + 档位标签 + 摄入占比 + 记录条数 +（有则）体重。
    private func heatmapDetailCard(for item: DayValue) -> some View {
        let target = budget?.intakeTarget
        let (tag, dot) = heatmapTag(value: item.value, target: target)
        let count = recordCount(on: item.day)
        let kg = weight(on: item.day)
        let hasIntake = item.value > 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.heatmapDayFormatter.string(from: item.day))
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(dot).frame(width: 7, height: 7)
                    Text(tag).font(.caption).foregroundColor(.secondary)
                }
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        selectedHeatmapDay = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body).foregroundColor(Color(.systemGray3))
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
            .padding(.bottom, 8)
            Divider()
            VStack(spacing: 8) {
                if hasIntake {
                    heatmapDetailRow(title: "摄入", value: "\(Int(item.value.rounded())) kcal",
                                     sub: target.map { "占目标 \(Int((item.value / $0 * 100).rounded()))%" })
                    heatmapDetailRow(title: "记录", value: "\(count) 条", sub: nil)
                } else {
                    HStack {
                        Text("这天没有饮食记录")
                            .font(.footnote).foregroundColor(.secondary)
                        Spacer()
                    }
                }
                if let kg = kg {
                    heatmapDetailRow(title: "体重", value: "\(Fmt.kg(kg)) kg", sub: nil)
                }
            }
            .padding(.top, 8)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.tertiarySystemGroupedBackground)))
    }

    private func heatmapDetailRow(title: String, value: String, sub: String?) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.subheadline).foregroundColor(.secondary)
            Spacer()
            if let sub = sub {
                Text(sub).font(.caption).foregroundColor(.secondary)
            }
            Text(value).font(.subheadline).fontWeight(.semibold).monospacedDigit()
        }
    }

    /// 和热力图同一套比例逻辑，但给人看的文案与标签圆点色。
    private func heatmapTag(value: Double, target: Double?) -> (String, Color) {
        guard value > 0 else { return ("未记录", Color(.systemGray3)) }
        guard let t = target, t > 0 else { return ("已记录", Theme.accent) }
        let r = value / t
        if r < 0.5 { return ("吃得少", Theme.accent.opacity(0.4)) }
        if r < 0.85 { return ("偏少", Theme.accent.opacity(0.65)) }
        if r <= 1.1 { return ("达标", Theme.accent) }
        return ("偏多", Theme.accent)
    }

    /// 当天记录了几条饮食。
    private func recordCount(on day: Date) -> Int {
        let cal = Calendar.current
        return foods.filter { cal.isDate($0.date, inSameDayAs: day) }.count
    }

    /// 当天体重（最新一次称重），没有则 nil。weights 已按日期倒序。
    private func weight(on day: Date) -> Double? {
        let cal = Calendar.current
        return weights.first { cal.isDate($0.date, inSameDayAs: day) }?.kilograms
    }

    private static let heatmapDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.setLocalizedDateFormatFromTemplate("MMMdEEEE")
        return f
    }()

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

    @ViewBuilder
    private var weightSection: some View {
        Section {
            if weightPoints.count < 2 {
                emptyHint("这段区间至少记两次体重，曲线才画得出来")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Chart {
                        // 每日步数作体重曲线背后的强弱柱（映射到体重域下半部，仅示相对高低）。
                        ForEach(dailyStepPoints) { point in
                            if point.value > 0 {
                                BarMark(
                                    x: .value("日期", point.day),
                                    yStart: .value("基线", weightDomain.lowerBound),
                                    yEnd: .value("步数", stepBarY(point.value))
                                )
                                .foregroundStyle(Theme.accent.opacity(0.16))
                                .cornerRadius(3)
                            }
                        }

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

                    HStack(spacing: 16) {
                        HStack(spacing: 5) {
                            Capsule()
                                .fill(Theme.accent)
                                .frame(width: 14, height: 3)
                            Text("体重 kg")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.accent.opacity(0.16))
                                .frame(width: 10, height: 10)
                            Text("每日步数")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .accessibilityHidden(true)

                    if let insight = trendInsight {
                        Text(insight)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
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

    // MARK: - 睡眠结构（方案 C：深/浅/REM 堆叠柱）

    @ViewBuilder
    private var sleepSection: some View {
        if !sleepLoggedDays.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(sleepDurationText(averageSleep))
                            .font(Theme.number(34))
                        Text("平均每晚")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Chart {
                        ForEach(sleepStageDays, id: \.day) { day in
                            BarMark(x: .value("日期", day.day), y: .value("深睡", day.deep))
                                .foregroundStyle(Theme.accent)
                                .cornerRadius(2)
                            BarMark(x: .value("日期", day.day), y: .value("浅睡", day.core))
                                .foregroundStyle(Theme.accent.opacity(0.5))
                                .cornerRadius(2)
                            BarMark(x: .value("日期", day.day), y: .value("REM", day.rem))
                                .foregroundStyle(Theme.accent.opacity(0.26))
                                .cornerRadius(2)
                        }
                    }
                    .chartYScale(domain: sleepDomain)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: span == .week ? 7 : 4)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .frame(height: 170)

                    HStack(spacing: 16) {
                        sleepLegend("深睡", Theme.accent)
                        sleepLegend("浅睡", Theme.accent.opacity(0.5))
                        sleepLegend("REM", Theme.accent.opacity(0.26))
                    }

                    if let night = latestSleepNight {
                        Text(sleepNightSummary(night))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let avg = sleepHeartAverage {
                        HStack(spacing: 6) {
                            Image(systemName: "heart")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(Theme.accent)
                                .accessibilityHidden(true)
                            if let low = sleepHeartLowest {
                                Text("夜间心率 平均 \(Int(avg.rounded())) · 最低 \(Int(low.rounded())) bpm")
                            } else {
                                Text("夜间心率 平均 \(Int(avg.rounded())) bpm")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                sectionHeader("睡眠结构", symbol: "bed.double")
            }
        }
    }

    /// 睡眠图例小圆点 + 文字。
    private func sleepLegend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    /// 最近一夜分期副文：昨晚 深睡 X · 浅睡 Y · REM Z。
    private func sleepNightSummary(_ night: HealthKitManager.SleepStageDay) -> String {
        "昨晚 \(sleepDurationText(night.total)) · 深睡 \(sleepDurationText(night.deep)) · 浅睡 \(sleepDurationText(night.core)) · REM \(sleepDurationText(night.rem))"
    }

    // MARK: - 心率（每日平均主线 + 最高参考）

    /// 心率区块：主线是按天平均心率，淡强调色柱是当天最高；整个时间窗无心率数据时整块不出现。
    @ViewBuilder
    private var heartRateSection: some View {
        if !heartRatePoints.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(averageHeartBpm.rounded()))")
                            .font(Theme.number(34))
                        Text("bpm · 日均 · \(heartRatePoints.count) 天有数据")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Chart {
                        ForEach(heartRatePoints) { point in
                            // 最高心率作背景副柱，淡强调色，不抢主线。
                            BarMark(
                                x: .value("日期", point.day),
                                y: .value("最高", point.maximum)
                            )
                            .foregroundStyle(Theme.accent.opacity(0.24))
                            .cornerRadius(4)

                            LineMark(
                                x: .value("日期", point.day),
                                y: .value("平均", point.average)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Theme.accent)

                            PointMark(
                                x: .value("日期", point.day),
                                y: .value("平均", point.average)
                            )
                            .foregroundStyle(Theme.accent)
                            .symbolSize(26)
                        }
                    }
                    .chartYScale(domain: heartRateDomain)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: span == .week ? 7 : 4)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .frame(height: 170)

                    HStack(spacing: 16) {
                        HStack(spacing: 5) {
                            Capsule()
                                .fill(Theme.accent)
                                .frame(width: 14, height: 3)
                            Text("平均 bpm")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.accent.opacity(0.24))
                                .frame(width: 10, height: 10)
                            Text("最高 bpm")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .accessibilityHidden(true)

                    if let latest = heartRatePoints.last {
                        Text("最近 \(Fmt.relativeDay(latest.day)) 平均 \(Int(latest.average.rounded())) · 最高 \(Int(latest.maximum.rounded())) bpm")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                sectionHeader("心率", symbol: "heart.fill")
            }
        }
    }

    private var activitySection: some View {
        Section {
            if healthBurnPoints.isEmpty && activities.filter({ $0.date >= startDay }).isEmpty {
                emptyHint("这段时间还没有运动数据")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Fmt.kcal(totalBurn))
                            .font(Theme.number(30))
                        Text("千卡 · \(burnActiveDays) 天有消耗")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(burnSourceNote)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Chart {
                        ForEach(burnSeries) { item in
                            BarMark(
                                x: .value("日期", item.day),
                                y: .value("消耗", item.value)
                            )
                            .foregroundStyle(Theme.accent.opacity(0.85))
                            .cornerRadius(4)
                        }

                        if averageBurnLoggedDay > 0 {
                            RuleMark(y: .value("日均", averageBurnLoggedDay))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .chartYScale(domain: burnDomain)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: span == .week ? 7 : 4)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .frame(height: 150)
                }
                .padding(.vertical, 4)

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
                            HStack(spacing: 4) {
                                Text(Fmt.relativeDay(entry.date))
                                if entry.source == WorkoutSync.source {
                                    Text("健康")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(Theme.accent)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Theme.accent.opacity(0.15)))
                                }
                            }
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

    /// 一天的心率（bpm）：平均作主线，最高作背景参考。
    private struct HeartRateDay: Identifiable {
        let day: Date
        let average: Double
        let maximum: Double
        var id: Date { day }
    }

    /// GitHub 式记录热力网格：列=周、行=星期，格子颜色按当天摄入占目标的比例取强调色深浅。
    private struct RecordHeatmap: View {
        let days: [DayValue]
        let target: Double?
        var selectedDay: Date? = nil
        var onSelect: ((DayValue) -> Void)? = nil

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

        /// 当前格是否为被点选的那一天。
        private func isSelected(_ cell: DayValue?) -> Bool {
            guard let cell = cell, let selectedDay = selectedDay else { return false }
            return Calendar.current.isDate(cell.day, inSameDayAs: selectedDay)
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
                                let selected = isSelected(cell)
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(cell == nil ? Color.clear : RecordHeatmap.color(for: level(for: cell!.value)))
                                    .frame(width: size, height: size)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .strokeBorder(Color.primary, lineWidth: selected ? 1.5 : 0)
                                    )
                                    .opacity(cell == nil ? 0 : 1)
                                    .scaleEffect(cell == nil ? 0.5 : (selected ? 1.18 : 1))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if let cell = cell { onSelect?(cell) }
                                    }
                                    .animation(.spring(response: 0.35, dampingFraction: 0.75)
                                        .delay(Double(c * 7 + r) * 0.01), value: cell?.value)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
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
