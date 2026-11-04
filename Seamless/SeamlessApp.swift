import SwiftUI

@main
struct SeamlessApp: App {
    #if DEBUG
    init() {
        // -demoClean hides the one-time gesture hints, for store screenshots.
        if ProcessInfo.processInfo.arguments.contains("-demoClean") {
            UserDefaults.standard.set(true, forKey: "seamless.hint.slides")
            UserDefaults.standard.set(true, forKey: "seamless.hint.shape")
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
