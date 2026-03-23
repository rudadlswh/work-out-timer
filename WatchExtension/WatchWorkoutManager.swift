import Foundation
import HealthKit
import WatchConnectivity
import WatchKit
import os

struct PhoneTimerState: Equatable {
    let mode: String
    let phase: String
    let displaySeconds: Int
    let headline: String
    let exercise: String
    let updatedAt: Date
}

private enum WatchHeartRateState: String {
    case watchAppNotActive
    case authorizationRequesting
    case unauthorized
    case authorizedIdle
    case startingWorkout
    case collectingNoSamples
    case receivingLive
    case error
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
    private var sumBpm: Double = 0
    private var sampleCount: Int = 0
    private var isStoppingWorkout: Bool = false
    private var hasDiscardedWorkout: Bool = false
    private var hasBegunCollection: Bool = false
    private var hasRequestedMirroring: Bool = false
    private var hasReceivedHeartRateSample: Bool = false
    private var dummyTimer: Timer?
    private var dummyBpm: Int = 95
    private var dummyDirection: Int = 1
    private var isAppActive: Bool = WKExtension.shared().applicationState == .active
    private var pendingWorkoutConfiguration: HKWorkoutConfiguration?
    private var lastSentState: WatchHeartRateState?
    private var lastSentStateDetail: String?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.chogm.timer.watch",
        category: "WatchHeartRate"
    )

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
        logger.info("HealthKit available: \(HKHealthStore.isHealthDataAvailable(), privacy: .public)")
        logAuthorizationSnapshot(context: "init")
    }

    func handleApplicationDidBecomeActive() {
        isAppActive = true
        logger.info("Watch app became active")
        sendCurrentStateSnapshot(reason: "app active")
        resumePendingWorkoutIfNeeded()
    }

    func handleApplicationWillResignActive() {
        isAppActive = false
        logger.info("Watch app will resign active")
    }

    private func configureConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        wcSession = session
        logger.info("WCSession activation requested")
    }

    private func ensureSessionActivated() {
        guard let session = wcSession else { return }
        if session.activationState != .activated {
            logger.info("Re-activating WCSession")
            session.activate()
        }
    }

    private func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            logger.error("HealthKit unavailable for heart rate collection")
            completion(false)
            return
        }

        let workoutType = HKObjectType.workoutType()
        logger.info("Requesting HealthKit authorization")
        logAuthorizationSnapshot(context: "before request")

        healthStore.requestAuthorization(toShare: [workoutType], read: [heartRateType]) { success, error in
            self.logger.info(
                "HealthKit authorization result success=\(success, privacy: .public) error=\(error?.localizedDescription ?? "none", privacy: .public)"
            )
            self.logAuthorizationSnapshot(context: "after request")
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    func startWorkout(configuration: HKWorkoutConfiguration? = nil) {
        if useDummyHeartRate {
            startDummyWorkout()
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            sendState(.error, detail: "HealthKit 미지원")
            return
        }

        guard isAppActive else {
            pendingWorkoutConfiguration = configuration
            logger.info("Deferring workout start until watch app is active")
            sendState(.watchAppNotActive)
            return
        }

        if isRunning {
            logger.debug("Ignoring start: workout already running")
            return
        }

        if workoutSession != nil || workoutBuilder != nil {
            cleanupWorkout(clearStopFlag: true)
        }

        let workoutConfiguration = configuration ?? {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .other
            configuration.locationType = .indoor
            return configuration
        }()

        resetMetrics()
        hasDiscardedWorkout = false
        isStoppingWorkout = false
        hasBegunCollection = false
        hasRequestedMirroring = false
        hasReceivedHeartRateSample = false
        pendingWorkoutConfiguration = nil

        sendState(.authorizationRequesting)
        requestAuthorizationIfNeeded { [weak self] success in
            guard let self else { return }
            guard success else {
                self.sendState(.unauthorized)
                return
            }

            self.sendState(.authorizedIdle)
            self.beginWorkout(configuration: workoutConfiguration)
        }
    }

    func stopWorkout() {
        if useDummyHeartRate {
            stopDummyWorkout()
            return
        }

        pendingWorkoutConfiguration = nil
        guard let session = workoutSession, let builder = workoutBuilder else {
            sendState(.authorizedIdle)
            return
        }
        guard !isStoppingWorkout else { return }

        logger.info("Stopping workout session")
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
            self.sendState(.authorizedIdle)
        }

        if hasBegunCollection {
            builder.endCollection(withEnd: endDate) { success, error in
                self.logger.info(
                    "Ended collection success=\(success, privacy: .public) error=\(error?.localizedDescription ?? "none", privacy: .public)"
                )
                finish()
            }
        } else {
            finish()
        }
    }

    private func beginWorkout(configuration: HKWorkoutConfiguration) {
        logger.info("Starting HKWorkoutSession activity=\(String(describing: configuration.activityType.rawValue), privacy: .public)")
        sendState(.startingWorkout)

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            workoutSession = session
            workoutBuilder = builder
            isRunning = true

            let startDate = Date()
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { [weak self] success, error in
                guard let self else { return }
                self.logger.info(
                    "LiveWorkoutBuilder beginCollection success=\(success, privacy: .public) error=\(error?.localizedDescription ?? "none", privacy: .public)"
                )
                DispatchQueue.main.async {
                    self.hasBegunCollection = success
                    if success {
                        self.sendState(.collectingNoSamples)
                        self.requestMirroringIfPossible(for: session)
                    } else {
                        self.isRunning = false
                        self.sendState(.error, detail: error?.localizedDescription ?? "수집 시작 실패")
                    }
                }
            }
        } catch {
            logger.error("Failed to create workout session: \(error.localizedDescription, privacy: .public)")
            isRunning = false
            sendState(.error, detail: error.localizedDescription)
        }
    }

    private func resumePendingWorkoutIfNeeded() {
        guard !useDummyHeartRate else { return }
        guard isAppActive else { return }
        guard !isRunning else { return }
        guard let configuration = pendingWorkoutConfiguration else { return }

        logger.info("Resuming deferred workout start")
        pendingWorkoutConfiguration = nil
        startWorkout(configuration: configuration)
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
        hasReceivedHeartRateSample = false
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
        hasReceivedHeartRateSample = true
        logger.debug("Heart rate sample bpm=\(rounded, privacy: .public)")
        sendHeartRate(bpm)
    }

    private func startDummyWorkout() {
        if isRunning { return }
        resetMetrics()
        isRunning = true
        hasReceivedHeartRateSample = false
        sendState(.collectingNoSamples)
        startDummyHeartRate()
    }

    private func stopDummyWorkout() {
        if !isRunning { return }
        stopDummyHeartRate()
        cleanupWorkout(clearStopFlag: true)
        sendState(.authorizedIdle)
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

    private func canSendToPhone(_ session: WCSession) -> Bool {
        guard session.activationState == .activated else { return false }
        return session.isCompanionAppInstalled
    }

    private func sendHeartRate(_ bpm: Double) {
        sendPayload([
            "heartRate": bpm,
            "heartRateState": WatchHeartRateState.receivingLive.rawValue
        ], reason: "heartRate")
    }

    private func sendState(_ state: WatchHeartRateState, detail: String? = nil) {
        if lastSentState == state, lastSentStateDetail == detail {
            return
        }

        lastSentState = state
        lastSentStateDetail = detail

        var payload: [String: Any] = ["heartRateState": state.rawValue]
        if let detail, !detail.isEmpty {
            payload["heartRateDetail"] = detail
        }
        sendPayload(payload, reason: "state")
    }

    private func sendCurrentStateSnapshot(reason: String) {
        logAuthorizationSnapshot(context: reason)
        if useDummyHeartRate {
            sendState(isRunning ? .collectingNoSamples : .authorizedIdle, detail: reason)
            return
        }

        if isRunning {
            sendState(hasReceivedHeartRateSample ? .receivingLive : .collectingNoSamples, detail: reason)
            return
        }

        let workoutStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        switch workoutStatus {
        case .sharingAuthorized:
            sendState(.authorizedIdle, detail: reason)
        case .sharingDenied, .notDetermined:
            sendState(.unauthorized, detail: reason)
        @unknown default:
            sendState(.error, detail: reason)
        }
    }

    private func sendPayload(_ payload: [String: Any], reason: String) {
        guard let session = wcSession else { return }
        ensureSessionActivated()
        guard canSendToPhone(session) else {
            logger.debug("Skipping WC send reason=\(reason, privacy: .public): session not ready")
            return
        }

        let keys = payload.keys.sorted().joined(separator: ",")
        if session.isReachable {
            logger.debug("WC sendMessage reason=\(reason, privacy: .public) keys=\(keys, privacy: .public)")
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                self?.logger.error("WC sendMessage failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            do {
                logger.debug("WC updateApplicationContext reason=\(reason, privacy: .public) keys=\(keys, privacy: .public)")
                try session.updateApplicationContext(payload)
            } catch {
                logger.error("WC updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func sendPong(pingId: String?) {
        guard let session = wcSession else { return }
        ensureSessionActivated()
        guard canSendToPhone(session) else { return }

        var payload: [String: Any] = ["pong": true]
        if let pingId {
            payload["pingId"] = pingId
        }

        if session.isReachable {
            logger.debug("Sending pong pingId=\(pingId ?? "none", privacy: .public)")
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                self?.logger.error("Pong sendMessage failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            logger.debug("Queueing pong via userInfo pingId=\(pingId ?? "none", privacy: .public)")
            session.transferUserInfo(payload)
        }
    }

    private func logAuthorizationSnapshot(context: String) {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            logger.info("HK auth snapshot [\(context, privacy: .public)] unavailable")
            return
        }

        let workoutType = HKObjectType.workoutType()
        let heartRateStatus = authorizationStatusText(for: healthStore.authorizationStatus(for: heartRateType))
        let workoutStatus = authorizationStatusText(for: healthStore.authorizationStatus(for: workoutType))

        logger.info(
            "HK auth snapshot [\(context, privacy: .public)] heartRate=\(heartRateStatus, privacy: .public) workout=\(workoutStatus, privacy: .public)"
        )

        healthStore.getRequestStatusForAuthorization(toShare: [workoutType], read: [heartRateType]) { status, error in
            self.logger.info(
                "HK request status [\(context, privacy: .public)] status=\(self.requestStatusText(status), privacy: .public) error=\(error?.localizedDescription ?? "none", privacy: .public)"
            )
        }
    }

    private func authorizationStatusText(for status: HKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .sharingDenied:
            return "sharingDenied"
        case .sharingAuthorized:
            return "sharingAuthorized"
        @unknown default:
            return "unknown"
        }
    }

    private func requestStatusText(_ status: HKAuthorizationRequestStatus) -> String {
        switch status {
        case .unknown:
            return "unknown"
        case .shouldRequest:
            return "shouldRequest"
        case .unnecessary:
            return "unnecessary"
        @unknown default:
            return "unknown"
        }
    }

    private func requestMirroringIfPossible(for session: HKWorkoutSession) {
        guard #available(watchOS 10.0, *) else { return }
        guard !hasRequestedMirroring else { return }
        guard hasBegunCollection, isRunning else { return }
        guard session.state == .running else { return }
        hasRequestedMirroring = true
        logger.debug("Requesting workout mirroring to companion")
        session.startMirroringToCompanionDevice { success, error in
            self.logger.info(
                "Workout mirroring result success=\(success, privacy: .public) error=\(error?.localizedDescription ?? "none", privacy: .public)"
            )
        }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        logger.info(
            "Workout session state changed from=\(String(describing: fromState.rawValue), privacy: .public) to=\(String(describing: toState.rawValue), privacy: .public)"
        )

        if toState == .running {
            DispatchQueue.main.async {
                self.sendState(self.hasReceivedHeartRateSample ? .receivingLive : .collectingNoSamples)
                self.requestMirroringIfPossible(for: workoutSession)
            }
        }

        if toState == .ended {
            DispatchQueue.main.async {
                self.isRunning = false
                if !self.isStoppingWorkout {
                    self.cleanupWorkout(clearStopFlag: true)
                }
                self.sendState(.authorizedIdle)
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        logger.error("Workout session failed: \(error.localizedDescription, privacy: .public)")
        DispatchQueue.main.async {
            self.isRunning = false
            if !self.isStoppingWorkout {
                self.cleanupWorkout(clearStopFlag: true)
            }
            self.sendState(.error, detail: error.localizedDescription)
        }
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        logger.debug("LiveWorkoutBuilder collected event")
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        guard collectedTypes.contains(heartRateType) else { return }
        guard let statistics = workoutBuilder.statistics(for: heartRateType),
              let quantity = statistics.mostRecentQuantity() else {
            logger.debug("LiveWorkoutBuilder heart rate callback without statistics")
            return
        }

        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = quantity.doubleValue(for: unit)
        logger.debug("LiveWorkoutBuilder didCollectData heartRate=\(Int(bpm.rounded()), privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            self?.updateHeartRate(bpm)
        }
    }
}

extension WatchWorkoutManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        logger.info(
            "WC activation completed state=\(String(describing: activationState.rawValue), privacy: .public) reachable=\(session.isReachable, privacy: .public) companionInstalled=\(session.isCompanionAppInstalled, privacy: .public) error=\(error?.localizedDescription ?? "none", privacy: .public)"
        )
        sendCurrentStateSnapshot(reason: "wc activated")
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        logger.info("WC reachability changed reachable=\(session.isReachable, privacy: .public)")
        if session.isReachable {
            sendCurrentStateSnapshot(reason: "reachability")
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        logger.debug("Received WC message keys=\(message.keys.sorted().joined(separator: ","), privacy: .public)")
        handleMessage(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        logger.debug("Received WC message with reply keys=\(message.keys.sorted().joined(separator: ","), privacy: .public)")
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
        logger.debug("Received WC userInfo keys=\(userInfo.keys.sorted().joined(separator: ","), privacy: .public)")
        handleMessage(userInfo)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        logger.debug("Received WC applicationContext keys=\(applicationContext.keys.sorted().joined(separator: ","), privacy: .public)")
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
                self.pendingWorkoutConfiguration = nil
                if self.isRunning {
                    self.stopWorkout()
                } else {
                    self.sendState(.authorizedIdle, detail: "idle")
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
