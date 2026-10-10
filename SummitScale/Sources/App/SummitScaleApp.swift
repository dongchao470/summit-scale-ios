import SwiftUI

@main
struct SummitScaleApp: App {
    private let persistence = Persistence.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
    }
}
