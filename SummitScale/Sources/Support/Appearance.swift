import SwiftUI

/// 外观三档：跟随系统 / 浅色 / 深色，UserDefaults 持久化。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static let storeKey = "appearanceMode"

    static var current: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: storeKey) ?? "") ?? .system
    }

    func activate() {
        UserDefaults.standard.set(rawValue, forKey: Self.storeKey)
    }
}

/// 主题容器：把外观开关挂到整个窗口上，设置页改动即时生效。
struct ThemedRootView<Content: View>: View {
    let content: Content
    @State private var mode = AppearanceMode.current

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .preferredColorScheme(mode.colorScheme)
            .onReceive(NotificationCenter.default.publisher(
                for: UserDefaults.didChangeNotification
            )) { _ in
                let newMode = AppearanceMode.current
                if newMode != mode { mode = newMode }
            }
    }
}
