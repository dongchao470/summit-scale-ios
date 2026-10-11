import CoreData
import SwiftUI

/// 套餐提醒里选「改完再记」时打开：把套餐内容摊成一份可编辑清单。
///
/// 这里改的只是这一次要记进去的记录，原套餐一个字都不动。
/// 想吃少一点、去掉一样、临时补一样，都在这里办。
struct TemplateFillSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let template: MealTemplate
    private let date: Date

    /// 摊开后的条目：进来时从套餐复制一份，之后随便改。
    @State private var rows: [Row]
    @State private var meal: MealType

    /// 清单里的一行，只活在这一次编辑里。
    private struct Row: Identifiable {
        let id = UUID()
        var name: String
        var gramsText: String
        var kcalText: String
        /// 每克热量。改份量时拿它把热量折过去，免得两处对不上。
        var kcalPerGram: Double

        /// 份量数值，解析不出来就是 0。
        var gramsValue: Double {
            Double(gramsText.trimmingCharacters(in: .whitespaces)) ?? 0
        }

        /// 热量数值，解析不出来就是 0。
        var kcalValue: Double {
            Double(kcalText.trimmingCharacters(in: .whitespaces)) ?? 0
        }
    }

    /// - Parameters:
    ///   - template: 要照着记的套餐。
    ///   - date: 记到哪一天。
    init(template: MealTemplate, date: Date) {
        self.template = template
        self.date = date
        _meal = State(initialValue: template.meal)
        _rows = State(initialValue: template.items.map { item in
            let perGram = item.grams > 0 ? item.kcal / item.grams : 0
            return Row(
                name: item.name,
                gramsText: Fmt.grams(item.grams),
                kcalText: Fmt.kcal(item.kcal),
                kcalPerGram: perGram
            )
        })
    }

    /// 清单里真正会记进去的条数。
    private var effectiveRows: [Row] {
        rows.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.kcalValue > 0 }
    }

    private var totalKcal: Double {
        effectiveRows.reduce(0) { $0 + $1.kcalValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("记到哪餐", selection: $meal) {
                        ForEach(MealType.allCases) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                } footer: {
                    Text("只影响这一次记录，原套餐不会被改动。")
                }

                Section("这几样") {
                    ForEach($rows) { $row in
                        rowEditor($row)
                    }
                    .onDelete { offsets in
                        rows.remove(atOffsets: offsets)
                    }

                    Button {
                        rows.append(
                            Row(name: "", gramsText: "", kcalText: "", kcalPerGram: 0)
                        )
                    } label: {
                        Label("再加一样", systemImage: "plus.circle")
                            .frame(minHeight: Theme.minTouch)
                    }
                }

                Section {
                    HStack {
                        Text("合计")
                        Spacer()
                        Text("约 \(Fmt.kcal(totalKcal)) 千卡")
                            .foregroundColor(Theme.secondaryText)
                    }
                }
            }
            .navigationTitle("改完再记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("记上") { save() }
                        .disabled(effectiveRows.isEmpty)
                }
            }
        }
    }

    /// 一行条目：名称在上，份量与热量在下，够宽，不用横着挤。
    private func rowEditor(_ row: Binding<Row>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("吃了什么", text: row.name)

            HStack(spacing: 12) {
                TextField("克", text: row.gramsText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .onChange(of: row.wrappedValue.gramsText) { newValue in
                        // 份量一改，热量按原来的每克热量跟着折，省得手动算。
                        scaleKcal(row, gramsText: newValue)
                    }
                Text("克").foregroundColor(Theme.secondaryText)
                Spacer()
                TextField("千卡", text: row.kcalText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                Text("千卡").foregroundColor(Theme.secondaryText)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 2)
    }

    /// 按新的份量折算热量，写回那一行的热量输入框。
    private func scaleKcal(_ row: Binding<Row>, gramsText: String) {
        let value = row.wrappedValue
        guard value.kcalPerGram > 0 else { return }
        let grams = Double(gramsText.trimmingCharacters(in: .whitespaces)) ?? 0
        guard grams > 0 else { return }
        row.wrappedValue.kcalText = Fmt.kcal(value.kcalPerGram * grams)
    }

    /// 逐条写进去。空名字、零热量的行直接跳过，不当成条目写。
    private func save() {
        let store = Persistence.shared
        for row in effectiveRows {
            store.addFood(
                name: row.name.trimmingCharacters(in: .whitespacesAndNewlines),
                meal: meal,
                grams: row.gramsValue,
                kcal: row.kcalValue,
                protein: 0,
                carbs: 0,
                fat: 0,
                foodID: nil,
                note: "套餐「\(template.name)」改后记入",
                date: date
            )
        }
        dismiss()
    }
}


