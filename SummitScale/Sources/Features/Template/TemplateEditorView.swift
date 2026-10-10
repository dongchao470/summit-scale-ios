import CoreData
import SwiftUI

/// 新建 / 编辑一个套餐。
struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss

    /// nil 表示新建。
    let template: MealTemplate?

    @State private var name = ""
    @State private var meal: MealType = .breakfast
    @State private var items: [TemplateItem] = []
    @State private var showPicker = false
    @State private var autoFillEnabled = false
    @State private var autoFillTime = Date()
    @State private var notice: String?

    private var totalKcal: Double {
        items.reduce(0) { $0 + $1.kcal }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !items.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("套餐") {
                    TextField("叫什么，比如「标准早餐」", text: $name)
                    Picker("算哪一餐", selection: $meal) {
                        ForEach(MealType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                }

                Section {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(item.name)
                                    .font(.body.weight(.medium))
                                Spacer(minLength: 4)
                                Text("\(Fmt.kcal(item.kcal)) 千卡")
                                    .font(.subheadline)
                                    .foregroundColor(Theme.accent)
                            }
                            Text(Fmt.grams(item.grams) + " g")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { offsets in
                        items.remove(atOffsets: offsets)
                    }

                    Button {
                        showPicker = true
                    } label: {
                        Label("加一样", systemImage: "plus.circle.fill")
                            .frame(minHeight: Theme.minTouch, alignment: .leading)
                    }
                } header: {
                    Text("内容")
                } footer: {
                    Text(items.isEmpty ? "还没加内容，套餐存不了。" : "合计约 \(Fmt.kcal(totalKcal)) 千卡。左滑可删。")
                }

                Section {
                    Toggle("到点自动填", isOn: $autoFillEnabled.animation())
                    if autoFillEnabled {
                        DatePicker("时间", selection: $autoFillTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("自动填")
                } footer: {
                    Text("到点会给你发一条通知；真正入账在下次打开 App 时完成 —— iOS 不让普通 App 在后台随便跑代码，这是系统限制。")
                }
            }
            .navigationTitle(template == nil ? "新建套餐" : "编辑套餐")
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
            .sheet(isPresented: $showPicker) {
                FoodPickerSheet { food in
                    append(food)
                }
            }
            .onAppear(perform: load)
            .alert(
                "提醒没排上",
                isPresented: Binding(
                    get: { notice != nil },
                    set: { if !$0 { notice = nil } }
                )
            ) {
                Button("知道了") { notice = nil }
            } message: {
                Text(notice ?? "")
            }
        }
    }

    // MARK: - 读写

    private func load() {
        guard let template = template else { return }
        name = template.name
        meal = template.meal
        items = template.items
        autoFillEnabled = template.autoFillEnabled
        var components = DateComponents()
        components.hour = Int(template.autoFillHour)
        components.minute = Int(template.autoFillMinute)
        autoFillTime = Calendar.current.date(from: components) ?? Date()
    }

    private func append(_ food: PickedFood) {
        let grams = food.commonGrams > 0 ? food.commonGrams : 100
        items.append(
            TemplateItem(
                id: UUID().uuidString,
                foodID: food.id,
                name: food.name,
                grams: grams,
                kcal: food.kcal(grams: grams),
                protein: food.protein(grams: grams),
                carbs: food.carbs(grams: grams),
                fat: food.fat(grams: grams),
                imageURL: food.imageURL
            )
        )
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = Calendar.current.dateComponents([.hour, .minute], from: autoFillTime)
        let hour = components.hour ?? meal.templateDefaultHour
        let minute = components.minute ?? 0

        let target: MealTemplate
        if let existing = template {
            Persistence.shared.updateTemplate(existing, name: trimmed, meal: meal, items: items)
            Persistence.shared.setAutoFill(existing, enabled: autoFillEnabled, hour: hour, minute: minute)
            target = existing
        } else {
            let created = Persistence.shared.addTemplate(name: trimmed, meal: meal, items: items)
            Persistence.shared.setAutoFill(created, enabled: autoFillEnabled, hour: hour, minute: minute)
            target = created
        }

        if autoFillEnabled {
            // 先要权限，拿到再排提醒；被拒就告诉用户一声，别装作排上了。
            Task {
                let granted = await Reminders.requestAuthorization()
                if granted {
                    Reminders.sync(target)
                    dismiss()
                } else {
                    notice = "系统没给通知权限，自动填还是会生效，但到点不会提醒你。可以去「设置 → 通知 → 山与秤」里打开。"
                }
            }
        } else {
            Reminders.cancel(target)
            dismiss()
        }
    }
}
