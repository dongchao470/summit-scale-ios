import SwiftUI

struct HikeEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var date: Date = Date()
    @State private var distance: Double = 5
    @State private var elevation: Double = 300
    @State private var duration: Double = 120
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("路线") {
                    TextField("名称", text: $title)
                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }

                Section("数据") {
                    numberRow(label: "距离", value: $distance, unit: "km", fractionDigits: 2)
                    numberRow(label: "累计爬升", value: $elevation, unit: "m", fractionDigits: 0)
                    numberRow(label: "用时", value: $duration, unit: "分钟", fractionDigits: 0)
                }

                Section("备注") {
                    TextField("可选", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle("记爬山")
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

    private func numberRow(label: String, value: Binding<Double>, unit: String, fractionDigits: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(fractionDigits)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("\(label)，单位\(unit)")
            Text(unit)
                .foregroundColor(.secondary)
        }
    }

    private func save() {
        Persistence.shared.addHike(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            distanceKilometers: distance,
            elevationGainMeters: elevation,
            durationMinutes: duration,
            note: note
        )
        dismiss()
    }
}
