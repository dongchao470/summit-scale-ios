import SwiftUI

/// 首启引导：把算热量必需的身体参数一次问清。
struct OnboardingView: View {
    /// 填完或跳过时回调，交给根视图撤掉引导。
    var onFinish: () -> Void

    @State private var step = 0
    @State private var name = ""
    @State private var sex: Sex = .female
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var activity: ActivityLevel = .light
    @State private var goal: GoalType = .lose
    @State private var targetWeightText = ""

    private var heightCentimeters: Double { Self.number(heightText) }
    private var weightKilograms: Double { Self.number(weightText) }
    private var targetWeightKilograms: Double { Self.number(targetWeightText) }

    private var canAdvance: Bool {
        switch step {
        case 0:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1:
            return heightCentimeters >= 100 && heightCentimeters <= 250
                && weightKilograms >= 25 && weightKilograms <= 300
        default:
            return true
        }
    }

    private var budgetPreview: CalorieBudget? {
        guard heightCentimeters > 0, weightKilograms > 0 else { return nil }
        return CalorieBudget.make(
            sex: sex,
            kilograms: weightKilograms,
            heightCentimeters: heightCentimeters,
            ageYears: CalorieMath.ageYears(birthDate: birthDate),
            level: activity,
            goal: goal,
            overrideKcal: nil
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProgressView(value: Double(step + 1), total: 3)
                        .accessibilityLabel("第 \(step + 1) 步，共 3 步")
                }

                switch step {
                case 0: identitySection
                case 1: bodySection
                default: goalSection
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if step > 0 {
                        Button("上一步") { step -= 1 }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("跳过") { finish(recordWeight: false) }
                        .accessibilityLabel("跳过引导")
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - 分步内容

    private var stepTitle: String {
        switch step {
        case 0: return "先认识一下"
        case 1: return "你的身体数据"
        default: return "你想去哪儿"
        }
    }

    private var identitySection: some View {
        Section {
            TextField("怎么称呼你", text: $name)
                .textContentType(.name)

            Picker("性别", selection: $sex) {
                ForEach(Sex.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            DatePicker("出生日期", selection: $birthDate, in: birthRange, displayedComponents: .date)
        } header: {
            Text("身份")
        } footer: {
            Text("性别和年龄只用来算基础代谢，不做别的用途。")
        }
    }

    private var bodySection: some View {
        Section {
            measurementRow(title: "身高", placeholder: "170", text: $heightText, unit: "cm", label: "身高，单位厘米")
            measurementRow(title: "体重", placeholder: "60", text: $weightText, unit: "kg", label: "体重，单位公斤")
        } header: {
            Text("身体")
        } footer: {
            Text("这两个数决定基础代谢。以后每次记体重都会自动更新。")
        }
    }

    private var goalSection: some View {
        Section {
            Picker("目标", selection: $goal) {
                ForEach(GoalType.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if goal != .maintain {
                measurementRow(
                    title: "目标体重",
                    placeholder: "55",
                    text: $targetWeightText,
                    unit: "kg",
                    label: "目标体重，单位公斤"
                )
            }

            Picker("日常活动量", selection: $activity) {
                ForEach(ActivityLevel.allCases) { option in
                    Text(option.title).tag(option)
                }
            }

            Text(activity.detail)
                .font(.footnote)
                .foregroundColor(.secondary)
        } header: {
            Text("目标")
        } footer: {
            if let preview = budgetPreview {
                Text("按现在的数据，你每天大约消耗 \(Fmt.kcal(preview.tdee)) 千卡，建议摄入 \(Fmt.kcal(preview.intakeTarget)) 千卡。")
            } else {
                Text("填完身高体重就能看到每天的热量预算。")
            }
        }
    }

    private func measurementRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        unit: String,
        label: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 88)
                .accessibilityLabel(label)
            Text(unit)
                .foregroundColor(.secondary)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                if step < 2 {
                    step += 1
                } else {
                    finish(recordWeight: true)
                }
            } label: {
                Text(step < 2 ? "下一步" : "开始记录")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAdvance)
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    // MARK: - 落库

    private var birthRange: ClosedRange<Date> {
        let now = Date()
        let earliest = Calendar.current.date(byAdding: .year, value: -100, to: now) ?? now
        return earliest...now
    }

    private func finish(recordWeight: Bool) {
        let persistence = Persistence.shared
        let profile = persistence.ensureProfile()
        persistence.updateProfile(
            profile,
            name: name,
            sex: sex,
            birthDate: birthDate,
            heightCentimeters: heightCentimeters,
            startWeightKilograms: weightKilograms,
            activity: activity,
            goal: goal,
            targetWeightKilograms: targetWeightKilograms,
            dailyCalorieOverride: 0
        )

        if recordWeight, weightKilograms > 0 {
            persistence.addWeight(kilograms: weightKilograms, date: Date(), note: "初始体重")
        }

        onFinish()
    }

    /// 中文键盘可能打出全角小数点或逗号，统一成点。
    private static func number(_ text: String) -> Double {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "，", with: ".")
            .replacingOccurrences(of: "。", with: ".")
        return Double(normalized) ?? 0
    }
}
