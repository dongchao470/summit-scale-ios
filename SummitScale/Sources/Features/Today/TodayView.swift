import Charts
import CoreData
import SwiftUI

/// 今日页：热量账本 + 体重 + 当天吃喝与运动。
struct TodayView: View {
    @FetchRequest(sortDescriptors: WeightEntry.dateDescending, animation: .default)
    private var weights: FetchedResults<WeightEntry>

    @FetchRequest(sortDescriptors: FoodEntry.dateDescending, animation: .default)
    private var foods: FetchedResults<FoodEntry>

    @FetchRequest(sortDescriptors: ActivityEntry.dateDescending, animation: .default)
    private var activities: FetchedResults<ActivityEntry>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)], animation: .default)
    private var profiles: FetchedResults<UserProfile>

    @State private var showWeightSheet = false
    @State private var showFoodSheet = false
    @State private var showActivitySheet = false
    @State private var showProfileSheet = false

    private var profile: UserProfile? { profiles.first }
    private var latestWeight: WeightEntry? { weights.first }
    private var bodyKilograms: Double {
        latestWeight?.kilograms ?? profile?.startWeightKilograms ?? 60
    }

    private var ledger: DayLedger? {
        guard let profile = profile,
              let budget = Persistence.shared.calorieBudget(for: profile, currentKilograms: latestWeight?.kilograms)
        else { return nil }
        return DayLedger(budget: budget, intakeKcal: intakeToday, burnKcal: burnToday)
    }

    private var todayFoods: [FoodEntry] {
        let start = Fmt.startOfDay(Date())
        return foods.filter { $0.date >= start }
    }

    private var todayActivities: [ActivityEntry] {
        let start = Fmt.startOfDay(Date())
        return activities.filter { $0.date >= start }
    }

    private var intakeToday: Double { todayFoods.reduce(0) { $0 + $1.kcal } }
    private var burnToday: Double { todayActivities.reduce(0) { $0 + $1.kcal } }

    private var weightDelta: Double? {
        guard let latest = weights.first, let previous = weights.dropFirst().first else { return nil }
        return latest.kilograms - previous.kilograms
    }

    var body: some View {
        NavigationStack {
            List {
                if let ledger = ledger {
                    budgetSection(ledger)
                } else {
                    profilePrompt
                }
                weightSection
                foodSection
                activitySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("今日")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showFoodSheet = true } label: {
                            Label("记饮食", systemImage: "fork.knife")
                        }
                        Button { showActivitySheet = true } label: {
                            Label("记运动", systemImage: "figure.hiking")
                        }
                        Button { showWeightSheet = true } label: {
                            Label("记体重", systemImage: "scalemass")
                        }
                        Button { showProfileSheet = true } label: {
                            Label("改档案", systemImage: "person.crop.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增记录")
                }
            }
            .sheet(isPresented: $showFoodSheet) {
                AddFoodSheet(defaultMeal: AddFoodSheet.suggestedMeal())
            }
            .sheet(isPresented: $showActivitySheet) {
                ActivityEditorView(bodyKilograms: bodyKilograms)
            }
            .sheet(isPresented: $showWeightSheet) {
                AddWeightSheet(defaultKilograms: bodyKilograms)
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileEditorView()
            }
        }
    }

    // MARK: - 热量

    @ViewBuilder
    private func budgetSection(_ ledger: DayLedger) -> some View {
        Section {
            CalorieRingView(ledger: ledger)

            HStack(spacing: 8) {
                MetricTile(title: "缺口", value: Fmt.kcal(ledger.actualDeficit), unit: "kcal")
                MetricTile(title: "基础代谢", value: Fmt.kcal(ledger.budget.bmr), unit: "kcal")
                MetricTile(title: "总消耗", value: Fmt.kcal(ledger.budget.tdee), unit: "kcal")
            }
            .padding(.vertical, 4)
        } header: {
            Text("热量账本")
        } footer: {
            if let name = profile?.name, !name.isEmpty {
                Text("\(name)，按你的身体数据估算，仅供参考，不作为医疗建议。")
            } else {
                Text("按你的身体数据估算，仅供参考，不作为医疗建议。")
            }
        }
    }

    @ViewBuilder
    private var profilePrompt: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("还缺身体数据")
                    .font(.body.weight(.semibold))
                Text("填上身高、体重和目标，才能算出你一天该吃多少。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Button("现在补上") { showProfileSheet = true }
                    .font(.footnote.weight(.semibold))
                    .padding(.top, 2)
            }
            .padding(.vertical, 4)
        } header: {
            Text("热量账本")
        }
    }

    // MARK: - 体重

    @ViewBuilder
    private var weightSection: some View {
        Section("体重") {
            if let latest = latestWeight {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.kg(latest.kilograms))
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                    Text("kg")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let delta = weightDelta {
                        deltaBadge(delta)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)

                Text("最近一次 · \(Fmt.relativeDay(latest.date))")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                if trendPoints.count >= 2 {
                    Chart(trendPoints, id: \.objectID) { entry in
                        LineMark(
                            x: .value("日期", entry.date),
                            y: .value("体重", entry.kilograms)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.accentColor)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 84)
                    .accessibilityLabel("最近 30 天体重趋势")
                }
            } else {
                Text("还没有体重记录，点右上角加号开始。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var trendPoints: [WeightEntry] {
        let cutoff = Fmt.daysAgo(30)
        return Array(weights.filter { $0.date >= cutoff }.reversed())
    }

    // MARK: - 饮食

    @ViewBuilder
    private var foodSection: some View {
        Section {
            if todayFoods.isEmpty {
                Text("今天还没记吃的。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(todayFoods) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                            Text("\(entry.mealValue.title) · \(Fmt.grams(entry.grams)) g")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(Fmt.kcal(entry.kcal))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
                .onDelete { offsets in
                    for index in offsets {
                        Persistence.shared.delete(todayFoods[index])
                    }
                }

                HStack {
                    Text("合计")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Fmt.kcal(intakeToday)) kcal")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                }
            }
        } header: {
            Text("今日饮食")
        }
    }

    // MARK: - 运动

    @ViewBuilder
    private var activitySection: some View {
        Section {
            if todayActivities.isEmpty {
                Text("今天还没记运动。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(todayActivities) { entry in
                    HStack {
                        Label(entry.displayTitle, systemImage: entry.kindValue.symbol)
                            .labelStyle(.titleAndIcon)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Fmt.minutes(entry.durationMinutes))
                                .font(.footnote.weight(.medium))
                                .monospacedDigit()
                            if entry.kcal > 0 {
                                Text("-\(Fmt.kcal(entry.kcal)) kcal")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                .onDelete { offsets in
                    for index in offsets {
                        Persistence.shared.delete(todayActivities[index])
                    }
                }
            }
        } header: {
            Text("今日运动")
        }
    }

    private func deltaBadge(_ delta: Double) -> some View {
        let color: Color
        let symbol: String
        if delta > 0.05 {
            color = .orange
            symbol = "arrow.up.right"
        } else if delta < -0.05 {
            color = .green
            symbol = "arrow.down.right"
        } else {
            color = .secondary
            symbol = "equal"
        }

        return HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
            Text("\(Fmt.signedKg(delta)) kg")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityLabel("较上次变化 \(Fmt.signedKg(delta)) 公斤")
    }
}
