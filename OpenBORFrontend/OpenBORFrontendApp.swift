import SwiftUI

@main
struct OpenBORFrontendApp: App {
    @StateObject private var model = AppModel()
    
    var body: some Scene {
        WindowGroup("OpenBOR Frontend") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    model.handleStartupLaunchIfNeeded()
                }
        }
        .windowResizability(.contentSize)
    }
}
