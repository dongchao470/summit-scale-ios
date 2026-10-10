import Charts
import CoreData
import SwiftUI

struct WeekBucket: Identifiable {
    let weekStart: Date
    let kilometers: Double
    let count: Int

    var id: Date { weekStart }
}

struct ReviewView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case days30 = "30 天"
        case days90 = "90 天"
        case all = "全部"

        var id: String { rawValue }

        var dayCount: Int? {
            switch self {
            case .days30: return 30
            case .days90: return 90
            case .all: return nil
            }
        }
    }

    @FetchRequest(sortDescriptors: WeightEntry.dateAscending, animation: .default)
    private var weights: FetchedResults<WeightEntry>

    @FetchRequest(sortDescriptors: Hike.dateAscending, animation: .default)
    private var hikes: FetchedResults<Hike>

    @State private var scope: Scope = .days90

    private var weightPoints: [WeightEntry] {
        guard let days = scope.dayCount else { return Array(weights) }
        let cutoff = Fmt.daysAgo(days)
        return weights.filter { $0.date >= cutoff }
    }

    private var hikePoints: [Hike] {
        guard let days = scope.dayCount else { return Array(hikes) }
        let cutoff = Fmt.daysAgo(days)
        return hikes.filter { $0.date >= cutoff }
    }

    private var weeklyHikes: [WeekBucket] {
        var buckets: [Date: (Double, Int)] = [:]
        for hike in hikePoints {
            let key = Fmt.startOfWeek(hike.date)
            let current = buckets[key] ?? (0, 0)
            buckets[key] = (current.0 + hike.distanceKilometers, current.1 + 1)
        }
        return buckets
            .map { WeekBucket(weekStart: $0.key, kilometers: $0.value.0, count: $0.value.1) }
            .sorted { $0.weekStart < $1.weekStart }
    }

    private var weightSummary: (average: Double, min: Double, max: Double, change: Double)? {
        let values = weightPoints.map { $0.kilograms }
        guard let min = values.min(),
              let max = values.max(),
              let first = values.first,
              let last = values.last else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        return (average, min, max, last - first)
    }

    private var hikeTotals: (count: Int, kilometers: Double, climb: Double, minutes: Double) {
        let kilometers = hikePoints.reduce(0) { $0 + $1.distanceKilometers }
        let climb = hikePoints.reduce(0) { $0 + $1.elevationGainMeters }
        let minutes = hikePoints.reduce(0) { $0 + $1.durationMinutes }
        return (hikePoints.count, kilometers, climb, minutes)
    }

    private var weightDomain: ClosedRange<Double> {
        let values = weightPoints.map { $0.kilograms }
        guard let min = values.min(), let max = values.max() else { return 0...1 }
        let padding = Swift.max((max - min) * 0.15, 0.5)
        return (min - padding)...(max + padding)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("范围", selection: $scope) {
                        ForEach(Scope.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                weightChartSection
                hikeChartSection
                statsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("回顾")
        }
    }

    @ViewBuilder
    private var weightChartSection: some View {
        Section("体重曲线") {
            if weightPoints.count >= 2 {
                Chart {
                    ForEach(weightPoints, id: \.objectID) { entry in
                        LineMark(
                            x: .value("日期", entry.date),
                            y: .value("体重", entry.kilograms)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.accentColor)

                        PointMark(
                            x: .value("日期", entry.date),
                            y: .value("体重", entry.kilograms)
                        )
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(20)
                    }
                }
                .chartYScale(domain: weightDomain)
                .frame(height: 200)
                .accessibilityLabel("体重变化曲线，共 \(weightPoints.count) 个样本")
            } else {
                Text("至少要有两次体重记录才能画出曲线")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var hikeChartSection: some View {
        Section("每周爬山") {
            if weeklyHikes.isEmpty {
                Text("这个区间没有爬山记录")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                Chart(weeklyHikes) { bucket in
                    BarMark(
                        x: .value("周", bucket.weekStart, unit: .weekOfYear),
                        y: .value("距离", bucket.kilometers)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)
                }
                .frame(height: 180)
                .accessibilityLabel("每周爬山距离柱状图，共 \(weeklyHikes.count) 周")
            }
        }
    }

    @ViewBuilder
    private var statsSection: some View {
        Section("统计") {
            if let summary = weightSummary {
                StatRow(title: "体重记录", value: "\(weightPoints.count) 条")
                StatRow(title: "平均体重", value: "\(Fmt.kg(summary.average)) kg")
                StatRow(title: "最轻 / 最重", value: "\(Fmt.kg(summary.min)) / \(Fmt.kg(summary.max)) kg")
                StatRow(title: "区间变化", value: "\(Fmt.signedKg(summary.change)) kg")
            } else {
                Text("暂无体重数据")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            StatRow(title: "爬山次数", value: "\(hikeTotals.count) 次")
            StatRow(title: "总距离", value: "\(Fmt.km(hikeTotals.kilometers)) km")
            StatRow(title: "总爬升", value: "\(Fmt.meters(hikeTotals.climb)) m")
            StatRow(title: "总用时", value: Fmt.minutes(hikeTotals.minutes))
        }
    }
}
