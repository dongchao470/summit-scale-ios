import SwiftUI

/// 「健康数据自检」：把「健康」里近 7 天的步数 / 活跃消耗 / 步行距离 / 锻炼样本数摊开，
/// 并报出本地已落库的条数。
///
/// 用途：App 里「导入了但运动记录还是空」的时候先看这一页——
/// 步数、步行距离、活跃消耗都是 iPhone 自动记的；只有「锻炼」那一列非 0，
/// 才说明「健康」里有真正的锻炼样本（HKWorkout）。
struct HealthSelfCheckView: View {
    private static let days = 7

    @ObservedObject private var health = HealthKitManager.shared
    @State private var rows: [DayRow] = []
    @State private var storedWorkouts = 0
    @State private var storedDaily = 0
    @State private var status = "读取中…"

    private struct DayRow: Identifiable {
        let id = UUID()
        let day: String
        let steps: Int
        let kcal: Int
        let kilometers: Double
        let workouts: Int
    }

    var body: some View {
        List {
            Section {
                if rows.isEmpty {
                    Text(status).font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.day).font(.footnote.monospaced())
                            Text("步 \(row.steps) · 消耗 \(row.kcal) kcal · 距离 \(String(format: "%.1f", row.kilometers)) km · 锻炼 \(row.workouts) 条")
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("近 7 天「健康」原始数据")
            } footer: {
                Text("步数、步行+跑步距离、活跃消耗都是 iPhone 自动记的。「锻炼」列为 0 就说明「健康」里没有锻炼样本，App 会改用当天的步数与消耗汇总成一条「日常活动」。")
            }

            Section("本地落库") {
                LabeledContent("已导入锻炼", value: "\(storedWorkouts) 条")
                LabeledContent("日常活动汇总", value: "\(storedDaily) 天")
            }

            Section("开关") {
                LabeledContent("健康读取", value: health.enabled ? "开" : "关")
                LabeledContent("健康活跃消耗计入消耗", value: health.activitySync ? "开" : "关")
                LabeledContent("版本", value: Self.appVersion)
            }

            HeartRateSelfCheckSection()
        }
        .listStyle(.insetGrouped)
        .navigationTitle("健康数据自检")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short)(\(build))"
    }

    @MainActor
    private func load() {
        status = "读取中…"
        rows = []

        var steps: [(day: Date, steps: Double)]?
        var energy: [(day: Date, kcal: Double)]?
        var distance: [(day: Date, kilometers: Double)]?
        var workouts: [HealthKitManager.WorkoutRecord]?

        @MainActor func render() {
            guard let stepsValue = steps, let energyValue = energy,
                  let distanceValue = distance, let workoutsValue = workouts else { return }

            let calendar = Calendar.current
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd"
            let stepMap = Dictionary(stepsValue.map { (calendar.startOfDay(for: $0.day), $0.steps) }, uniquingKeysWith: { first, _ in first })
            let energyMap = Dictionary(energyValue.map { (calendar.startOfDay(for: $0.day), $0.kcal) }, uniquingKeysWith: { first, _ in first })
            let kilometerMap = Dictionary(distanceValue.map { (calendar.startOfDay(for: $0.day), $0.kilometers) }, uniquingKeysWith: { first, _ in first })
            let workoutMap = Dictionary(grouping: workoutsValue) { calendar.startOfDay(for: $0.start) }.mapValues { $0.count }

            let today = calendar.startOfDay(for: Date())
            var built: [DayRow] = []
            for offset in stride(from: Self.days - 1, through: 0, by: -1) {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                built.append(DayRow(
                    day: formatter.string(from: day),
                    steps: Int(stepMap[day] ?? 0),
                    kcal: Int(energyMap[day] ?? 0),
                    kilometers: kilometerMap[day] ?? 0,
                    workouts: workoutMap[day] ?? 0
                ))
            }
            let counts = WorkoutSync.storedCounts()
            rows = built
            storedWorkouts = counts.workouts
            storedDaily = counts.daily
            status = ""
        }

        health.recentWorkouts(days: Self.days) { records in
            workouts = records
            render()
        }
        health.dailySteps(days: Self.days) { points in
            steps = points
            render()
        }
        health.dailyActiveEnergy(days: Self.days) { points in
            energy = points
            render()
        }
        health.dailyWalkingDistance(days: Self.days) { points in
            distance = points
            render()
        }
    }
}

/// 只干一件事：把近 7 天的心率采样摊开，好判断「拿不到心率」是没权限还是健康里就没数据。
private struct HeartRateSelfCheckSection: View {
    private static let days = 7

    @State private var dayCount = 0
    @State private var latestLabel = "—"
    @State private var latestBpm = "—"

    var body: some View {
        Section {
            LabeledContent("有采样的天数", value: "\(dayCount) / \(Self.days) 天")
            LabeledContent("最近一次采样 \(latestLabel)", value: latestBpm)
        } header: {
            Text("心率（近 7 天）")
        } footer: {
            Text("心率靠设备自动采样。这里全是 0 天或「—」，说明「健康」这段时间就没有心率数据（没戴设备、没授权、或传感器没记录），App 不会凭空生成。")
        }
        .onAppear {
            HealthKitManager.shared.dailyHeartRate(days: Self.days) { points in
                dayCount = points.count
                guard let last = points.last else { return }
                let formatter = DateFormatter()
                formatter.dateFormat = "M月d日"
                latestLabel = formatter.string(from: last.day)
                latestBpm = "平均 \(Int(last.average.rounded())) · 最高 \(Int(last.maximum.rounded())) bpm"
            }
        }
    }
}
