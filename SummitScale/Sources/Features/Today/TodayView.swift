import CoreData
import SwiftUI

/// 今日页：热量账本、三大营养素、体重目标、今天的吃喝与运动。
///
/// 布局按 ui-ux-pro-max 的规则：一张卡只讲一件事，卡片间距统一 14pt，
/// 大号数字用等宽圆体，扫一眼就能做比较。
struct TodayView: View {
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

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "sortIndex", ascending: true)],
        animation: .default
    )
    private var templates: FetchedResults<MealTemplate>

    @State private var showFoodSheet = false
    @State private var showActivitySheet = false
    @State private var showProfileSheet = false
    @State private var presetMeal: MealType?
    @State private var filledMessage: String?

    // MARK: - 派生数据

    private var profile: UserProfile? { profiles.first }

    private var latestWeight: WeightEntry? { weights.first }

    private var budget: CalorieBudget? {
        guard let profile = profile, profile.isComplete else { return nil }
        return Persistence.shared.calorieBudget(for: profile, currentKilograms: latestWeight?.kilograms)
    }

    private var todayStart: Date { Calendar.current.startOfDay(for: Date()) }

    private var todayFoods: [FoodEntry] {
        foods.filter { $0.date >= todayStart }
    }

    private var todayActivities: [ActivityEntry] {
        activities.filter { $0.date >= todayStart }
    }

    private var ledger: DayLedger? {
        guard let budget = budget else { return nil }
        return DayLedger(
            budget: budget,
            intakeKcal: todayFoods.reduce(0) { $0 + $1.kcal },
            burnKcal: todayActivities.reduce(0) { $0 + $1.kcal }
        )
    }

    private var macroTotals: (protein: Double, carbs: Double, fat: Double) {
        var totals = (protein: 0.0, carbs: 0.0, fat: 0.0)
        for entry in todayFoods {
            totals.protein += entry.protein
            totals.carbs += entry.carbs
            totals.fat += entry.fat
        }
        return totals
    }

    // MARK: - 页面

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.stackSpacing) {
                    if let ledger = ledger {
                        calorieCard(ledger)
                        macroCard(ledger.budget)
                    } else {
                        profilePromptCard
                    }
                    weightCard
                    foodCard
                    activityCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
            .background(Theme.pageBackground)
            .navigationTitle("今日")
            .sheet(isPresented: $showFoodSheet) {
                AddFoodSheet(defaultMeal: presetMeal ?? .current)
                    .onDisappear { presetMeal = nil }
            }
            .sheet(isPresented: $showActivitySheet) {
                ActivityEditorView(bodyKilograms: latestWeight?.kilograms ?? profile?.startWeightKilograms ?? 60)
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileEditorView()
            }
            .alert("已加入今日", isPresented: Binding(
                get: { filledMessage != nil },
                set: { if !$0 { filledMessage = nil } }
            )) {
                Button("好", role: .cancel) { filledMessage = nil }
            } message: {
                Text(filledMessage ?? "")
            }
        }
    }

    // MARK: - 热量卡

    private func calorieCard(_ ledger: DayLedger) -> some View {
        VStack(spacing: 16) {
            CalorieRingView(ledger: ledger)

            HStack(spacing: 8) {
                StatTile(
                    title: "已摄入",
                    value: Fmt.kcal(ledger.intakeKcal),
                    unit: "kcal",
                    tint: Theme.accent,
                    symbol: "fork.knife"
                )
                StatTile(
                    title: "预算",
                    value: Fmt.kcal(ledger.budget.intakeTarget),
                    unit: "kcal",
                    tint: .primary,
                    symbol: "target"
                )
                StatTile(
                    title: ledger.isOverBudget ? "超出" : "还能吃",
                    value: Fmt.kcal(abs(ledger.remainingKcal)),
                    unit: "kcal",
                    tint: ledger.isOverBudget ? Theme.warning : Theme.success,
                    symbol: ledger.isOverBudget ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
            }
        }
        .card()
    }

    // MARK: - 营养素卡

    private func macroCard(_ budget: CalorieBudget) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(text: "三大营养素", symbol: "chart.bar.xaxis")
            MacroPanel(
                protein: macroTotals.protein,
                carbs: macroTotals.carbs,
                fat: macroTotals.fat,
                budget: budget
            )
        }
        .card()
    }

    // MARK: - 档案缺失

    private var profilePromptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "先补一份档案", symbol: "person.crop.circle.badge.questionmark")
            Text("身高、体重、年龄、目标填一下，这里才会出现热量环和营养素目标。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showProfileSheet = true
            } label: {
                Label("去填档案", systemImage: "arrow.right.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: Theme.minTouch)
                    .background(Theme.accent)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .card()
    }

    // MARK: - 体重卡

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle(text: "体重", symbol: "figure.stand")
                Spacer()
                if let latest = latestWeight {
                    Text(dayLabel(latest.date))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if let latest = latestWeight, let profile = profile, profile.isComplete {
                GoalProgressBar(
                    current: latest.kilograms,
                    start: profile.startWeightKilograms,
                    target: profile.targetWeightKilograms
                )
            } else if let profile = profile, profile.isComplete {
                Text("还没有体重记录。右下角的加号 → 记体重。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                Text("档案填完就能看体重进度。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if let delta = weightDelta {
                Label(
                    "比上次\(delta <= 0 ? "少" : "多") \(Fmt.kg(abs(delta))) kg",
                    systemImage: delta <= 0 ? "arrow.down.right" : "arrow.up.right"
                )
                .font(.caption)
                .foregroundColor(delta <= 0 ? Theme.success : Theme.warning)
            }
        }
        .card()
    }

    private var weightDelta: Double? {
        guard weights.count >= 2 else { return nil }
        return weights[0].kilograms - weights[1].kilograms
    }

    // MARK: - 饮食卡

    private var foodCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardTitle(text: "今天吃了什么", symbol: "fork.knife.circle")
                Spacer()
                Button {
                    presetMeal = nil
                    showFoodSheet = true
                } label: {
                    Label("加一条", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 32)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }

            ForEach(MealType.allCases) { meal in
                mealSection(meal)
            }
        }
        .card()
    }

    @ViewBuilder
    private func mealSection(_ meal: MealType) -> some View {
        let entries = todayFoods.filter { $0.mealValue == meal }
        let kcal = entries.reduce(0) { $0 + $1.kcal }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: meal.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Theme.accent)
                    .accessibilityHidden(true)
                Text(meal.title)
                    .font(.subheadline.weight(.semibold))
                Text(Fmt.kcal(kcal) + " kcal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Spacer()

                if let template = templates.first(where: { $0.meal == meal }) {
                    Button {
                        applyTemplate(template)
                    } label: {
                        Label(template.name, systemImage: "wand.and.stars")
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: 28)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                    .accessibilityLabel("一键加入套餐 \(template.name)")
                }

                Button {
                    presetMeal = meal
                    showFoodSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.accent)
                .accessibilityLabel("往\(meal.title)加食物")
            }

            if entries.isEmpty {
                Text("还没有记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 26)
            } else {
                ForEach(entries) { entry in
                    foodRow(entry)
                }
            }
        }
    }

    private func foodRow(_ entry: FoodEntry) -> some View {
        HStack(spacing: 10) {
            FoodThumbnail(urlString: entry.imageURL, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(Fmt.grams(entry.grams)) g·蛋白 \(Fmt.grams(entry.protein)) / 碳水 \(Fmt.grams(entry.carbs)) / 脂肪 \(Fmt.grams(entry.fat))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(Fmt.kcal(entry.kcal))
                .font(Theme.number(15, weight: .semibold))
                .foregroundColor(.primary)

            Menu {
                Button(role: .destructive) {
                    Persistence.shared.delete(entry)
                } label: {
                    Label("删除这条", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.footnote)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(entry.name) 的更多操作")
        }
        .padding(.leading, 26)
    }

    // MARK: - 运动卡

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle(text: "今天动了多少", symbol: "figure.hiking")
                Spacer()
                Button {
                    showActivitySheet = true
                } label: {
                    Label("加一条", systemImage: "plus")
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 32)
                }
                .buttonStyle(.bordered)
                .tint(Theme.success)
            }

            if todayActivities.isEmpty {
                Text("还没有运动记录。爬山、跑步、走路都算。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 8) {
                    StatTile(
                        title: "消耗",
                        value: Fmt.kcal(ledger?.burnKcal ?? 0),
                        unit: "kcal",
                        tint: Theme.success,
                        symbol: "flame.fill"
                    )
                    StatTile(
                        title: "条数",
                        value: "\(todayActivities.count)",
                        unit: "条",
                        tint: .primary,
                        symbol: "list.bullet"
                    )
                    StatTile(
                        title: "里程",
                        value: Fmt.kg(todayActivities.reduce(0) { $0 + $1.distanceKilometers }),
                        unit: "km",
                        tint: .primary,
                        symbol: "point.topleft.down.curvedto.point.bottomright.up"
                    )
                }

                ForEach(todayActivities) { activity in
                    HStack(spacing: 10) {
                        Image(systemName: activity.kindValue.symbol)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(Theme.success)
                            .frame(width: 22)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.displayTitle)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(activitySubtitle(activity))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        Text(Fmt.kcal(activity.kcal))
                            .font(Theme.number(15, weight: .semibold))

                        Menu {
                            Button(role: .destructive) {
                                Persistence.shared.delete(activity)
                            } label: {
                                Label("删除这条", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.footnote)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("\(activity.displayTitle) 的更多操作")
                    }
                }
            }
        }
        .card()
    }

    private func activitySubtitle(_ activity: ActivityEntry) -> String {
        var parts: [String] = []
        if activity.durationMinutes > 0 {
            parts.append("\(Int(activity.durationMinutes)) 分钟")
        }
        if activity.distanceKilometers > 0 {
            parts.append("\(Fmt.kg(activity.distanceKilometers)) 公里")
        }
        if activity.elevationGainMeters > 0 {
            parts.append("爬升 \(Int(activity.elevationGainMeters)) 米")
        }
        return parts.isEmpty ? activity.kindValue.title : parts.joined(separator: " · ")
    }

    // MARK: - 动作

    private func applyTemplate(_ template: MealTemplate) {
        let count = Persistence.shared.applyTemplate(template, to: Date())
        filledMessage = count > 0
            ? "「\(template.name)」的 \(count) 条已经记进今天。"
            : "这个套餐是空的，先去「我的 → 套餐」里加点东西。"
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}
