import SwiftUI

/// 右下角加号能开的三个入口。
/// 三个主页面，记录动作收在各页右上角菜单。
struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase

    @FetchRequest(
        sortDescriptors: WeightEntry.dateDescending,
        animation: .default
    )
    private var weights: FetchedResults<WeightEntry>

    @State private var selection = 0
    @State private var autoFillNotice: String?
    /// 到点、等着用户点头的套餐；非空就会弹确认框。
    @State private var pendingTemplates: [MealTemplate] = []

    private var bodyKilograms: Double {
        weights.first?.kilograms ?? 60
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("今日", systemImage: "flame.fill") }
                .tag(0)

            TrendsView()
                .tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }
                .tag(1)

            ProfileHomeView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(2)
        }
        .confirmationDialog(
            autoFillPrompt,
            isPresented: Binding(
                get: { !pendingTemplates.isEmpty },
                set: { if !$0 { pendingTemplates = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("记进今天") {
                let names = Persistence.shared.applyAutoFills(pendingTemplates)
                pendingTemplates = []
                guard !names.isEmpty else { return }
                autoFillNotice = "已按套餐补上：" + names.joined(separator: "、")
            }
            Button("今天不用", role: .cancel) {
                // 用户明确说不要，就记下今天已经处理过，别每次回前台都再问。
                Persistence.shared.skipAutoFills(pendingTemplates)
                pendingTemplates = []
            }
        } message: {
            Text(autoFillDetail)
        }
        .alert(
            "套餐已补记",
            isPresented: Binding(
                get: { autoFillNotice != nil },
                set: { if !$0 { autoFillNotice = nil } }
            )
        ) {
            Button("知道了") { autoFillNotice = nil }
        } message: {
            Text(autoFillNotice ?? "")
        }
        .task {
            // 用户先前拒过通知权限、后来去系统设置里打开了的话，
            // 之前没排上的提醒不会自己回来，这里补排一次。
            Reminders.resyncAll(Persistence.shared.allTemplates())
            checkAutoFill()
            syncWorkouts()
            // 顺带排一轮后台刷新：上次退后台若没排上（崩溃或被强杀），这里补回来。
            BackgroundRefresh.schedule()
        }
        .onChange(of: scenePhase) { phase in
            // 从后台回来也查一次，避免早上开了 App 晚上才补账。
            if phase == .active {
                checkAutoFill()
                syncWorkouts()
            } else if phase == .background {
                // 退到后台时排一轮后台刷新：不打开 App 也要让桌面 widget 有新数字。
                BackgroundRefresh.schedule()
            }
        }
    }

    /// 开过健康同步就把「健康」里的新锻炼补进运动记录；按 workout UUID 去重，重复调用无害。
    private func syncWorkouts() {
        guard HealthKitManager.shared.enabledByUser else { return }
        WorkoutSync.importRecent(days: 30)
    }

    // MARK: - 到点补填

    /// 只把到点的套餐挑出来问一句，真正写库要等用户点「记进今天」。
    private func checkAutoFill() {
        // 确认框已经开着的时候别再覆盖，免得把用户正看着的列表换掉。
        guard pendingTemplates.isEmpty else { return }
        pendingTemplates = Persistence.shared.pendingAutoFills()
    }

    private var autoFillPrompt: String {
        pendingTemplates.count == 1
            ? "「\(pendingTemplates[0].name)」到点了，要记进今天吗？"
            : "有 \(pendingTemplates.count) 个套餐到点了，要记进今天吗？"
    }

    private var autoFillDetail: String {
        pendingTemplates
            .map { "\($0.name)：\($0.itemCount) 样，约 \(Int($0.totalKcal.rounded())) 千卡" }
            .joined(separator: "\n")
    }
}
