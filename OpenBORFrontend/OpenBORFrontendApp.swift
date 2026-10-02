import SwiftUI

@main
enum OpenBORFrontendEntry {
    @MainActor
    static func main() {
        if requestsHelp(Array(CommandLine.arguments.dropFirst())) {
            AppModel.printCLIHelp()
            return
        }
        OpenBORFrontendApp.main()
    }

    static func requestsHelp(_ arguments: [String]) -> Bool {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--help", "-h":
                return true
            case "--engine-args":
                return false
            case "--pak", "--launch", "--paks-dir", "--saves-dir", "--logs-dir",
                 "--screenshots-dir", "--engine-arg", "--metal-shader":
                // Option values, including engine flags, are not launcher commands.
                index += 1
            default:
                break
            }
            index += 1
        }
        return false
    }
}

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
