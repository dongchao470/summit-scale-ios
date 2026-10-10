import SwiftUI

/// 从库里挑出来的食物。本地库和联网结果统一成这一种，上层不用关心来源。
struct PickedFood: Identifiable, Hashable {
    let id: String
    let name: String
    let brand: String?
    let category: String
    let imageURL: String?
    let kcalPer100: Double
    let proteinPer100: Double
    let carbsPer100: Double
    let fatPer100: Double
    /// 常见一份的克数，联网食物没有这个概念，按 100 克算。
    let commonGrams: Double
    let commonLabel: String
    let isRemote: Bool

    init(item: FoodItem) {
        id = item.id
        name = item.name
        brand = nil
        category = item.category
        imageURL = nil
        kcalPer100 = item.kcalPer100g
        proteinPer100 = item.proteinPer100g
        carbsPer100 = item.carbsPer100g
        fatPer100 = item.fatPer100g
        commonGrams = item.commonGrams
        commonLabel = item.commonLabel
        isRemote = false
    }

    init(remote: RemoteFood) {
        id = remote.id
        name = remote.name
        brand = remote.brand
        category = "联网"
        imageURL = remote.imageURL
        kcalPer100 = remote.kcalPer100
        proteinPer100 = remote.proteinPer100
        carbsPer100 = remote.carbsPer100
        fatPer100 = remote.fatPer100
        commonGrams = 100
        commonLabel = "100 g"
        isRemote = true
    }

    /// 列表里显示的完整名称：品牌跟在后面。
    var displayName: String {
        guard let brand = brand, !brand.isEmpty else { return name }
        return "\(brand) \(name)"
    }

    func kcal(grams: Double) -> Double { kcalPer100 * grams / 100 }
    func protein(grams: Double) -> Double { proteinPer100 * grams / 100 }
    func carbs(grams: Double) -> Double { carbsPer100 * grams / 100 }
    func fat(grams: Double) -> Double { fatPer100 * grams / 100 }
}

/// 食物缩略图。联网食物有图就显示图，没有就退回占位图标，不留白洞。
struct FoodThumb: View {
    let urlString: String?
    var size: CGFloat = 46

    var body: some View {
        Group {
            if let urlString = urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    default:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        Image(systemName: "fork.knife")
            .font(.system(size: size * 0.38))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
    }
}

/// 选食物：本地家常菜库（305 条）+ 联网搜包装食品。
///
/// 本地库覆盖中餐家常菜 —— 联网那份中文数据几乎只有包装食品，
/// 两边的强项正好互补，所以搜索框一次给两边，各占一段。
struct FoodPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// 挑中之后把结果交回调用方。
    var onPick: (PickedFood) -> Void

    @State private var query = ""
    @State private var category = "全部"
    @State private var remoteResults: [RemoteFood] = []
    @State private var remoteKeyword = ""
    @State private var isSearchingRemote = false
    @State private var remoteError: String?

    private var localItems: [FoodItem] {
        let found = FoodLibrary.search(query)
        let filtered = category == "全部" ? found : found.filter { $0.category == category }
        return Array(filtered.prefix(query.isEmpty && category == "全部" ? 30 : 80))
    }

    private var isBrowsingAll: Bool { query.isEmpty && category == "全部" }

    var body: some View {
        NavigationStack {
            List {
                localSection
                remoteSection
            }
            .listStyle(.insetGrouped)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜食物，比如番茄炒蛋、可乐"
            )
            .onSubmit(of: .search) {
                Task { await searchRemote() }
            }
            .navigationTitle("选食物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    // MARK: - 本地库

    @ViewBuilder
    private var localSection: some View {
        Section {
            if isBrowsingAll {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        categoryChip("全部")
                        ForEach(FoodLibrary.categories, id: \.self) { name in
                            categoryChip(name)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            if localItems.isEmpty {
                Text(query.isEmpty ? "这个分类还没有数据。" : "本地库里没找到「\(query)」。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(localItems) { item in
                    Button {
                        onPick(PickedFood(item: item))
                        dismiss()
                    } label: {
                        foodRow(
                            name: item.name,
                            subtitle: "\(item.category) · 一份 \(item.commonLabel) \(Fmt.grams(item.commonGrams)) g",
                            kcalPer100: item.kcalPer100g,
                            imageURL: nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text(isBrowsingAll ? "本地食物库（\(FoodLibrary.items.count) 条）" : "本地结果 \(localItems.count) 条")
        } footer: {
            if !isBrowsingAll {
                Text("家常菜都在本地库里，不吃流量也不怕断网。")
            }
        }
    }

    private func categoryChip(_ name: String) -> some View {
        Button {
            category = name
        } label: {
            Text(name)
                .font(.footnote.weight(category == name ? .semibold : .regular))
                .foregroundColor(category == name ? .white : .primary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    category == name
                        ? AnyShapeStyle(Theme.accent)
                        : AnyShapeStyle(Color(uiColor: .tertiarySystemGroupedBackground))
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(category == name ? [.isSelected] : [])
    }

    // MARK: - 联网

    @ViewBuilder
    private var remoteSection: some View {
        Section {
            if remoteKeyword.isEmpty {
                Button {
                    Task { await searchRemote() }
                } label: {
                    Label("联网搜包装食品（带图片和条码）", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.subheadline)
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else if isSearchingRemote {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在联网找「\(remoteKeyword)」…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else if let error = remoteError {
                VStack(alignment: .leading, spacing: 6) {
                    Text("联网没成功：\(error)")
                        .font(.footnote)
                        .foregroundColor(Theme.warning)
                    Button("再试一次") {
                        Task { await searchRemote() }
                    }
                    .font(.footnote.weight(.semibold))
                }
            } else if remoteResults.isEmpty {
                Text("联网也没搜到「\(remoteKeyword)」，试试换个说法或者用本地库。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(remoteResults) { food in
                    Button {
                        onPick(PickedFood(remote: food))
                        dismiss()
                    } label: {
                        foodRow(
                            name: food.name,
                            subtitle: food.subtitle,
                            kcalPer100: food.kcalPer100,
                            imageURL: food.imageURL
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("联网结果")
        } footer: {
            Text("数据来自 Open Food Facts。中文库以包装食品为主，家常菜请用上面的本地库。")
        }
    }

    // MARK: - 行

    private func foodRow(
        name: String,
        subtitle: String,
        kcalPer100: Double,
        imageURL: String?
    ) -> some View {
        HStack(spacing: 12) {
            FoodThumb(urlString: imageURL)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.kcal(kcalPer100))
                    .font(Theme.number(16))
                    .foregroundColor(kcalPer100 > 0 ? .primary : .secondary)
                Text("kcal/100g")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minHeight: Theme.minTouch)
        .contentShape(Rectangle())
    }

    private func searchRemote() async {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        remoteKeyword = keyword
        isSearchingRemote = true
        remoteError = nil
        defer { isSearchingRemote = false }
        do {
            remoteResults = try await FoodSearchService.shared.search(keyword)
        } catch {
            remoteResults = []
            remoteError = error.localizedDescription
        }
    }
}
