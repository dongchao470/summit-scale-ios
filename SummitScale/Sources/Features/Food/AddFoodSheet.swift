import CoreData
import SwiftUI

/// 记一笔饮食。从食物库里挑，或者直接手输热量。
struct AddFoodSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selected: FoodItem?
    @State private var gramsText = ""
    @State private var meal: MealType
    @State private var date = Date()
    @State private var manualName = ""
    @State private var manualKcalText = ""
    @State private var isManual = false

    init(defaultMeal: MealType = .lunch) {
        _meal = State(initialValue: defaultMeal)
    }

    /// 按当前时间猜一个默认餐次。
    static func suggestedMeal(now: Date = Date()) -> MealType {
        switch Calendar.current.component(.hour, from: now) {
        case 5..<10: return .breakfast
        case 10..<15: return .lunch
        case 15..<17: return .snack
        case 17..<22: return .dinner
        default: return .snack
        }
    }

    private var grams: Double { Fmt.number(gramsText) }
    private var manualKcal: Double { Fmt.number(manualKcalText) }

    private var results: [FoodItem] {
        let found = FoodLibrary.search(query)
        return Array(found.prefix(query.isEmpty ? 24 : 60))
    }

    private var canSave: Bool {
        if isManual {
            return !manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && manualKcal > 0
        }
        return selected != nil && grams > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("餐次") {
                    Picker("餐次", selection: $meal) {
                        ForEach(MealType.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    DatePicker("时间", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }

                if isManual {
                    manualSection
                } else if let item = selected {
                    portionSection(item)
                } else {
                    pickerSection
                }

                Section {
                    Toggle("手动输入热量", isOn: $isManual)
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜食物，比如米饭"
            )
            .navigationTitle("记饮食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    @ViewBuilder
    private var pickerSection: some View {
        Section {
            ForEach(results) { item in
                Button {
                    selected = item
                    gramsText = Fmt.grams(item.commonGrams)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .foregroundColor(.primary)
                            Text("\(item.category) · 每 100 g \(Fmt.kcal(item.kcalPer100g)) 千卡")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(Fmt.kcal(item.kcal(grams: item.commonGrams)))
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(query.isEmpty ? "常用食物" : "搜索结果")
        }
    }

    @ViewBuilder
    private func portionSection(_ item: FoodItem) -> some View {
        Section {
            HStack {
                Text(item.name)
                Spacer()
                Button("换一个") { selected = nil }
                    .font(.footnote)
            }

            HStack {
                Text("份量")
                Spacer()
                TextField("100", text: $gramsText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 88)
                    .accessibilityLabel("份量，单位克")
                Text("g")
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                quickButton(item.commonLabel, grams: item.commonGrams)
                quickButton("100 g", grams: 100)
                quickButton("半份", grams: item.commonGrams / 2)
            }
        } header: {
            Text("份量")
        } footer: {
            Text("约 \(Fmt.kcal(item.kcal(grams: grams))) 千卡 · 蛋白 \(Fmt.grams(item.protein(grams: grams))) g · 碳水 \(Fmt.grams(item.carbs(grams: grams))) g · 脂肪 \(Fmt.grams(item.fat(grams: grams))) g")
        }
    }

    private func quickButton(_ title: String, grams value: Double) -> some View {
        Button(title) {
            gramsText = Fmt.grams(value)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private var manualSection: some View {
        Section("手动输入") {
            TextField("食物名称", text: $manualName)

            HStack {
                Text("热量")
                Spacer()
                TextField("0", text: $manualKcalText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 88)
                    .accessibilityLabel("热量，单位千卡")
                Text("kcal")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func save() {
        if isManual {
            Persistence.shared.addFood(
                name: manualName,
                meal: meal,
                grams: 0,
                kcal: manualKcal,
                protein: 0,
                carbs: 0,
                fat: 0,
                foodID: nil,
                note: nil,
                date: date
            )
        } else if let item = selected {
            Persistence.shared.addFood(
                name: item.name,
                meal: meal,
                grams: grams,
                kcal: item.kcal(grams: grams),
                protein: item.protein(grams: grams),
                carbs: item.carbs(grams: grams),
                fat: item.fat(grams: grams),
                foodID: item.id,
                note: nil,
                date: date
            )
        }
        dismiss()
    }
}
