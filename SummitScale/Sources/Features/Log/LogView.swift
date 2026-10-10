import CoreData
import SwiftUI

struct LogView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case weight = "体重"
        case hike = "爬山"

        var id: String { rawValue }
    }

    @FetchRequest(sortDescriptors: WeightEntry.dateDescending, animation: .default)
    private var weights: FetchedResults<WeightEntry>

    @FetchRequest(sortDescriptors: Hike.dateDescending, animation: .default)
    private var hikes: FetchedResults<Hike>

    @State private var kind: Kind = .weight
    @State private var showWeightSheet = false
    @State private var showHikeSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("类型", selection: $kind) {
                    ForEach(Kind.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                List {
                    if kind == .weight {
                        weightRows
                    } else {
                        hikeRows
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("记录")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if kind == .weight {
                            showWeightSheet = true
                        } else {
                            showHikeSheet = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增记录")
                }
            }
            .sheet(isPresented: $showWeightSheet) {
                AddWeightSheet(defaultKilograms: weights.first?.kilograms ?? 60)
            }
            .sheet(isPresented: $showHikeSheet) {
                HikeEditorView()
            }
        }
    }

    @ViewBuilder
    private var weightRows: some View {
        if weights.isEmpty {
            Text("暂无体重记录")
                .foregroundColor(.secondary)
        } else {
            ForEach(weights, id: \.objectID) { entry in
                weightRow(entry)
            }
            .onDelete(perform: deleteWeight)
        }
    }

    @ViewBuilder
    private var hikeRows: some View {
        if hikes.isEmpty {
            Text("暂无爬山记录")
                .foregroundColor(.secondary)
        } else {
            ForEach(hikes, id: \.objectID) { hike in
                hikeRow(hike)
            }
            .onDelete(perform: deleteHike)
        }
    }

    private func weightRow(_ entry: WeightEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.kg(entry.kilograms))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                Text("kg")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(Fmt.stamp(entry.date))
                .font(.caption)
                .foregroundColor(.secondary)
            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func hikeRow(_ hike: Hike) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hike.title)
                .font(.body.weight(.semibold))
            Text("\(Fmt.km(hike.distanceKilometers)) km · 爬升 \(Fmt.meters(hike.elevationGainMeters)) m · \(Fmt.minutes(hike.durationMinutes))")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(Fmt.stamp(hike.date))
                .font(.caption2)
                .foregroundColor(.secondary)
            if let note = hike.note, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func deleteWeight(_ offsets: IndexSet) {
        let list = Array(weights)
        for index in offsets where index < list.count {
            Persistence.shared.delete(list[index])
        }
    }

    private func deleteHike(_ offsets: IndexSet) {
        let list = Array(hikes)
        for index in offsets where index < list.count {
            Persistence.shared.delete(list[index])
        }
    }
}
