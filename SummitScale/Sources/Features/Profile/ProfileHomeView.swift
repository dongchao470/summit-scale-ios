import CoreData
import SwiftUI

/// 我的页：档案、套餐模板、数据说明。
struct ProfileHomeView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)],
        animation: .default
    )
    private var profiles: FetchedResults<UserProfile>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "sortIndex", ascending: true)],
        animation: .default
    )
    private var templates: FetchedResults<MealTemplate>

    @FetchRequest(sortDescriptors: WeightEntry.dateDescending, animation: .default)
    private var weights: FetchedResults<WeightEntry>

    @State private var showProfileEditor = false

    private var profile: UserProfile? { profiles.first }

    private var currentKilograms: Double? { weights.first?.kilograms }

    var body: some View {
        NavigationStack {
            List {
                profileHeroSection
                profileSection
                templateSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("我的")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .accessibilityLabel("设置")
                    }
                }
            }
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorView()
            }
        }
    }

    // MARK: - 档案卡（头像 + 目标进度）

    /// 顶部一张档案卡：头像取名字首字，右侧名字与目标体重进度，点整卡进编辑。
    @ViewBuilder
    private var profileHeroSection: some View {
        if let profile = profile {
            Section {
                Button {
                    showProfileEditor = true
                } label: {
                    HStack(spacing: 14) {
                        Text(avatarInitial(profile))
                            .font(.title2.weight(.semibold))
                            .foregroundColor(Theme.accent)
                            .frame(width: 54, height: 54)
                            .background(Theme.accent.opacity(0.12))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.name.isEmpty ? "还没填称呼" : profile.name)
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.primary)
                            Text(targetSummary(profile))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(Color(uiColor: .tertiaryLabel))
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑档案，\(profile.name.isEmpty ? "未填称呼" : profile.name)")
            }
        }
    }

    /// 头像里显示的字：名字首字，空就用「你」。
    private func avatarInitial(_ profile: UserProfile) -> String {
        let name = profile.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "你" : String(name.prefix(1))
    }

    /// 档案卡副标题：目标体重 + 距目标还差多少。
    private func targetSummary(_ profile: UserProfile) -> String {
        let target = profile.targetWeightKilograms
        guard let current = currentKilograms else {
            return "目标 \(Fmt.kg(target)) kg"
        }
        let diff = current - target
        if abs(diff) < 0.05 {
            return "目标 \(Fmt.kg(target)) kg · 已达标"
        }
        return "目标 \(Fmt.kg(target)) kg · 还差 \(Fmt.kg(abs(diff))) kg"
    }

    // MARK: - 档案

    private var profileSection: some View {
        Section {
            if let profile = profile {
                infoRow("性别", profile.sexValue.title)
                infoRow("年龄", "\(age(from: profile.birthDate)) 岁")
                infoRow("身高", "\(Fmt.height(profile.heightCentimeters)) cm")
                infoRow("当前体重", currentKilograms.map { "\(Fmt.kg($0)) kg" } ?? "还没记")
                infoRow("活动量", profile.activityValue.title)

                if let budget = Persistence.shared.calorieBudget(for: profile, currentKilograms: currentKilograms) {
                    HStack(spacing: 8) {
                        StatTile(title: "基础代谢", value: Fmt.kcal(budget.bmr), unit: "kcal")
                        StatTile(title: "总消耗", value: Fmt.kcal(budget.tdee), unit: "kcal")
                        StatTile(
                            title: "每日目标",
                            value: Fmt.kcal(budget.intakeTarget),
                            unit: "kcal",
                            tint: Theme.accent
                        )
                    }
                    .padding(.vertical, 6)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("还没有身体数据")
                        .font(.subheadline.weight(.semibold))
                    Text("填上身高、体重和目标，才能算出一天该吃多少。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "person.text.rectangle")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.accent)
                    .accessibilityHidden(true)
                Text("档案")
                Spacer()
                Button("编辑") { showProfileEditor = true }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Theme.accent)
                    .accessibilityLabel("编辑档案")
            }
            .textCase(nil)
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
        }
        .accessibilityElement(children: .combine)
    }

    private func age(from birthDate: Date) -> Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
    }

    // MARK: - 套餐

    private var templateSection: some View {
        Section {
            if templates.isEmpty {
                Text("把「早餐固定就那几样」配成套餐，之后一键入账，还能到点自动填。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(templates) { template in
                    HStack(spacing: 10) {
                        Image(systemName: template.meal.symbol)
                            .font(.footnote)
                            .foregroundColor(Theme.accent)
                            .frame(width: 22)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .font(.subheadline.weight(.medium))
                            Text("\(template.meal.title) · \(template.itemCount) 样 · \(Fmt.kcal(template.totalKcal)) 千卡")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer(minLength: 4)

                        if template.autoFillEnabled {
                            Label(template.autoFillTimeText, systemImage: "clock")
                                .labelStyle(.titleAndIcon)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            NavigationLink {
                TemplateListView()
            } label: {
                Text(templates.isEmpty ? "配一个套餐" : "管理套餐")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.accent)
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.accent)
                    .accessibilityHidden(true)
                Text("固定套餐")
            }
            .textCase(nil)
        }
    }

}
