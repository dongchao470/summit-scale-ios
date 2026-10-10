import SwiftUI

struct AddWeightSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var kilograms: Double
    @State private var date: Date
    @State private var note: String = ""

    init(defaultKilograms: Double) {
        _kilograms = State(initialValue: defaultKilograms)
        _date = State(initialValue: Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("数值") {
                    HStack {
                        Text("体重")
                        Spacer()
                        TextField("0.0", value: $kilograms, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title3.weight(.semibold))
                            .accessibilityLabel("体重，单位公斤")
                        Text("kg")
                            .foregroundColor(.secondary)
                    }
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
                        .disabled(kilograms <= 0)
                }
            }
        }
    }

    private func save() {
        Persistence.shared.addWeight(kilograms: kilograms, date: date, note: note)
        dismiss()
    }
}
