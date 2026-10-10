import CoreData
import SwiftUI

/// 记一笔运动。热量按 MET 公式自动估算，也能手动覆盖。
struct ActivityEditorView: View {
    @Environment(\.dismiss) private var dismiss

    /// 用来估算消耗的当前体重，由调用方传入。
    var bodyKilograms: Double = 60

    @State private var kind: ActivityKind = .hiking
    @State private var title = ""
    @State private var date = Date()
    @State private var minutesText = "60"
    @State private var distanceText = ""
    @State private var elevationText = ""
    @State private var manualKcalText = ""
    @State private var note = ""

    private var minutes: Double { Self.number(minutesText) }
    private var distance: Double { Self.number(distanceText) }
    private var elevation: Double { Self.number(elevationText) }
    private var manualKcal: Double { Self.number(manualKcalText) }

    private var estimatedKcal: Double {
        CalorieMath.burn(kind: kind, minutes: minutes, kilograms: bodyKilograms)
    }

    private var effectiveKcal: Double {
        manualKcal > 0 ? manualKcal : estimatedKcal
    }

    private var canSave: Bool { minutes > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("运动") {
                    Picker("类型", selection: $kind) {
                        ForEach(ActivityKind.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                    TextField(kind.title, text: $title)
                        .accessibilityLabel("运动名称，可留空")
                    DatePicker("时间", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }

                Section {
                    HStack {
                        Text("时长")
                        Spacer()
                        TextField("60", text: $minutesText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 88)
                            .accessibilityLabel("时长，单位分钟")
                        Text("分钟")
                            .foregroundColor(.secondary)
                    }

                    if kind.supportsDistance {
                        HStack {
                            Text("距离")
                            Spacer()
                            TextField("0", text: $distanceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 88)
                                .accessibilityLabel("距离，单位公里")
                            Text("km")
                                .foregroundColor(.secondary)
                        }
                    }

                    if kind == .hiking {
                        HStack {
                            Text("爬升")
                            Spacer()
                            TextField("0", text: $elevationText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 88)
                                .accessibilityLabel("累计爬升，单位米")
                            Text("m")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("数据")
                }

                Section {
                    HStack {
                        Text("消耗")
                        Spacer()
                        TextField(Fmt.kcal(estimatedKcal), text: $manualKcalText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 88)
                            .accessibilityLabel("消耗热量，留空按公式估算")
                        Text("kcal")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("热量")
                } footer: {
                    Text("留空按 \(kind.title) 的代谢当量估算约 \(Fmt.kcal(estimatedKcal)) 千卡（按 \(Fmt.kg(bodyKilograms)) kg 体重）。")
                }

                Section("备注") {
                    TextField("可选", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle("记运动")
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

    private func save() {
        Persistence.shared.addActivity(
            kind: kind,
            title: title,
            date: date,
            durationMinutes: minutes,
            distanceKilometers: distance,
            elevationGainMeters: elevation,
            kcal: effectiveKcal,
            note: note
        )
        dismiss()
    }

    static func number(_ text: String) -> Double {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "，", with: ".")
        return Double(normalized) ?? 0
    }
}
