import SwiftUI

@main
struct NovaWingApp: App {
    @StateObject private var engine = GameEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
        }
    }
}
