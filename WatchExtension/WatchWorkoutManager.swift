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
    static let shared = WatchWorkoutManager()

    @Published var currentBpm: Int?
    @Published var averageBpm: Int?
    @Published var isRunning: Bool = false
    @Published var phoneTimerState: PhoneTimerState?
    @Published var useDummyHeartRate: Bool = WatchWorkoutManager.defaultDummyHeartRateEnabled

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var wcSession: WCSession?
    private var authorizationStatus: Bool?
    private var sumBpm: Double = 0
    private var sampleCount: Int = 0
    private var isStoppingWorkout: Bool = false
    private var hasDiscardedWorkout: Bool = false
    private var hasBegunCollection: Bool = false
    private var hasRequestedMirroring: Bool = false
    private var dummyTimer: Timer?
    private var dummyBpm: Int = 95
    private var dummyDirection: Int = 1

    private static let defaultDummyHeartRateEnabled: Bool = {
    #if targetEnvironment(simulator)
        return true
    #else
        return false
    #endif
    }()

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

    private func ensureSessionActivated() {
        guard let session = wcSession else { return }
        if session.activationState != .activated {
            session.activate()
        }
    }

    private func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            authorizationStatus = false
            completion(false)
            return
        }
        let workoutType = HKObjectType.workoutType()

        if let status = authorizationStatus {
            completion(status)
            return
        }

        healthStore.requestAuthorization(toShare: [workoutType], read: [heartRateType]) { success, _ in
            DispatchQueue.main.async {
                self.authorizationStatus = success
                completion(success)
            }
        }
    }

    func startWorkout(configuration: HKWorkoutConfiguration? = nil) {
        if useDummyHeartRate {
            startDummyWorkout()
            return
        }
        requestAuthorizationIfNeeded { [weak self] success in
            guard let self, success else { return }
            if self.isRunning { return }
            if self.workoutSession != nil || self.workoutBuilder != nil {
                self.cleanupWorkout(clearStopFlag: true)
            }

            self.resetMetrics()
            self.hasDiscardedWorkout = false
            self.isStoppingWorkout = false
            self.hasBegunCollection = false
            self.hasRequestedMirroring = false
            let workoutConfiguration = configuration ?? {
                let configuration = HKWorkoutConfiguration()
                configuration.activityType = .other
                configuration.locationType = .indoor
                return configuration
            }()

            do {
                let session = try HKWorkoutSession(healthStore: self.healthStore, configuration: workoutConfiguration)
                let builder = session.associatedWorkoutBuilder()
                builder.dataSource = HKLiveWorkoutDataSource(healthStore: self.healthStore, workoutConfiguration: workoutConfiguration)
                session.delegate = self
                builder.delegate = self

                self.workoutSession = session
                self.workoutBuilder = builder
                self.isRunning = true

                let startDate = Date()
                session.startActivity(with: startDate)
                builder.beginCollection(withStart: startDate) { [weak self] success, _ in
                    DispatchQueue.main.async {
                        self?.hasBegunCollection = success
                        if success {
                            self?.requestMirroringIfPossible(for: session)
                        }
                    }
                }
            } catch {
                self.isRunning = false
            }
        }
    }

    func stopWorkout() {
        if useDummyHeartRate {
            stopDummyWorkout()
            return
        }
        guard let session = workoutSession, let builder = workoutBuilder else { return }
        guard !isStoppingWorkout else { return }
        isStoppingWorkout = true
        session.end()
        let endDate = Date()
        let finish: () -> Void = { [weak self] in
            guard let self else { return }
            if self.hasBegunCollection && !self.hasDiscardedWorkout {
                self.hasDiscardedWorkout = true
                builder.discardWorkout()
            }
            self.cleanupWorkout(clearStopFlag: true)
        }

        if hasBegunCollection {
            builder.endCollection(withEnd: endDate) { _, _ in
                finish()
            }
        } else {
            finish()
        }
    }

    private func resetMetrics() {
        currentBpm = nil
        averageBpm = nil
        sumBpm = 0
        sampleCount = 0
    }

    private func cleanupWorkout(clearStopFlag: Bool) {
        workoutSession = nil
        workoutBuilder = nil
        isRunning = false
        hasBegunCollection = false
        hasRequestedMirroring = false
        stopDummyHeartRate()
        if clearStopFlag {
            isStoppingWorkout = false
        }
    }

    private func updateHeartRate(_ bpm: Double) {
        let rounded = Int(bpm.rounded())
        currentBpm = rounded
        sumBpm += bpm
        sampleCount += 1
        averageBpm = Int((sumBpm / Double(sampleCount)).rounded())
        sendHeartRate(bpm)
    }

    private func startDummyWorkout() {
        if isRunning { return }
        resetMetrics()
        isRunning = true
        startDummyHeartRate()
    }

    private func stopDummyWorkout() {
        if !isRunning { return }
        stopDummyHeartRate()
        cleanupWorkout(clearStopFlag: true)
    }

    private func startDummyHeartRate() {
        stopDummyHeartRate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.isRunning else { return }
            let bpm = self.nextDummyHeartRate()
            self.updateHeartRate(Double(bpm))
        }
        RunLoop.main.add(timer, forMode: .common)
        dummyTimer = timer
    }

    private func stopDummyHeartRate() {
        dummyTimer?.invalidate()
        dummyTimer = nil
    }

    private func nextDummyHeartRate() -> Int {
        let drift = Int.random(in: -2...4)
        dummyBpm += drift * dummyDirection
        if dummyBpm > 145 {
            dummyBpm = 145
            dummyDirection = -1
        } else if dummyBpm < 75 {
            dummyBpm = 75
            dummyDirection = 1
        }
        return dummyBpm
    }

    private func sendHeartRate(_ bpm: Double) {
        guard let session = wcSession else { return }
        ensureSessionActivated()
        guard session.activationState == .activated else { return }
        let payload = ["heartRate": bpm]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func sendPong(pingId: String?) {
        guard let session = wcSession else { return }
        ensureSessionActivated()
        guard session.activationState == .activated else { return }
        var payload: [String: Any] = ["pong": true]
        if let pingId {
            payload["pingId"] = pingId
        }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func requestMirroringIfPossible(for session: HKWorkoutSession) {
        guard #available(watchOS 10.0, *) else { return }
        guard !hasRequestedMirroring else { return }
        guard hasBegunCollection, isRunning else { return }
        guard session.state == .running else { return }
        hasRequestedMirroring = true
        session.startMirroringToCompanionDevice { _, _ in }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .running {
            DispatchQueue.main.async {
                self.requestMirroringIfPossible(for: workoutSession)
            }
        }
        if toState == .ended {
            DispatchQueue.main.async {
                self.isRunning = false
                if !self.isStoppingWorkout {
                    self.cleanupWorkout(clearStopFlag: true)
                }
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isRunning = false
            if !self.isStoppingWorkout {
                self.cleanupWorkout(clearStopFlag: true)
            }
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
            var reply: [String: Any] = ["pong": true]
            if let pingId = message["pingId"] as? String {
                reply["pingId"] = pingId
            }
            replyHandler(reply)
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
        if command == "ping" {
            sendPong(pingId: message["pingId"] as? String)
            return
        }
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
        let exercise = message["exercise"] as? String ?? phoneTimerState?.exercise ?? ""

        DispatchQueue.main.async {
            if phase == "idle" || mode.isEmpty {
                self.phoneTimerState = nil
                if self.isRunning {
                    self.stopWorkout()
                }
                return
            }

            self.phoneTimerState = PhoneTimerState(
                mode: mode,
                phase: phase,
                displaySeconds: displaySeconds,
                headline: headline,
                exercise: exercise,
                updatedAt: Date()
            )

            let shouldRun = phase == "running"
            if shouldRun, !self.isRunning {
                self.startWorkout()
            } else if !shouldRun, self.isRunning {
                self.stopWorkout()
            }
        }
    }
}
