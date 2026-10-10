import CoreData
import SwiftUI

/// 套餐管理：平时一键入账，也能开着到点自动填。
struct TemplateListView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "sortIndex", ascending: true)],
        animation: .default
    )
    private var templates: FetchedResults<MealTemplate>

    @State private var isCreating = false
    @State private var editing: MealTemplate?
    @State private var notice: String?

    var body: some View {
        List {
            Section {
                Text("套餐就是「早餐固定这么吃」这种组合。平时左滑一键记到今天；打开自动填，到点会提醒你，下次开 App 自动补上。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            ForEach(MealType.allCases) { meal in
                let matched = templates.filter { $0.meal == meal }
                if !matched.isEmpty {
                    Section(meal.title) {
                        ForEach(matched) { template in
                            row(template)
                        }
                    }
                }
            }

            if templates.isEmpty {
                Section {
                    Text("还没有套餐。点右上角加一个，比如「标准早餐：鸡蛋 + 牛奶 + 全麦面包」。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("套餐")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreating = true
                } label: {
                    Label("新建", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            TemplateEditorView(template: nil)
        }
        .sheet(item: $editing) { template in
            TemplateEditorView(template: template)
        }
        .alert(
            "套餐入账",
            isPresented: Binding(
                get: { notice != nil },
                set: { if !$0 { notice = nil } }
            )
        ) {
            Button("知道了") { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    // MARK: - 行

    private func row(_ template: MealTemplate) -> some View {
        Button {
            editing = template
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(template.name)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                    Spacer(minLength: 4)
                    Text("\(Fmt.kcal(template.totalKcal)) 千卡")
                        .font(.subheadline)
                        .foregroundColor(Theme.accent)
                }

                HStack(spacing: 12) {
                    Label("\(template.itemCount) 样", systemImage: "list.bullet")
                    if template.autoFillEnabled {
                        Label(template.autoFillTimeText, systemImage: "clock.badge.checkmark")
                            .foregroundColor(Theme.success)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                let names = template.items.map { $0.name }.joined(separator: " · ")
                if !names.isEmpty {
                    Text(names)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
            .frame(minHeight: Theme.minTouch)
        }
        .swipeActions(edge: .leading) {
            Button {
                apply(template)
            } label: {
                Label("记到今天", systemImage: "text.badge.plus")
            }
            .tint(Theme.accent)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Reminders.cancel(template)
                Persistence.shared.delete(template)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func apply(_ template: MealTemplate) {
        let count = Persistence.shared.applyTemplate(template, to: Date())
        notice = count > 0
            ? "「\(template.name)」的 \(count) 样已经记到今天的\(template.meal.title)。"
            : "这个套餐还是空的，先进去加点内容。"
    }
}
