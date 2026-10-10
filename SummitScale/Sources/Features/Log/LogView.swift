import CoreData
import SwiftUI

/// 记录页：饮食、运动、体重三类都能翻，也能删。
struct LogView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case food
        case activity
        case weight

        var id: String { rawValue }

        var title: String {
            switch self {
            case .food: return "饮食"
            case .activity: return "运动"
            case .weight: return "体重"
            }
        }
    }

    @State private var segment: Segment = .food
    @State private var showFoodSheet = false
    @State private var showActivitySheet = false
    @State private var showWeightSheet = false

    @FetchRequest(sortDescriptors: FoodEntry.dateDescending, animation: .default)
    private var foods: FetchedResults<FoodEntry>

    @FetchRequest(sortDescriptors: ActivityEntry.dateDescending, animation: .default)
    private var activities: FetchedResults<ActivityEntry>

    @FetchRequest(sortDescriptors: WeightEntry.dateDescending, animation: .default)
    private var weights: FetchedResults<WeightEntry>

    private var latestKilograms: Double {
        weights.first?.kilograms ?? 60
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("类型", selection: $segment) {
                        ForEach(Segment.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch segment {
                case .food: foodSection
                case .activity: activitySection
                case .weight: weightSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("记录")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: presentEditor) {
                        Label("新增\(segment.title)记录", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showFoodSheet) {
                AddFoodSheet(defaultMeal: AddFoodSheet.suggestedMeal())
            }
            .sheet(isPresented: $showActivitySheet) {
                ActivityEditorView(bodyKilograms: latestKilograms)
            }
            .sheet(isPresented: $showWeightSheet) {
                AddWeightSheet(defaultKilograms: latestKilograms)
            }
        }
    }

    // MARK: - 分区

    @ViewBuilder
    private var foodSection: some View {
        if foods.isEmpty {
            emptyHint("还没有饮食记录。点右上角加号，从食物库挑一样。")
        } else {
            Section("共 \(foods.count) 条") {
                ForEach(foods) { entry in
                    row(
                        title: entry.name,
                        subtitle: "\(entry.mealValue.title) · \(Fmt.relativeDay(entry.date)) · \(Fmt.grams(entry.grams)) g",
                        trailing: Fmt.kcal(entry.kcal),
                        unit: "kcal"
                    )
                }
                .onDelete { offsets in remove(offsets, from: foods) }
            }
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        if activities.isEmpty {
            emptyHint("还没有运动记录。爬山、走路、跑步都记在这里。")
        } else {
            Section("共 \(activities.count) 条") {
                ForEach(activities) { entry in
                    row(
                        title: entry.displayTitle,
                        subtitle: activitySubtitle(entry),
                        trailing: entry.kcal > 0 ? Fmt.kcal(entry.kcal) : "—",
                        unit: "kcal"
                    )
                }
                .onDelete { offsets in remove(offsets, from: activities) }
            }
        }
    }

    @ViewBuilder
    private var weightSection: some View {
        if weights.isEmpty {
            emptyHint("还没有体重记录。点右上角加号记第一次。")
        } else {
            Section("共 \(weights.count) 条") {
                ForEach(weights) { entry in
                    row(
                        title: "\(Fmt.kg(entry.kilograms)) kg",
                        subtitle: weightSubtitle(entry),
                        trailing: entry.note ?? "—",
                        unit: ""
                    )
                }
                .onDelete { offsets in remove(offsets, from: weights) }
            }
        }
    }

    // MARK: - 小组件

    private func row(title: String, subtitle: String, trailing: String, unit: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            if !unit.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(trailing)
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !trailing.isEmpty {
                Text(trailing)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func emptyHint(_ text: String) -> some View {
        Section {
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private func activitySubtitle(_ entry: ActivityEntry) -> String {
        var parts = [Fmt.relativeDay(entry.date), Fmt.minutes(entry.durationMinutes)]
        if entry.distanceKilometers > 0 {
            parts.append("\(Fmt.km(entry.distanceKilometers)) km")
        }
        if entry.elevationGainMeters > 0 {
            parts.append("爬升 \(Fmt.meters(entry.elevationGainMeters)) m")
        }
        return parts.joined(separator: " · ")
    }

    private func weightSubtitle(_ entry: WeightEntry) -> String {
        var parts = [Fmt.relativeDay(entry.date)]
        if entry.source == "health" {
            parts.append("来自健康")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 动作

    private func presentEditor() {
        switch segment {
        case .food: showFoodSheet = true
        case .activity: showActivitySheet = true
        case .weight: showWeightSheet = true
        }
    }

    private func remove<T: NSManagedObject>(_ offsets: IndexSet, from items: FetchedResults<T>) {
        for index in offsets {
            Persistence.shared.delete(items[index])
        }
    }
}
