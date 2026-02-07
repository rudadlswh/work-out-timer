import Foundation
import HealthKit
import WatchConnectivity

struct PhoneTimerState: Equatable {
    let mode: String
    let phase: String
    let displaySeconds: Int
    let headline: String
    let exercise: String
    let updatedAt: Date
}

final class WatchWorkoutManager: NSObject, ObservableObject {
    @Published var currentBpm: Int?
    @Published var averageBpm: Int?
    @Published var isRunning: Bool = false
    @Published var phoneTimerState: PhoneTimerState?

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var wcSession: WCSession?
    private var authorizationStatus: Bool?
    private var sumBpm: Double = 0
    private var sampleCount: Int = 0

    override init() {
        super.init()
        configureConnectivity()
    }

    private func configureConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        wcSession = session
    }

    private func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            authorizationStatus = false
            completion(false)
            return
        }

        if let status = authorizationStatus {
            completion(status)
            return
        }

        healthStore.requestAuthorization(toShare: [], read: [heartRateType]) { success, _ in
            DispatchQueue.main.async {
                self.authorizationStatus = success
                completion(success)
            }
        }
    }

    func startWorkout() {
        requestAuthorizationIfNeeded { [weak self] success in
            guard let self, success else { return }
            guard self.workoutSession == nil else { return }

            self.resetMetrics()
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .other
            configuration.locationType = .indoor

            do {
                let session = try HKWorkoutSession(healthStore: self.healthStore, configuration: configuration)
                let builder = session.associatedWorkoutBuilder()
                builder.dataSource = HKLiveWorkoutDataSource(healthStore: self.healthStore, workoutConfiguration: configuration)
                session.delegate = self
                builder.delegate = self

                self.workoutSession = session
                self.workoutBuilder = builder
                self.isRunning = true

                let startDate = Date()
                session.startActivity(with: startDate)
                builder.beginCollection(withStart: startDate) { _, _ in }
            } catch {
                self.isRunning = false
            }
        }
    }

    func stopWorkout() {
        guard let session = workoutSession, let builder = workoutBuilder else { return }
        session.end()
        let endDate = Date()
        builder.endCollection(withEnd: endDate) { _, _ in
            builder.discardWorkout()
        }
        workoutSession = nil
        workoutBuilder = nil
        isRunning = false
    }

    private func resetMetrics() {
        currentBpm = nil
        averageBpm = nil
        sumBpm = 0
        sampleCount = 0
    }

    private func updateHeartRate(_ bpm: Double) {
        let rounded = Int(bpm.rounded())
        currentBpm = rounded
        sumBpm += bpm
        sampleCount += 1
        averageBpm = Int((sumBpm / Double(sampleCount)).rounded())
        sendHeartRate(bpm)
    }

    private func sendHeartRate(_ bpm: Double) {
        guard let session = wcSession else { return }
        let payload = ["heartRate": bpm]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(payload)
        }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended {
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        guard collectedTypes.contains(heartRateType) else { return }
        guard let statistics = workoutBuilder.statistics(for: heartRateType),
              let quantity = statistics.mostRecentQuantity() else { return }

        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = quantity.doubleValue(for: unit)
        DispatchQueue.main.async { [weak self] in
            self?.updateHeartRate(bpm)
        }
    }
}

extension WatchWorkoutManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleMessage(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        if let command = message["command"] as? String, command == "ping" {
            replyHandler(["pong": true])
            return
        }
        handleMessage(message)
        replyHandler(["ok": true])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleMessage(userInfo)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleMessage(applicationContext)
    }

    private func handleMessage(_ message: [String: Any]) {
        if let type = message["type"] as? String, type == "timerState" {
            handlePhoneTimerState(message)
            return
        }

        guard let command = message["command"] as? String else { return }
        DispatchQueue.main.async {
            if command == "start" {
                self.startWorkout()
            } else if command == "stop" {
                self.stopWorkout()
            }
        }
    }

    private func handlePhoneTimerState(_ message: [String: Any]) {
        let mode = message["mode"] as? String ?? ""
        let phase = message["phase"] as? String ?? ""
        let displaySeconds = message["displaySeconds"] as? Int ?? 0
        let headline = message["headline"] as? String ?? ""
        let exercise = message["exercise"] as? String ?? ""

        DispatchQueue.main.async {
            if phase == "idle" || mode.isEmpty {
                self.phoneTimerState = nil
            } else {
                self.phoneTimerState = PhoneTimerState(
                    mode: mode,
                    phase: phase,
                    displaySeconds: displaySeconds,
                    headline: headline,
                    exercise: exercise,
                    updatedAt: Date()
                )
            }
        }
    }
}
