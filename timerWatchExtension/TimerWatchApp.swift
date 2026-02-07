import SwiftUI

@main
struct TimerWatchApp: App {
    @StateObject private var workoutManager = WatchWorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(workoutManager)
        }
    }
}
