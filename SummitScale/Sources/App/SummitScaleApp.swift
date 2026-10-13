import CoreData
import SwiftUI

@main
struct SummitScaleApp: App {
    private let persistence = Persistence.shared

    init() {
        // v0.1 的旧爬山记录搬进统一的活动表，只跑一次。
        Persistence.shared.migrateLegacyHikesIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ThemedRootView {
                RootView()
                    .environment(\.managedObjectContext, persistence.container.viewContext)
                    // 全 App 统一强调色：Theme.accent（系统蓝）。
                    // 不设的话最外层与内层可能各走一套强调色，同屏打架。
                    .tint(Theme.accent)
            }
        }
    }
}

/// 数据为空时先走引导，档案填完就直接进主界面。
struct RootView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)],
        animation: .default
    )
    private var profiles: FetchedResults<UserProfile>

    @State private var skipOnboarding = false

    private var needsOnboarding: Bool {
        guard !skipOnboarding else { return false }
        guard let profile = profiles.first else { return true }
        return !profile.isComplete
    }

    var body: some View {
        Group {
            if needsOnboarding {
                OnboardingView { skipOnboarding = true }
            } else {
                RootTabView()
            }
        }
    }
}
