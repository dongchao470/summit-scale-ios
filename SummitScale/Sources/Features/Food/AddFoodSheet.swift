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
    @State private var manualGramsText = ""
    @State private var showPicker = false
    /// 每 100 克营养的输入文本：联网来源经常没有营养表，得让用户自己改。
    @State private var kcal100Text = ""
    @State private var protein100Text = ""
    @State private var carbs100Text = ""
    @State private var fat100Text = ""
    @FocusState private var focusedField: Field?

    /// 需要自己收键盘的输入框。
    private enum Field: Hashable {
        case grams
        case manualName
        case manualKcal
        case manualGrams
        case kcal100
        case protein100
        case carbs100
        case fat100
    }

    /// 按当前时间猜默认餐次，省得每次都手动切。
    static func suggestedMeal(for date: Date = Date()) -> MealType {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<10: return .breakfast
        case 10..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snack
        }
    }

    /// 非空表示在编辑这条已有记录：保存时回写，不新建。
    private let editingEntry: FoodEntry?

    /// - Parameters:
    ///   - defaultMeal: 打开时预选的餐次。
    ///   - date: 记到哪一天，默认今天；「补记昨天」会传昨天的日期。
    ///   - editing: 传了就是编辑这条已有记录，而不是新增。
    init(
        defaultMeal: MealType = AddFoodSheet.suggestedMeal(),
        date: Date = Date(),
        editing entry: FoodEntry? = nil
    ) {
        self.editingEntry = entry
        _meal = State(initialValue: entry?.mealValue ?? defaultMeal)
        _grams = State(initialValue: 100)
        _gramsText = State(initialValue: "100")
        _date = State(initialValue: date)
        if let entry = entry {
            // 已有记录当成手填条目来改：名称、热量、份量都能动。
            // 图片、来源、外部 id 一律不碰，免得编辑一次把配图弄丢。
            _isManual = State(initialValue: true)
            _manualName = State(initialValue: entry.name)
            _manualKcalText = State(
                initialValue: entry.kcal > 0 ? String(Int(entry.kcal.rounded())) : ""
            )
            _manualGramsText = State(
                initialValue: entry.grams > 0 ? Fmt.grams(entry.grams) : ""
            )
        }
    }

    private var manualKcal: Double {
        Double(manualKcalText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    /// 手填条目的份量，留空就是 0（只记热量，不折算克数）。
    private var manualGrams: Double {
        Double(manualGramsText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private var canSave: Bool {
        if isManual {
            return !manualName.trimmingCharacters(in: .whitespaces).isEmpty && manualKcal > 0
        }
        return picked != nil && grams > 0
    }

    /// 当前选中的食物，营养值取输入框里的（用户可能手动改过）。
    private var editedFood: PickedFood? {
        picked?.replacingNutrients(
            kcalPer100: nutrientValue(kcal100Text),
            proteinPer100: nutrientValue(protein100Text),
            carbsPer100: nutrientValue(carbs100Text),
            fatPer100: nutrientValue(fat100Text)
        )
    }

    /// 把营养值搬进输入框：0 就留空，免得看起来像「已经填好了」。
    private func applyNutrientTexts(_ food: PickedFood) {
        kcal100Text = nutrientText(food.kcalPer100)
        protein100Text = nutrientText(food.proteinPer100)
        carbs100Text = nutrientText(food.carbsPer100)
        fat100Text = nutrientText(food.fatPer100)
    }

    private func nutrientText(_ value: Double) -> String {
        guard value > 0 else { return "" }
        return value.rounded() == value
            ? String(Int(value))
            : String(format: "%.1f", value)
    }

    private func nutrientValue(_ text: String) -> Double {
        Double(text.trimmingCharacters(in: .whitespaces)) ?? 0
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
            .navigationTitle(editingEntry == nil ? "记饮食" : "改这条")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("记上") { save() }
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }
                }
            }
            .sheet(isPresented: $showPicker) {
                FoodPickerSheet { food in
                    picked = food
                    grams = food.commonGrams
                    gramsText = Fmt.grams(food.commonGrams)
                    applyNutrientTexts(food)
                }
            }
        }
    }

    // MARK: - 从库里挑

    @ViewBuilder
    private var foodSection: some View {
        Section("吃什么") {
            if let food = editedFood {
                HStack(spacing: 12) {
                    FoodThumb(
                        imageName: food.imageName,
                        urlString: food.imageURL,
                        symbol: FoodCategorySymbol.symbol(for: food.category),
                        size: 56
                    )
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
                        .focused($focusedField, equals: .grams)
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

        if picked != nil {
            nutrientSection
        }
    }

    /// 每 100 克营养，手动可改。
    ///
    /// 联网查来的条目经常没有营养表（下厨房只给菜名和图），本地库又对不上同名菜的话
    /// 四项全是 0；不给个输入口，用户就只能眼睁睁记一条 0 千卡的账。
    private var nutrientSection: some View {
        Section {
            nutrientRow("热量", unit: "千卡", text: $kcal100Text, field: .kcal100)
            nutrientRow("蛋白质", unit: "g", text: $protein100Text, field: .protein100)
            nutrientRow("碳水", unit: "g", text: $carbs100Text, field: .carbs100)
            nutrientRow("脂肪", unit: "g", text: $fat100Text, field: .fat100)
        } header: {
            Text("每 100 g 营养")
        } footer: {
            Text("取不到数据时这里是空的，自己填一个准的；上面的份量会跟着一起折算。")
        }
    }

    private func nutrientRow(
        _ title: String,
        unit: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: field)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
            Text(unit).foregroundColor(.secondary)
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
                .focused($focusedField, equals: .manualName)
            HStack {
                Text("热量")
                Spacer()
                TextField("千卡", text: $manualKcalText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .manualKcal)
                    .frame(width: 88)
                Text("千卡").foregroundColor(.secondary)
            }
            HStack {
                Text("份量")
                Spacer()
                TextField("克", text: $manualGramsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .manualGrams)
                    .frame(width: 88)
                Text("克").foregroundColor(.secondary)
            }
            Text("手填的条目只有热量，不参与三大营养素统计；份量可以留空。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 入账

    private func save() {
        let store = Persistence.shared

        // 编辑已有记录：只回写这一条，不新建，配图和来源原样保留。
        if let entry = editingEntry {
            store.updateFood(
                entry,
                name: manualName,
                meal: meal,
                grams: manualGrams,
                kcal: manualKcal,
                date: date
            )
            dismiss()
            return
        }

        if isManual {
            store.addFood(
                name: manualName.trimmingCharacters(in: .whitespacesAndNewlines),
                meal: meal,
                grams: manualGrams,
                kcal: manualKcal,
                protein: 0,
                carbs: 0,
                fat: 0,
                foodID: nil,
                note: "手动输入",
                date: date
            )
        } else if let food = editedFood {
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
                // FoodEntry 只有一个图片字段：联网条目存 http 地址，本地条目存打包资源名。
                imageURL: food.isRemote ? food.imageURL : food.imageName,
                source: food.isRemote ? FoodSource.remote : FoodSource.library,
                // 联网条目把外部 id 也存上，方便以后去重和对账。
                externalID: food.isRemote ? food.id : nil
            )
        }
        dismiss()
    }
}
