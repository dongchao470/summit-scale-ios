import SwiftUI

/// 记体重。
///
/// 数值改用滚轮（picker wheel）选择，不再弹数字键盘：
/// 早上称完单手就能滚到目标值，省掉「点输入框 → 弹键盘 → 输入 → 收键盘」四步。
/// 体重以 0.1kg 为最小刻度存成整数，避免 Double 在滚轮里做相等比较。
struct AddWeightSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var tenths: Int
    @State private var date: Date
    @State private var note: String = ""

    /// 可选范围 20.0 ~ 300.0 kg，覆盖常见取值；滚轮底层是 UIPickerView，会按需渲染。
    private static let tenthsRange = 200...3000

    init(defaultKilograms: Double) {
        let clamped = min(max(defaultKilograms, 20.0), 300.0)
        _tenths = State(initialValue: Int((clamped * 10).rounded()))
        _date = State(initialValue: Date())
    }

    /// 当前选中的公斤数。
    private var kilograms: Double { Double(tenths) / 10 }

    private static func label(for tenths: Int) -> String {
        String(format: "%.1f", Double(tenths) / 10)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("体重（公斤）", selection: $tenths) {
                        ForEach(Self.tenthsRange, id: \.self) { value in
                            Text(Self.label(for: value)).tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("体重，单位公斤")
                    .accessibilityValue(Self.label(for: tenths) + "公斤")
                } header: {
                    Text("体重（公斤）")
                } footer: {
                    Text("上下滚动选择，最小刻度 0.1 公斤。")
                }

                Section("时间") {
                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }

                Section("备注") {
                    TextField("可选", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle("记体重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
        }
    }

    private func save() {
        Persistence.shared.addWeight(kilograms: kilograms, date: date, note: note)
        // 已接入健康且开了体重同步时，顺手写回健康 App。
        HealthKitManager.shared.saveWeight(kilograms: kilograms, date: date)
        dismiss()
    }
}
