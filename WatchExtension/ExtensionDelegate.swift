import WatchKit

final class ExtensionDelegate: NSObject, WKApplicationDelegate {
    func applicationDidBecomeActive() {
        WatchWorkoutManager.shared.handleApplicationDidBecomeActive()
    }

    func applicationWillResignActive() {
        WatchWorkoutManager.shared.handleApplicationWillResignActive()
    }

    // TODO: Re-enable HealthKit after App Review fix.
}
