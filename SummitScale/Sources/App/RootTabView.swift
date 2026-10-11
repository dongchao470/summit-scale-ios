import SwiftUI

/// 右下角加号能开的三个入口。
enum QuickAction: String, Identifiable, CaseIterable {
    case food
    case activity
    case weight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: return "记饮食"
        case .activity: return "记运动"
        case .weight: return "记体重"
        }
    }

    var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .activity: return "figure.walk"
        case .weight: return "scalemass"
        }
    }

    var tint: Color {
        switch self {
        case .food: return Theme.accent
        case .activity: return Theme.success
        case .weight: return Theme.fat
        }
    }
}

/// 三个主页面 + 一个全局加号。
///
/// 首页本来就会显示「今天吃了什么」，另一个 Tab 再叫「记录」纯属重复，
/// 所以记录动作统一收进右下角加号，Tab 让给趋势和我的。
struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase

    @FetchRequest(
        sortDescriptors: WeightEntry.dateDescending,
        animation: .default
    )
    private var weights: FetchedResults<WeightEntry>

    @State private var selection = 0
    @State private var quickAction: QuickAction?
    @State private var isMenuOpen = false
    @State private var autoFillNotice: String?
    /// 到点、等着用户点头的套餐；非空就会弹确认框。
    @State private var pendingTemplates: [MealTemplate] = []

    private var bodyKilograms: Double {
        weights.first?.kilograms ?? 60
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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

            if isMenuOpen {
                // 展开快捷记录时把整页压暗模糊，点空白处收起，避免误点到下面的卡片。
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            isMenuOpen = false
                        }
                    }
            }

            quickAdd
                .padding(.trailing, 18)
                .padding(.bottom, 62)
        }
        .sheet(item: $quickAction) { action in
            switch action {
            case .food:
                AddFoodSheet()
            case .activity:
                ActivityEditorView(bodyKilograms: bodyKilograms)
            case .weight:
                AddWeightSheet(defaultKilograms: bodyKilograms)
            }
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
        }
        .onChange(of: scenePhase) { phase in
            // 从后台回来也查一次，避免早上开了 App 晚上才补账。
            if phase == .active { checkAutoFill() }
        }
    }

    // MARK: - 悬浮加号

    private var quickAdd: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if isMenuOpen {
                ForEach(QuickAction.allCases) { action in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            isMenuOpen = false
                        }
                        quickAction = action
                    } label: {
                        HStack(spacing: 8) {
                            Text(action.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.regularMaterial, in: Capsule())

                            Image(systemName: action.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: Theme.minTouch, height: Theme.minTouch)
                                .background(action.tint, in: Circle())
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(action.title)
                    }
                }
                .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
            }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                    isMenuOpen.toggle()
                }
            } label: {
                Image(systemName: isMenuOpen ? "xmark" : "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        LinearGradient(
                            colors: [Theme.accent, Theme.accent.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
                    .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 5)
            }
            .accessibilityLabel(isMenuOpen ? "收起快捷记录" : "打开快捷记录")
        }
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
