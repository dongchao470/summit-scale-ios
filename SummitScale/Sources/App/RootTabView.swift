import SwiftUI

struct RootTabView: View {
    @State private var selection: Int = 0

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem {
                    Label("今日", systemImage: "sun.max")
                }
                .tag(0)

            LogView()
                .tabItem {
                    Label("记录", systemImage: "list.bullet.rectangle")
                }
                .tag(1)

            ReviewView()
                .tabItem {
                    Label("回顾", systemImage: "chart.xyaxis.line")
                }
                .tag(2)
        }
    }
}
