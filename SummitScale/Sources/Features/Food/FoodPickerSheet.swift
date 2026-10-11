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
    /// 打包进 App 的配图资源名。本地库配过图的才有，联网条目一律 nil。
    let imageName: String?

    init(item: FoodItem) {
        id = item.id
        name = item.name
        brand = nil
        category = item.category
        // 本地条目的图现在是打包资源，不再是远程地址。
        imageName = item.imageName
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
        // 下厨房只给菜名和图，不给营养表；先在本地库找同名菜把数值补上，
        // 补不到就留 0，记一笔页面会提示用户自己填。
        let local = remote.kcalPer100 > 0 ? nil : FoodLibrary.bestMatch(remote.name)

        id = remote.id
        name = remote.name
        brand = remote.brand
        category = local?.category ?? "联网"
        imageName = nil
        imageURL = remote.imageURL
        kcalPer100 = remote.kcalPer100 > 0 ? remote.kcalPer100 : (local?.kcalPer100g ?? 0)
        proteinPer100 = remote.proteinPer100 > 0 ? remote.proteinPer100 : (local?.proteinPer100g ?? 0)
        carbsPer100 = remote.carbsPer100 > 0 ? remote.carbsPer100 : (local?.carbsPer100g ?? 0)
        fatPer100 = remote.fatPer100 > 0 ? remote.fatPer100 : (local?.fatPer100g ?? 0)
        commonGrams = local?.commonGrams ?? 100
        commonLabel = local?.commonLabel ?? "100 g"
        isRemote = true
    }

    /// 全参数构造，只给 `replacingNutrients` 用。
    private init(
        id: String,
        name: String,
        brand: String?,
        category: String,
        imageName: String?,
        imageURL: String?,
        kcalPer100: Double,
        proteinPer100: Double,
        carbsPer100: Double,
        fatPer100: Double,
        commonGrams: Double,
        commonLabel: String,
        isRemote: Bool
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.category = category
        self.imageName = imageName
        self.imageURL = imageURL
        self.kcalPer100 = kcalPer100
        self.proteinPer100 = proteinPer100
        self.carbsPer100 = carbsPer100
        self.fatPer100 = fatPer100
        self.commonGrams = commonGrams
        self.commonLabel = commonLabel
        self.isRemote = isRemote
    }

    /// 复制一份，只换每 100 克的营养值。
    ///
    /// 联网来源经常没有营养表（下厨房干脆不返回，只有菜名和图），
    /// 靠本地同名菜兜底也未必准，所以记一笔页面得让用户自己校准一遍。
    func replacingNutrients(
        kcalPer100: Double,
        proteinPer100: Double,
        carbsPer100: Double,
        fatPer100: Double
    ) -> PickedFood {
        PickedFood(
            id: id,
            name: name,
            brand: brand,
            category: category,
            imageName: imageName,
            imageURL: imageURL,
            kcalPer100: kcalPer100,
            proteinPer100: proteinPer100,
            carbsPer100: carbsPer100,
            fatPer100: fatPer100,
            commonGrams: commonGrams,
            commonLabel: commonLabel,
            isRemote: isRemote
        )
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
/// 食物缩略图。
///
/// 三个来源按优先级取：打包进 App 的图片资源（食物库那 434 条配过图）、
/// 远程地址（联网搜出来的结果）、SF Symbol（按分类兜底）。
/// 成分表那 1503 条食材和中式成菜没有照片，走最后一档，不留空白。
struct FoodThumb: View {
    /// Assets 里的资源名，食物库条目用
    var imageName: String? = nil
    /// 远程图片地址，联网条目用
    var urlString: String? = nil
    /// 前两个都没有时显示的 SF Symbol
    var symbol: String = "fork.knife"
    var size: CGFloat = 46

    var body: some View {
        Group {
            if let imageName = imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else if let urlString = urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                    case .failure:
                        placeholder
                    default:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    }
                }
                .frame(width: size, height: size)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .stroke(Theme.separator.opacity(0.45), lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        Image(systemName: symbol)
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
            // 输入停下就自动联网，不用再手动点按钮或按回车 —— 之前入口藏在列表里，
            // 用户根本没发现，才一直以为「联网搜索没成功过」。
            .task(id: query) {
                let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard keyword.count >= 2 else {
                    remoteResults = []
                    remoteKeyword = ""
                    remoteError = nil
                    return
                }
                // 停手 0.7 秒再发，别每敲一个字打一次接口。
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                await searchRemote(keyword)
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
                            // 配过图的取打包资源（断网也有），没配图的按分类退回 SF Symbol。
                            imageName: item.imageName,
                            symbol: FoodCategorySymbol.symbol(for: item.category)
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
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(Theme.accent)
                    Text("输入两个字以上会自动联网找，数据来自下厨房（带图）。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
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
                        Task { await searchRemote(query.trimmingCharacters(in: .whitespacesAndNewlines)) }
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
                            subtitle: remoteSubtitle(food),
                            kcalPer100: PickedFood(remote: food).kcalPer100,
                            urlString: food.imageURL,
                            symbol: FoodCategorySymbol.symbol(for: "快餐")
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("联网结果")
        } footer: {
            Text("数据来自下厨房（真实菜谱图 + 菜名），家常菜中文覆盖好；它的菜谱页不给营养表，所以热量会先按本地库同名条目估，选完还能改。包装食品会再查一次 Open Food Facts。")
        }
    }

    // MARK: - 行

    /// 联网行的副标题。下厨房不给营养表，这里先用本地库同名菜估一个，
    /// 让用户在列表里直接看到大概热量，不用点进去才发现是空的。
    private func remoteSubtitle(_ food: RemoteFood) -> String {
        var parts: [String] = []
        if let brand = food.brand, !brand.isEmpty {
            parts.append(brand)
        }
        let kcal = PickedFood(remote: food).kcalPer100
        if kcal > 0 {
            parts.append("每 100 克 \(Int(kcal.rounded())) 千卡 · 估算")
        } else {
            parts.append("没有营养数据，选了自己填")
        }
        return parts.joined(separator: " · ")
    }

    private func foodRow(
        name: String,
        subtitle: String,
        kcalPer100: Double,
        imageName: String? = nil,
        urlString: String? = nil,
        symbol: String = "fork.knife"
    ) -> some View {
        HStack(spacing: 12) {
            FoodThumb(imageName: imageName, urlString: urlString, symbol: symbol)

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

    private func searchRemote(_ keyword: String) async {
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
