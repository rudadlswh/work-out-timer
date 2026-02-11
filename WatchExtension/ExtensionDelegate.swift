import HealthKit
import WatchKit

final class ExtensionDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        startWorkout(with: workoutConfiguration)
    }

    private func startWorkout(with workoutConfiguration: HKWorkoutConfiguration) {
        DispatchQueue.main.async {
            WatchWorkoutManager.shared.startWorkout(configuration: workoutConfiguration)
        }
    }
}
