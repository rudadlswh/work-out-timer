import SwiftUI

@main
struct TimerWatchApp: App {
    @WKApplicationDelegateAdaptor(ExtensionDelegate.self) private var extensionDelegate
    @StateObject private var workoutManager = WatchWorkoutManager.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(workoutManager)
        }
    }
}
