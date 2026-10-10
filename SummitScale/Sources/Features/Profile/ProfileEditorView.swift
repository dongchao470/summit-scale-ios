import CoreData
import SwiftUI

/// 编辑档案。字段跟首启引导一致，之后随时能改。
struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)],
        animation: .default
    )
    private var profiles: FetchedResults<UserProfile>

    @State private var name = ""
    @State private var sex: Sex = .female
    @State private var birthDate = Date()
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var targetText = ""
    @State private var activity: ActivityLevel = .light
    @State private var goal: GoalType = .lose
    @State private var loaded = false

    private var earliestBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? Date()
    }

    private var preview: CalorieBudget? {
        let height = Fmt.number(heightText)
        let weight = Fmt.number(weightText)
        guard height > 0, weight > 0 else { return nil }
        return CalorieBudget.make(
            sex: sex,
            kilograms: weight,
            heightCentimeters: height,
            ageYears: CalorieMath.ageYears(birthDate: birthDate),
            level: activity,
            goal: goal,
            overrideKcal: nil
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("身份") {
                    TextField("称呼", text: $name)
                    Picker("性别", selection: $sex) {
                        ForEach(Sex.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    DatePicker(
                        "出生日期",
                        selection: $birthDate,
                        in: earliestBirthDate...Date(),
                        displayedComponents: .date
                    )
                }

                Section("身体") {
                    numberRow("身高", text: $heightText, unit: "cm", label: "身高，单位厘米")
                    numberRow("体重", text: $weightText, unit: "kg", label: "体重，单位公斤")
                }

                Section {
                    Picker("目标", selection: $goal) {
                        ForEach(GoalType.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    numberRow("目标体重", text: $targetText, unit: "kg", label: "目标体重，单位公斤")
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
                    if let preview = preview {
                        Text("基础代谢 \(Fmt.kcal(preview.bmr)) 千卡，每天总消耗 \(Fmt.kcal(preview.tdee)) 千卡，建议摄入 \(Fmt.kcal(preview.intakeTarget)) 千卡。")
                    }
                }
            }
            .navigationTitle("档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func numberRow(
        _ title: String,
        text: Binding<String>,
        unit: String,
        label: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 88)
                .accessibilityLabel(label)
            Text(unit)
                .foregroundColor(.secondary)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let profile = profiles.first else { return }
        name = profile.name
        sex = profile.sexValue
        birthDate = profile.birthDate
        heightText = profile.heightCentimeters > 0 ? Fmt.height(profile.heightCentimeters) : ""
        weightText = profile.startWeightKilograms > 0 ? Fmt.kg(profile.startWeightKilograms) : ""
        targetText = profile.targetWeightKilograms > 0 ? Fmt.kg(profile.targetWeightKilograms) : ""
        activity = profile.activityValue
        goal = profile.goalValue
    }

    private func save() {
        let profile = Persistence.shared.ensureProfile()
        Persistence.shared.updateProfile(
            profile,
            name: name,
            sex: sex,
            birthDate: birthDate,
            heightCentimeters: Fmt.number(heightText),
            startWeightKilograms: Fmt.number(weightText),
            activity: activity,
            goal: goal,
            targetWeightKilograms: Fmt.number(targetText),
            dailyCalorieOverride: 0
        )
        dismiss()
    }
}
