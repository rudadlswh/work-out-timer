import Foundation
import Combine

#if os(iOS) && canImport(WatchConnectivity) && canImport(HealthKit)
import WatchConnectivity
import HealthKit

final class HeartRateManager: NSObject, ObservableObject {
    @Published var currentBpm: Int?
    @Published var averageBpm: Int?
    @Published var isCollecting: Bool = false
    @Published var isSessionSupported: Bool = false
    @Published var isWatchPaired: Bool = false
    @Published var isWatchAppInstalled: Bool = false
    @Published var isReachable: Bool = false
    @Published var activationStateText: String = "미활성화"
    @Published var lastPingStatus: String = "미실행"
    @Published var lastPingDate: Date?
    @Published var lastPingSucceeded: Bool?
    @Published var isPinging: Bool = false
    @Published var lastHeartRateDate: Date?
    @Published var useDummyHeartRate: Bool = HeartRateManager.defaultDummyHeartRateEnabled {
        didSet {
            updateDummyMode()
        }
    }

    private var sumBpm: Double = 0
    private var sampleCount: Int = 0
    private var session: WCSession?
    private let healthStore = HKHealthStore()
    private var authorizationStatus: Bool?
    private var mirroredSession: HKWorkoutSession?
    private var mirroredBuilder: HKLiveWorkoutBuilder?
    private var isMirroringActive: Bool = false
    private var autoConnectEnabled: Bool = true
    private var pendingPing: Bool = false
    private var currentPingId: String?
    private var pingTimeoutWorkItem: DispatchWorkItem?
    private let pingTimeout: TimeInterval = 10
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
        configureMirroring()
        let supported = WCSession.isSupported()
        isSessionSupported = supported
        guard supported else { return }
        let wcSession = WCSession.default
        wcSession.delegate = self
        wcSession.activate()
        session = wcSession
        updateSessionState()
    }

    func start() {
        resetMetrics()
        isCollecting = true
        if useDummyHeartRate {
            startDummyHeartRate()
            return
        }
        requestAuthorizationIfNeeded { [weak self] success in
            guard let self else { return }
            if success {
                self.startWatchAppForMirroring()
            } else {
                self.sendCommand("start")
            }
        }
    }

    func stop() {
        isCollecting = false
        stopDummyHeartRate()
        if useDummyHeartRate {
            return
        }
        sendCommand("stop")
    }

    func reset() {
        isCollecting = false
        stopDummyHeartRate()
        resetMetrics()
    }

    func setDummyHeartRateEnabled(_ enabled: Bool) {
        useDummyHeartRate = enabled
    }

    func refreshConnectionStatus() {
        ensureSessionActivated()
        updateSessionState()
    }

    func pingWatch() {
        guard let session else {
            updatePingStatus(result: "세션 없음", success: false)
            return
        }
        let pingId = UUID().uuidString
        currentPingId = pingId
        DispatchQueue.main.async {
            self.isPinging = true
            self.lastPingStatus = "대기 중"
            self.lastPingSucceeded = nil
            self.lastPingDate = Date()
        }
        schedulePingTimeout()
        ensureSessionActivated()
        if session.activationState != .activated {
            pendingPing = true
            updatePingProgress("세션 활성화 대기")
            return
        }
        sendPingMessage(session, pingId: pingId)
        sendPingUserInfo(session, pingId: pingId)
    }

    private func resetMetrics() {
        currentBpm = nil
        averageBpm = nil
        lastHeartRateDate = nil
        sumBpm = 0
        sampleCount = 0
    }

    private func updateDummyMode() {
        if useDummyHeartRate {
            stopDummyHeartRate()
            if isCollecting {
                startDummyHeartRate()
            }
        } else {
            stopDummyHeartRate()
            if isCollecting {
                start()
            }
        }
    }

    private func startDummyHeartRate() {
        stopDummyHeartRate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.isCollecting else { return }
            let bpm = self.nextDummyHeartRate()
            self.handleHeartRate(Double(bpm))
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

    private func configureMirroring() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if #available(iOS 17.0, *) {
            healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
                self?.handleMirroredSession(session)
            }
        }
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
        let workoutType = HKObjectType.workoutType()
        healthStore.requestAuthorization(toShare: [], read: [heartRateType, workoutType]) { success, _ in
            DispatchQueue.main.async {
                self.authorizationStatus = success
                completion(success)
            }
        }
    }

    private func startWatchAppForMirroring() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .indoor
        healthStore.startWatchApp(with: configuration) { [weak self] success, _ in
            DispatchQueue.main.async {
                if !success {
                    self?.sendCommand("start")
                }
            }
        }
    }

    private func handleMirroredSession(_ session: HKWorkoutSession) {
        requestAuthorizationIfNeeded { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.resetMetrics()
                self.mirroredSession = session
                session.delegate = self
                let builder = session.associatedWorkoutBuilder()
                builder.delegate = self
                self.mirroredBuilder = builder
                self.isMirroringActive = true
                self.isCollecting = true
            }
        }
    }

    private func updateSessionState() {
        ensureSessionActivated()
        guard let session else {
            DispatchQueue.main.async {
                self.isSessionSupported = WCSession.isSupported()
                self.isWatchPaired = false
                self.isWatchAppInstalled = false
                self.isReachable = false
                self.activationStateText = "미활성화"
            }
            return
        }
        let activationText = Self.activationStateText(session.activationState)
        let isPaired = session.isPaired
        let isInstalled = session.isWatchAppInstalled
        let isReachable = session.isReachable
        DispatchQueue.main.async {
            self.isSessionSupported = true
            self.isWatchPaired = isPaired
            self.isWatchAppInstalled = isInstalled
            self.isReachable = isReachable
            self.activationStateText = activationText
            self.autoConnectIfPossible()
            if self.pendingPing, isReachable, let pingId = self.currentPingId {
                self.sendPingMessage(session, pingId: pingId)
            }
        }
    }

    private func ensureSessionActivated() {
        guard let session else { return }
        if session.activationState != .activated {
            session.activate()
        }
    }

    private func autoConnectIfPossible() {
        guard autoConnectEnabled else { return }
        guard isSessionSupported, isWatchPaired, isWatchAppInstalled else { return }
        guard !isCollecting else { return }
        start()
    }

    private func updatePingStatus(result: String, success: Bool) {
        DispatchQueue.main.async {
            self.pingTimeoutWorkItem?.cancel()
            self.pendingPing = false
            self.currentPingId = nil
            self.isPinging = false
            self.lastPingStatus = result
            self.lastPingSucceeded = success
            self.lastPingDate = Date()
        }
    }

    private func updatePingProgress(_ status: String) {
        DispatchQueue.main.async {
            self.lastPingStatus = status
            self.lastPingDate = Date()
        }
    }

    private func schedulePingTimeout() {
        pingTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isPinging else { return }
            self.pendingPing = false
            self.updatePingStatus(result: "응답 없음", success: false)
        }
        pingTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + pingTimeout, execute: workItem)
    }

    private func sendPingMessage(_ session: WCSession, pingId: String) {
        let payload: [String: Any] = ["command": "ping", "pingId": pingId]
        session.sendMessage(payload, replyHandler: { [weak self] reply in
            self?.handlePong(reply)
        }, errorHandler: { [weak self] _ in
            guard let self else { return }
            self.pendingPing = true
            self.updatePingProgress("실시간 연결 대기")
        })
    }

    private func sendPingUserInfo(_ session: WCSession, pingId: String) {
        let payload: [String: Any] = ["command": "ping", "pingId": pingId]
        session.transferUserInfo(payload)
    }

    private func handlePong(_ message: [String: Any]) {
        guard isPinging else { return }
        if let pingId = message["pingId"] as? String,
           let currentPingId,
           pingId != currentPingId {
            return
        }
        let success = message["pong"] as? Bool ?? false
        updatePingStatus(result: success ? "성공" : "응답 이상", success: success)
    }

    private static func activationStateText(_ state: WCSessionActivationState) -> String {
        switch state {
        case .activated:
            return "활성화됨"
        case .inactive:
            return "비활성"
        case .notActivated:
            return "미활성화"
        @unknown default:
            return "알 수 없음"
        }
    }

    private func handleHeartRate(_ bpm: Double) {
        guard isCollecting else { return }
        let rounded = Int(bpm.rounded())
        currentBpm = rounded
        lastHeartRateDate = Date()
        sumBpm += bpm
        sampleCount += 1
        averageBpm = Int((sumBpm / Double(sampleCount)).rounded())
    }

    func sendTimerState(mode: String, phase: String, displaySeconds: Int, headline: String, exercise: String?) {
        var payload: [String: Any] = [
            "type": "timerState",
            "mode": mode,
            "phase": phase,
            "displaySeconds": max(0, displaySeconds),
            "headline": headline
        ]
        if let exercise {
            payload["exercise"] = exercise
        }
        sendMessageOrContext(payload)
    }

    private func sendCommand(_ command: String) {
        let payload = ["command": command]
        sendMessageOrUserInfo(payload)
    }

    private func sendMessageOrUserInfo(_ payload: [String: Any]) {
        guard let session else { return }
        ensureSessionActivated()
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func sendMessageOrContext(_ payload: [String: Any]) {
        guard let session else { return }
        ensureSessionActivated()
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            try? session.updateApplicationContext(payload)
        }
    }
}

extension HeartRateManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // 상태 변경 필요 시 사용
        updateSessionState()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // 필요 시 처리
        updateSessionState()
    }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        updateSessionState()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleHeartRateMessage(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        handleHeartRateMessage(userInfo)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        updateSessionState()
        guard pendingPing, session.isReachable, let currentPingId else { return }
        DispatchQueue.main.async { [weak self] in
            self?.sendPingMessage(session, pingId: currentPingId)
        }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        updateSessionState()
    }

    private func handleHeartRateMessage(_ message: [String: Any]) {
        guard !useDummyHeartRate else { return }
        if message["pong"] as? Bool != nil {
            handlePong(message)
            return
        }
        guard !isMirroringActive else { return }
        let bpmValue: Double?
        if let bpm = message["heartRate"] as? Double {
            bpmValue = bpm
        } else if let bpm = message["heartRate"] as? Int {
            bpmValue = Double(bpm)
        } else {
            bpmValue = nil
        }

        guard let bpm = bpmValue else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handleHeartRate(bpm)
        }
    }
}

extension HeartRateManager: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async {
            switch toState {
            case .running:
                self.isCollecting = true
            case .ended, .stopped:
                self.isCollecting = false
                self.isMirroringActive = false
                self.mirroredSession = nil
                self.mirroredBuilder = nil
            default:
                break
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isCollecting = false
            self.isMirroringActive = false
            self.mirroredSession = nil
            self.mirroredBuilder = nil
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        DispatchQueue.main.async {
            self.isMirroringActive = false
            self.mirroredSession = nil
            self.mirroredBuilder = nil
        }
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard !useDummyHeartRate else { return }
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(heartRateType) else { return }
        guard let statistics = workoutBuilder.statistics(for: heartRateType),
              let quantity = statistics.mostRecentQuantity() else { return }

        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = quantity.doubleValue(for: unit)
        DispatchQueue.main.async { [weak self] in
            self?.handleHeartRate(bpm)
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
    }
}
#else
final class HeartRateManager: ObservableObject {
    @Published var currentBpm: Int?
    @Published var averageBpm: Int?
    @Published var isCollecting: Bool = false
    @Published var isSessionSupported: Bool = false
    @Published var isWatchPaired: Bool = false
    @Published var isWatchAppInstalled: Bool = false
    @Published var isReachable: Bool = false
    @Published var activationStateText: String = "지원 안 됨"
    @Published var lastPingStatus: String = "지원 안 됨"
    @Published var lastPingDate: Date?
    @Published var lastPingSucceeded: Bool?
    @Published var isPinging: Bool = false
    @Published var lastHeartRateDate: Date?
    @Published var useDummyHeartRate: Bool = false

    func start() {}
    func stop() {}
    func reset() {}
    func refreshConnectionStatus() {}
    func pingWatch() {}
    func sendTimerState(mode: String, phase: String, displaySeconds: Int, headline: String, exercise: String?) {}
    func setDummyHeartRateEnabled(_ enabled: Bool) {}
}
#endif
