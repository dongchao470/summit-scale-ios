import CoreData
import SwiftUI

/// 今日页：热量账本、三大营养素、体重目标、今天的吃喝与运动。
///
/// 布局按 ui-ux-pro-max 的规则：一张卡只讲一件事，卡片间距统一 14pt，
/// 大号数字用等宽圆体，扫一眼就能做比较。
struct TodayView: View {
    @FetchRequest(sortDescriptors: WeightEntry.dateDescending, animation: .default)
    private var weights: FetchedResults<WeightEntry>

    // 不加 animation：带动画删除时 List 会在淡出帧里继续渲染已删除的 FoodEntry，
    // 访问它的 @NSManaged 非可选属性会触发 Core Data fault 直接崩。无动画即刻移除最稳。
    @FetchRequest(sortDescriptors: FoodEntry.dateDescending)
    private var foods: FetchedResults<FoodEntry>

    @FetchRequest(sortDescriptors: ActivityEntry.dateDescending)
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
    @State private var showWeightSheet = false
    @State private var showProfileSheet = false
    @State private var presetMeal: MealType?
    /// 「补记昨天」打开记饮食时用的日期；普通新增保持 nil，走今天。
    @State private var presetDate: Date?
    /// 正在改的那一条；非空就弹编辑页。
    @State private var editingFood: FoodEntry?
    /// 提醒里选了「改完再记」的套餐；非空就弹摊开编辑页。
    @State private var editingTemplate: MealTemplate?
    @State private var pendingTemplate: MealTemplate?
    @State private var filledMessage: String?
    /// 已经展开明细的套餐组；键是 `template:<套餐UUID>`。
    @State private var expandedGroups: Set<String> = []
    /// 顶部热量环的绘制动画开关，onAppear 置 true，由 0 扫到当前百分比。
    @State private var ringAnimate = false
    /// 健康提供的今日步数/锻炼消耗（kcal），未启用为 0。
    @State private var healthBurnKcal: Double = 0
    /// 健康推送的最新体重；非 nil 时展示并提醒是否替换当前记录。
    @State private var healthWeightKg: Double?
    /// 健康今日活动明细（步数/锻炼消耗/锻炼时长），未启用时为空。
    @State private var healthActivity = HealthKitManager.TodayActivity()
    /// 健康读到的昨夜睡眠时长（小时），未读到为 nil。
    @State private var healthSleepHours: Double?

    private var healthBurn: Double {
        healthBurnKcal
    }

    /// 从健康读今日活动消耗；未授权/未开启时回调 0，UI 不展示。
    private func refreshHealthData() {
        HealthKitManager.shared.todayActivityKcal { kcal in
            healthBurnKcal = kcal
        }
        HealthKitManager.shared.todayActivityDetail { healthActivity = $0 }
        HealthKitManager.shared.lastNightSleepHours { healthSleepHours = $0 }
    }

    // MARK: - A2 今日活动明细卡（来自 Apple 健康）

    private var healthStepSubtitle: String? {
        let kcal = Int(healthActivity.steps * 0.04)
        return kcal > 0 ? "折合约 \(kcal) kcal" : nil
    }

    private var healthExerciseSubtitle: String? {
        let mins = Int(healthActivity.exerciseMinutes.rounded())
        return mins > 0 ? "\(mins) 分钟" : nil
    }

    private func healthMetricRow(symbol: String, tint: Color, title: String, subtitle: String?, value: String, unit: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundColor(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value) \(unit)")
    }

    @ViewBuilder
    private var healthTodayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(text: "今日活动 · 来自 Apple 健康", symbol: "heart.fill")

            VStack(spacing: 0) {
                if healthActivity.steps > 0 {
                    healthMetricRow(
                        symbol: "figure.walk",
                        tint: Theme.accent,
                        title: "步数",
                        subtitle: healthStepSubtitle,
                        value: healthActivity.steps.formatted(.number.precision(.fractionLength(0))),
                        unit: "步"
                    )
                }
                if healthActivity.activeKcal > 0 || healthActivity.exerciseMinutes > 0 {
                    healthMetricRow(
                        symbol: "flame.fill",
                        tint: .orange,
                        title: "锻炼",
                        subtitle: healthExerciseSubtitle,
                        value: Fmt.kcal(healthActivity.activeKcal),
                        unit: "kcal"
                    )
                }
                if let sleep = healthSleepHours {
                    healthMetricRow(
                        symbol: "moon.zzz.fill",
                        tint: .purple,
                        title: "昨夜睡眠",
                        subtitle: nil,
                        value: String(format: "%.1f", sleep),
                        unit: "小时"
                    )
                }
            }
        }
    }

    // MARK: - 派生数据

    private var profile: UserProfile? { profiles.first }

    private var latestWeight: WeightEntry? { weights.first }

    private var budget: CalorieBudget? {
        guard let profile = profile, profile.isComplete else { return nil }
        return Persistence.shared.calorieBudget(for: profile, currentKilograms: latestWeight?.kilograms)
    }

    private var todayStart: Date { Calendar.current.startOfDay(for: Date()) }

    private var todayFoods: [FoodEntry] {
        // 过滤已删除对象：删除瞬间 FetchedResults 还没来得及剔除时，
        // 读取已删 entry 的属性会崩，这里兜一道。
        foods.filter { !$0.isDeleted && $0.date >= todayStart }
    }

    private var todayActivities: [ActivityEntry] {
        activities.filter { !$0.isDeleted && $0.date >= todayStart }
    }

    private var ledger: DayLedger? {
        guard let budget = budget else { return nil }
        return DayLedger(
            budget: budget,
            intakeKcal: todayFoods.reduce(0) { $0 + $1.kcal },
            burnKcal: todayActivities.reduce(0) { $0 + $1.kcal } + healthBurn
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

    /// 顶部问候语：按时间切，后面接用户的显示名。
    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let prefix: String
        switch hour {
        case 5..<11: prefix = "早上好"
        case 11..<13: prefix = "中午好"
        case 13..<18: prefix = "下午好"
        case 18..<23: prefix = "晚上好"
        default: prefix = "夜深了"
        }
        return "\(prefix)，\(profile?.displayName ?? "你")"
    }

    var body: some View {
        NavigationStack {
            // 用系统 List 分组，不再拿 ScrollView 拼一摞手绘卡片：
            // 分组间距、圆角、分隔线、左滑这些交给系统，比手写的好看也好维护。
            List {
                if let ledger = ledger {
                    Section { calorieHeroCard(ledger) }
                } else {
                    Section { profilePromptCard }
                }
                if healthActivity.hasData || healthSleepHours != nil {
                    Section { healthTodayCard }
                }
                Section { weightCard }
                // 吃喝按餐次各占一个分组，餐次名就是分组标题。
                ForEach(MealType.allCases) { meal in
                    mealSection(meal)
                }
                Section { activityCard }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(greetingTitle)
            .onAppear(perform: refreshHealthData)
            .onReceive(NotificationCenter.default.publisher(for: .healthWeightChanged)) { note in
                if let kg = note.userInfo?["kilograms"] as? Double {
                    healthWeightKg = kg
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    recordMenu
                }
            }
            .sheet(isPresented: $showFoodSheet) {
                AddFoodSheet(
                    defaultMeal: presetMeal ?? AddFoodSheet.suggestedMeal(),
                    date: presetDate ?? Date()
                )
                .onDisappear {
                    presetMeal = nil
                    presetDate = nil
                }
            }
            // 改某一条走单独的 sheet，免得和新增抢同一份状态。
            .sheet(item: $editingFood) { entry in
                AddFoodSheet(editing: entry)
            }
            // 套餐「改完再记」：摊开成可编辑清单。
            .sheet(item: $editingTemplate) { template in
                TemplateFillSheet(template: template, date: Date())
            }
            .sheet(isPresented: $showActivitySheet) {
                ActivityEditorView(bodyKilograms: latestWeight?.kilograms ?? profile?.startWeightKilograms ?? 60)
            }
            .sheet(isPresented: $showWeightSheet) {
                AddWeightSheet(defaultKilograms: latestWeight?.kilograms ?? 60)
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileEditorView()
            }
            .confirmationDialog(
                pendingTemplate.map { "把「\($0.name)」记到今天？" } ?? "",
                isPresented: Binding(
                    get: { pendingTemplate != nil },
                    set: { if !$0 { pendingTemplate = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingTemplate
            ) { template in
                Button("记上，约 \(Fmt.kcal(template.totalKcal)) 千卡") {
                    applyTemplate(template)
                    pendingTemplate = nil
                }
                // 想吃少一点，或者换掉两样：摊开来改，只影响这一次。
                Button("改完再记") {
                    editingTemplate = template
                    pendingTemplate = nil
                }
                Button("取消", role: .cancel) { pendingTemplate = nil }
            } message: { template in
                Text(template.items.map(\.name).joined(separator: " + "))
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

    private func calorieHeroCard(_ ledger: DayLedger) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今日已摄入")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Fmt.kcal(ledger.intakeKcal))
                            .font(Theme.number(44, weight: .bold))
                            .foregroundColor(Theme.primaryText)
                        Text("kcal")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    remainingMeta(ledger)
                }
                Spacer(minLength: 0)
                heroRing(ledger)
            }

            Divider()

            MacroPanel(
                protein: macroTotals.protein,
                carbs: macroTotals.carbs,
                fat: macroTotals.fat,
                budget: ledger.budget
            )
        }
        .padding(.vertical, 2)
    }

    /// 目标 + 还可吃/超出 的小字；还可吃用强调色点一下，超出走中性，不用红。
    private func remainingMeta(_ ledger: DayLedger) -> some View {
        let remaining = ledger.remainingKcal
        return HStack(spacing: 4) {
            Text("目标 \(Fmt.kcal(ledger.budget.intakeTarget)) ·")
                .foregroundColor(.secondary)
            if remaining >= 0 {
                Text("还可吃 \(Fmt.kcal(remaining)) kcal")
                    .foregroundColor(Theme.accent)
            } else {
                Text("已超出 \(Fmt.kcal(-remaining)) kcal")
                    .foregroundColor(.secondary)
            }
        }
        .font(.footnote.weight(.medium))
    }

    /// 右侧进度环：中心显示占目标的百分比，只用强调色，超标也封顶在整圈。
    private func heroRing(_ ledger: DayLedger) -> some View {
        let progress = min(1.0, max(0.0, ledger.progress))
        return ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 9)
            Circle()
                .trim(from: 0, to: ringAnimate ? progress : 0)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.1), value: ringAnimate)
            VStack(spacing: 1) {
                Text("\(Int((ledger.progress * 100).rounded()))%")
                    .font(Theme.number(18, weight: .semibold))
                    .foregroundColor(Theme.primaryText)
                Text("目标")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 86, height: 86)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("已摄入占目标 \(Int((ledger.progress * 100).rounded())) 个百分点")
        .onAppear { ringAnimate = true }
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
                    .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            }
        }
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
                .foregroundColor(delta <= 0 ? Theme.accent : .secondary)
            }
        }
    }

    private var weightDelta: Double? {
        guard weights.count >= 2 else { return nil }
        return weights[0].kilograms - weights[1].kilograms
    }

    // MARK: - 记录入口

    /// 「记一条」「补记昨天」「套用套餐」这些低频动作收进右上角菜单，
    /// 不再挤在卡片标题行里抢地方；日常加一条直接点各餐次标题右边的加号。
    private var recordMenu: some View {
        Menu {
            Button {
                presetMeal = nil
                presetDate = nil
                showFoodSheet = true
            } label: {
                Label("记一条饮食", systemImage: "fork.knife")
            }
            // 早上想起昨晚忘了记：一步把日期拨到昨天，省得进页面再改。
            Button {
                presetDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())
                presetMeal = nil
                showFoodSheet = true
            } label: {
                Label("补记昨天", systemImage: "calendar.badge.minus")
            }
            if !templates.isEmpty {
                Section("套用套餐") {
                    ForEach(templates) { template in
                        Button {
                            pendingTemplate = template
                        } label: {
                            Label(template.name, systemImage: "wand.and.stars")
                        }
                    }
                }
            }
            Section {
                Button {
                    showActivitySheet = true
                } label: {
                    Label("记运动", systemImage: "figure.walk")
                }
                Button {
                    showWeightSheet = true
                } label: {
                    Label("记体重", systemImage: "scalemass")
                }
            }
        } label: {
            Image(systemName: "plus.circle.fill")
        }
        .accessibilityLabel("记一笔")
    }

    /// 一个餐次就是一个分组：标题写明餐次和已入账热量，右侧加号按当餐记账。
    @ViewBuilder
    private func mealSection(_ meal: MealType) -> some View {
        let entries = todayFoods.filter { $0.mealValue == meal }
        let kcal = entries.reduce(0) { $0 + $1.kcal }

        Section {
            if entries.isEmpty {
                Text("还没有记录")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                let split = splitByTemplate(entries)
                ForEach(split.singles, id: \.objectID) { entry in
                    foodRow(entry)
                }
                ForEach(split.groups) { group in
                    templateGroupRow(group)
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: meal.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.accent)
                    .accessibilityHidden(true)
                Text(meal.title)
                Text(Fmt.kcal(kcal) + " 千卡")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Spacer()
                // 套餐不再常驻占位，挪进右上角菜单；这里只留「按这个餐次加一条」。
                Button {
                    presetMeal = meal
                    presetDate = nil
                    showFoodSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundColor(Theme.accent)
                        .frame(minWidth: 36, minHeight: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("往\(meal.title)加食物")
            }
            .textCase(nil)
        }
    }

    /// 同一份套餐补进来的几条，在界面上折成一行。
    private struct TemplateGroup: Identifiable {
        let id: String
        let name: String
        let entries: [FoodEntry]

        var itemCount: Int { entries.count }
        var totalKcal: Double { entries.reduce(0) { $0 + $1.kcal } }
    }

    /// 把当餐的条目拆成「零散条目」和「套餐组」两拨。
    ///
    /// 套餐身份藏在 `externalID` 里，格式是 `template:<套餐UUID>:<yyyyMMdd>`。
    /// 一键加和到点补记写的是同一个键，所以同一天同一份套餐的条目自然归到一组。
    /// 老数据里的 `externalID` 是 nil，会被当成零散条目，不影响显示。
    private func splitByTemplate(_ entries: [FoodEntry]) -> (singles: [FoodEntry], groups: [TemplateGroup]) {
        var singles: [FoodEntry] = []
        var buckets: [String: [FoodEntry]] = [:]
        var order: [String] = []

        for entry in entries {
            guard let key = Self.templateKey(of: entry) else {
                singles.append(entry)
                continue
            }
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(entry)
        }

        let groups: [TemplateGroup] = order.compactMap { key in
            guard let items = buckets[key] else { return nil }
            return TemplateGroup(id: key, name: templateName(for: key, first: items.first), entries: items)
        }
        return (singles, groups)
    }

    /// 从 `externalID` 里抠出 `template:<UUID>` 这一段；不是套餐条目就返回 nil。
    private static func templateKey(of entry: FoodEntry) -> String? {
        guard let external = entry.externalID, external.hasPrefix("template:") else { return nil }
        let parts = external.split(separator: ":")
        guard parts.count >= 2 else { return nil }
        return "\(parts[0]):\(parts[1])"
    }

    /// 组名优先查还在的套餐；套餐被删了就退回条目备注里的名字。
    private func templateName(for key: String, first: FoodEntry?) -> String {
        let uuid = key.replacingOccurrences(of: "template:", with: "")
        if let template = templates.first(where: { $0.id.uuidString == uuid }) {
            return template.name
        }
        if let note = first?.note,
           let open = note.firstIndex(of: "「"),
           let close = note.firstIndex(of: "」"),
           open < close {
            let name = note[note.index(after: open)..<close]
            if !name.isEmpty { return String(name) }
        }
        return "套餐"
    }

    /// 同一份套餐补进来的几条在界面上折成一行，点开才摊平明细。
    @ViewBuilder
    private func templateGroupRow(_ group: TemplateGroup) -> some View {
        let expanded = expandedGroups.contains(group.id)

        HStack(spacing: 10) {
            // 不再铺那层 12% 淡底：整页已经够多自绘了，靠强调色本身区分就够。
            Image(systemName: "wand.and.stars")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Theme.accent)
                .frame(width: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.subheadline.weight(.medium))
                Text("套餐 · \(group.itemCount) 样 · " + Fmt.kcal(group.totalKcal) + " 千卡")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(expanded ? -180 : 0))
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleGroup(group.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(expanded ? "收起\(group.name)的明细" : "展开\(group.name)的明细")

        if expanded {
            ForEach(group.entries, id: \.objectID) { entry in
                foodRow(entry)
            }
        }
    }

    private func toggleGroup(_ id: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if expandedGroups.contains(id) {
                expandedGroups.remove(id)
            } else {
                expandedGroups.insert(id)
            }
        }
    }

    /// 一行一条。改和删走左滑，不再挂省略号菜单——
    /// 那玩意儿既占宽度，又等于把「改」藏进两次点击里。
    private func foodRow(_ entry: FoodEntry) -> some View {
        HStack(spacing: 10) {
            FoodThumb(
                // FoodEntry 只有一个图片字段：联网条目存 http 地址，
                // 本地条目存打包资源名，靠前缀分流。
                imageName: (entry.imageURL?.hasPrefix("http") ?? false) ? nil : entry.imageURL,
                urlString: (entry.imageURL?.hasPrefix("http") ?? false) ? entry.imageURL : nil,
                // FoodEntry 没存分类，拿名字回本地库反查一次；查不到就用默认刀叉。
                symbol: FoodCategorySymbol.symbol(for: FoodLibrary.bestMatch(entry.name)?.category ?? ""),
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(Fmt.grams(entry.grams)) g·蛋白 \(Fmt.grams(entry.protein)) / 碳水 \(Fmt.grams(entry.carbs)) / 脂肪 \(Fmt.grams(entry.fat))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(Fmt.kcal(entry.kcal))
                .font(Theme.number(15, weight: .semibold))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Persistence.shared.delete(entry)
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                editingFood = entry
            } label: {
                Label("改这条", systemImage: "pencil")
            }
            .tint(Theme.accent)
        }
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
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundColor(Theme.accent)
                        .frame(minWidth: 36, minHeight: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("加一条运动")
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
                        tint: Theme.accent,
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

                ForEach(todayActivities, id: \.objectID) { activity in
                    HStack(spacing: 10) {
                        Image(systemName: activity.kindValue.symbol)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(Theme.accent)
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
                            // 心率：只有真读到数据才多这一行；为 0 时整段不出现、不占位。
                            if let heart = heartRateText(activity) {
                                Text(heart)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 4)

                        Text(Fmt.kcal(activity.kcal))
                            .font(Theme.number(15, weight: .semibold))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Persistence.shared.delete(activity)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
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

    /// 心率文案：平均 / 最高 bpm，取整；没读到心率（平均值 <= 0）时返回 nil，界面整段不显示。
    private func heartRateText(_ entry: ActivityEntry) -> String? {
        guard entry.averageHeartRate > 0 else { return nil }
        let average = Int(entry.averageHeartRate.rounded())
        if entry.maximumHeartRate > 0 {
            return "平均 \(average) · 最高 \(Int(entry.maximumHeartRate.rounded())) bpm"
        }
        return "平均 \(average) bpm"
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
