import Charts
import CoreData
import SwiftUI

struct TodayView: View {
    @FetchRequest(sortDescriptors: WeightEntry.dateDescending, animation: .default)
    private var weights: FetchedResults<WeightEntry>

    @FetchRequest(sortDescriptors: Hike.dateDescending, animation: .default)
    private var hikes: FetchedResults<Hike>

    @State private var showWeightSheet = false
    @State private var showHikeSheet = false

    private var latestWeight: WeightEntry? { weights.first }

    private var weightDelta: Double? {
        guard let latest = weights.first, let previous = weights.dropFirst().first else { return nil }
        return latest.kilograms - previous.kilograms
    }

    private var trendPoints: [WeightEntry] {
        let cutoff = Fmt.daysAgo(30)
        return Array(weights.filter { $0.date >= cutoff }.reversed())
    }

    private var hikesThisWeek: [Hike] {
        let start = Fmt.startOfWeek(Date())
        return hikes.filter { $0.date >= start }
    }

    private var weekDistance: Double {
        hikesThisWeek.reduce(0) { $0 + $1.distanceKilometers }
    }

    private var weekElevation: Double {
        hikesThisWeek.reduce(0) { $0 + $1.elevationGainMeters }
    }

    var body: some View {
        NavigationStack {
            List {
                weightSection
                weekSection
                lastHikeSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("今日")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showWeightSheet = true
                        } label: {
                            Label("记体重", systemImage: "scalemass")
                        }
                        Button {
                            showHikeSheet = true
                        } label: {
                            Label("记爬山", systemImage: "figure.hiking")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增记录")
                }
            }
            .sheet(isPresented: $showWeightSheet) {
                AddWeightSheet(defaultKilograms: latestWeight?.kilograms ?? 60)
            }
            .sheet(isPresented: $showHikeSheet) {
                HikeEditorView()
            }
        }
    }

    @ViewBuilder
    private var weightSection: some View {
        Section("体重") {
            if let latest = latestWeight {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Fmt.kg(latest.kilograms))
                            .font(.largeTitle.weight(.semibold))
                            .monospacedDigit()
                        Text("kg")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Spacer()
                        if let delta = weightDelta {
                            deltaBadge(delta)
                        }
                    }
                    Text("最近一次 · \(Fmt.day(latest.date))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)

                if trendPoints.count >= 2 {
                    Chart(trendPoints, id: \.objectID) { entry in
                        AreaMark(
                            x: .value("日期", entry.date),
                            y: .value("体重", entry.kilograms)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("日期", entry.date),
                            y: .value("体重", entry.kilograms)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.accentColor)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 96)
                    .accessibilityLabel("最近 30 天体重趋势")
                }
            } else {
                Text("还没有体重记录，点右上角加号开始")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var weekSection: some View {
        Section("本周爬山") {
            if hikesThisWeek.isEmpty {
                Text("这周还没有记录")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 8) {
                    metric("次数", "\(hikesThisWeek.count)", "次")
                    metric("距离", Fmt.km(weekDistance), "km")
                    metric("爬升", Fmt.meters(weekElevation), "m")
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var lastHikeSection: some View {
        if let last = hikes.first {
            Section("最近一次爬山") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(last.title)
                        .font(.body.weight(.semibold))
                    Text("\(Fmt.km(last.distanceKilometers)) km · 爬升 \(Fmt.meters(last.elevationGainMeters)) m · \(Fmt.minutes(last.durationMinutes))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text(Fmt.stamp(last.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func deltaBadge(_ delta: Double) -> some View {
        let color: Color
        let symbol: String
        if delta > 0.05 {
            color = .orange
            symbol = "arrow.up.right"
        } else if delta < -0.05 {
            color = .green
            symbol = "arrow.down.right"
        } else {
            color = .secondary
            symbol = "equal"
        }

        return HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
            Text("\(Fmt.signedKg(delta)) kg")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityLabel("较上次变化 \(Fmt.signedKg(delta)) 公斤")
    }

    private func metric(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
