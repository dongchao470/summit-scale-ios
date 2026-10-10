import CoreData
import SwiftUI

/// 记一笔饮食：从食物库挑（本地家常菜 + 联网包装食品），定好份量后入账。
struct AddFoodSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var picked: PickedFood?
    @State private var grams: Double
    @State private var gramsText: String
    @State private var meal: MealType
    @State private var date = Date()
    @State private var isManual = false
    @State private var manualName = ""
    @State private var manualKcalText = ""
    @State private var showPicker = false

    /// 按当前时间猜默认餐次，省得每次都手动切。
    static func suggestedMeal(for date: Date = Date()) -> MealType {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<10: return .breakfast
        case 10..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snack
        }
    }

    init(defaultMeal: MealType = AddFoodSheet.suggestedMeal()) {
        _meal = State(initialValue: defaultMeal)
        _grams = State(initialValue: 100)
        _gramsText = State(initialValue: "100")
    }

    private var manualKcal: Double {
        Double(manualKcalText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private var canSave: Bool {
        if isManual {
            return !manualName.trimmingCharacters(in: .whitespaces).isEmpty && manualKcal > 0
        }
        return picked != nil && grams > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("什么时候吃的") {
                    Picker("餐次", selection: $meal) {
                        ForEach(MealType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    DatePicker("时间", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }

                if isManual {
                    manualSection
                } else {
                    foodSection
                }

                Section {
                    Toggle("直接输热量", isOn: $isManual.animation())
                }
            }
            .navigationTitle("记饮食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("记上") { save() }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showPicker) {
                FoodPickerSheet { food in
                    picked = food
                    grams = food.commonGrams
                    gramsText = Fmt.grams(food.commonGrams)
                }
            }
        }
    }

    // MARK: - 从库里挑

    @ViewBuilder
    private var foodSection: some View {
        Section("吃什么") {
            if let food = picked {
                HStack(spacing: 12) {
                    FoodThumb(urlString: food.imageURL, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(food.name)
                            .font(.body.weight(.medium))
                        if let brand = food.brand, !brand.isEmpty {
                            Text(brand)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("每 100 g 约 \(Fmt.kcal(food.kcalPer100)) 千卡")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("换") { showPicker = true }
                        .frame(minWidth: Theme.minTouch, minHeight: Theme.minTouch)
                }

                HStack {
                    Text("份量")
                    Spacer()
                    TextField("克", text: $gramsText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                        .onChange(of: gramsText) { text in
                            grams = Double(text) ?? 0
                        }
                    Text("g").foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    portionButton("半份", food.commonGrams / 2, food: food)
                    portionButton("一份", food.commonGrams, food: food)
                    portionButton("两份", food.commonGrams * 2, food: food)
                }

                if grams > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("这一份约 \(Fmt.kcal(food.kcal(grams: grams))) 千卡")
                            .font(.headline)
                        HStack(spacing: 8) {
                            StatTile(title: "蛋白质", value: Fmt.grams(food.protein(grams: grams)), unit: "g", tint: Theme.protein)
                            StatTile(title: "碳水", value: Fmt.grams(food.carbs(grams: grams)), unit: "g", tint: Theme.carbs)
                            StatTile(title: "脂肪", value: Fmt.grams(food.fat(grams: grams)), unit: "g", tint: Theme.fat)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                        Text("从食物库挑一个")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(minHeight: Theme.minTouch)
                }
            }
        }
    }

    private func portionButton(_ title: String, _ value: Double, food: PickedFood) -> some View {
        Button(title) {
            grams = value
            gramsText = Fmt.grams(value)
        }
        .buttonStyle(.bordered)
        .frame(minHeight: Theme.minTouch)
        .accessibilityLabel("\(title)，\(Fmt.grams(value)) 克")
    }

    // MARK: - 手输热量

    @ViewBuilder
    private var manualSection: some View {
        Section("手动填") {
            TextField("吃了什么", text: $manualName)
            HStack {
                Text("热量")
                Spacer()
                TextField("千卡", text: $manualKcalText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 88)
                Text("千卡").foregroundColor(.secondary)
            }
            Text("手填的条目只有热量，不参与三大营养素统计。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 入账

    private func save() {
        let store = Persistence.shared
        if isManual {
            store.addFood(
                name: manualName.trimmingCharacters(in: .whitespacesAndNewlines),
                meal: meal,
                grams: 0,
                kcal: manualKcal,
                protein: 0,
                carbs: 0,
                fat: 0,
                foodID: nil,
                note: "手动输入",
                date: date
            )
        } else if let food = picked {
            let displayName = [food.brand, food.name]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            store.addFood(
                name: displayName,
                meal: meal,
                grams: grams,
                kcal: food.kcal(grams: grams),
                protein: food.protein(grams: grams),
                carbs: food.carbs(grams: grams),
                fat: food.fat(grams: grams),
                foodID: food.id,
                note: food.isRemote ? "联网条目" : nil,
                date: date,
                imageURL: food.imageURL
            )
        }
        dismiss()
    }
}
