import Charts
import CoreData
import SwiftUI

/// 回顾。看趋势，不看单点。
struct ReviewView: View {
    enum Span: String, CaseIterable, Identifiable {
        case week
        case month
        case quarter

        var id: String { rawValue }

        var title: String {
            switch self {
            case .week: return "7 天"
            case .month: return "30 天"
            case .quarter: return "90 天"
            }
        }

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            }
        }
    }

    struct DailyIntake: Identifiable {
        let day: Date
        let kcal: Double

        var id: Date { day }
    }

    @FetchRequest(sortDescriptors: WeightEntry.dateAscending, animation: .default)
    private var weights: FetchedResults<WeightEntry>

    @FetchRequest(sortDescriptors: FoodEntry.dateDescending, animation: .default)
    private var foods: FetchedResults<FoodEntry>

    @FetchRequest(sortDescriptors: ActivityEntry.dateDescending, animation: .default)
    private var activities: FetchedResults<ActivityEntry>

    @State private var span: Span = .month

    private var cutoff: Date { Fmt.daysAgo(span.days) }

    private var weightPoints: [WeightEntry] {
        weights.filter { $0.date >= cutoff }
    }

    private var dailyIntake: [DailyIntake] {
        let recent = foods.filter { $0.date >= cutoff }
        let grouped = Dictionary(grouping: recent) { Fmt.startOfDay($0.date) }
        return grouped
            .map { DailyIntake(day: $0.key, kcal: $0.value.reduce(0) { $0 + $1.kcal }) }
            .sorted { $0.day < $1.day }
    }

    private var weightChange: Double? {
        guard weightPoints.count >= 2, let first = weightPoints.first, let last = weightPoints.last else {
            return nil
        }
        return last.kilograms - first.kilograms
    }

    private var totalBurn: Double {
        activities.filter { $0.date >= cutoff }.reduce(0) { $0 + $1.kcal }
    }

    private var averageIntake: Double? {
        guard !dailyIntake.isEmpty else { return nil }
        let total = dailyIntake.reduce(0) { $0 + $1.kcal }
        return total / Double(dailyIntake.count)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("区间", selection: $span) {
                        ForEach(Span.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                weightSection
                intakeSection
                summarySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("回顾")
        }
    }

    @ViewBuilder
    private var weightSection: some View {
        Section("体重") {
            if weightPoints.count >= 2 {
                Chart(weightPoints, id: \.objectID) { entry in
                    AreaMark(
                        x: .value("日期", entry.date),
                        y: .value("体重", entry.kilograms)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.12))

                    LineMark(
                        x: .value("日期", entry.date),
                        y: .value("体重", entry.kilograms)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
                .accessibilityLabel("体重趋势图，共 \(weightPoints.count) 个点")
            } else {
                Text("记录还不够画趋势，多记几天。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var intakeSection: some View {
        Section("每天吃进去的") {
            if dailyIntake.count >= 2 {
                Chart(dailyIntake) { point in
                    BarMark(
                        x: .value("日期", point.day, unit: .day),
                        y: .value("千卡", point.kcal)
                    )
                    .foregroundStyle(Color.orange.opacity(0.75))
                }
                .frame(height: 160)
                .accessibilityLabel("每日摄入热量柱状图，共 \(dailyIntake.count) 天")
            } else {
                Text("还没有足够的饮食记录。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        Section {
            if let change = weightChange {
                summaryRow("体重变化", value: Fmt.signedKg(change), unit: "kg")
            }
            if let average = averageIntake {
                summaryRow("平均每天摄入", value: Fmt.kcal(average), unit: "kcal")
            }
            summaryRow("运动消耗合计", value: Fmt.kcal(totalBurn), unit: "kcal")
            summaryRow("记了几天", value: "\(dailyIntake.count)", unit: "天")
        } header: {
            Text("区间汇总")
        } footer: {
            Text("热量是估算值，按公式推的，不是医疗建议。")
        }
    }

    private func summaryRow(_ title: String, value: String, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.body.weight(.medium))
                .monospacedDigit()
            Text(unit)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
