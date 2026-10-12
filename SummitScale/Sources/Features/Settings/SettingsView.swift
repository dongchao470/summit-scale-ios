import SwiftUI

/// 设置页：外观、健康数据接入、关于。
/// 由「我的」页右上角齿轮以 NavigationLink 推入，所以这里不再自带 NavigationStack。
struct SettingsView: View {
    @State private var appearance = AppearanceMode.current
    @ObservedObject private var health = HealthKitManager.shared

    var body: some View {
        List {
            appearanceSection
            healthSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        Section {
            Picker("外观", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: appearance) { mode in
                mode.activate()
            }
        } header: {
            sectionHeader("外观", symbol: "circle.lefthalf.filled")
        } footer: {
            Text("跟随系统时，会随 iOS 的浅色/深色自动切换。")
                .font(.caption)
        }
    }

    // MARK: - 健康数据

    private var healthSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { health.enabled },
                set: { on in
                    if on {
                        health.requestAccess()
                    } else {
                        health.disable()
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("接入 Apple 健康")
                    Text(health.statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tint(Theme.accent)

            if health.enabled {
                Toggle("体重双向同步", isOn: $health.weightSync)
                    .tint(Theme.accent)
                Toggle("步数与锻炼计入消耗", isOn: $health.activitySync)
                    .tint(Theme.accent)
                Toggle("睡眠辅助分析", isOn: $health.sleepSync)
                    .tint(Theme.accent)
            }
        } header: {
            sectionHeader("健康数据", symbol: "heart.text.square")
        } footer: {
            Text("体重会与「健康」App 双向同步，步数/锻炼计入每日消耗，睡眠用于趋势参考。数据只在本机处理。")
                .font(.caption)
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section {
            infoRow("版本", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            infoRow("本地食物库", "\(FoodLibrary.items.count) 条")
            infoRow("联网搜索", "Open Food Facts")

            Text("热量按 Mifflin-St Jeor 公式估算，运动消耗按 MET 计算，都只是参考值，不构成医疗建议。联网搜到的包装食品营养数据由 Open Food Facts 提供，可能有个别录入误差。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            sectionHeader("关于", symbol: "info.circle")
        }
    }

    // MARK: - 小工具

    private func sectionHeader(_ text: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.accent)
                .accessibilityHidden(true)
            Text(text)
        }
        .textCase(nil)
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
}
