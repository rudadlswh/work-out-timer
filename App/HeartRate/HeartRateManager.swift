import Foundation
import Combine

#if os(iOS) && canImport(WatchConnectivity)
import WatchConnectivity
import os

private enum RemoteHeartRateState: String {
    case idle
    case startRequested
    case watchAppNotActive
    case watchAppNotReachable
    case authorizationRequesting
    case unauthorized
    case authorizedIdle
    case startingWorkout
    case collectingNoSamples
    case receivingLive
    case error

    var isCollecting: Bool {
        switch self {
        case .collectingNoSamples, .receivingLive:
            return true
        default:
            return false
        }
    }

    var isStartPending: Bool {
        switch self {
        case .startRequested, .authorizationRequesting, .startingWorkout:
            return true
        default:
            return false
        }
    }

    var defaultText: String {
        switch self {
        case .idle:
            return "대기"
        case .startRequested:
            return "시작 요청 중"
        case .watchAppNotActive:
            return "워치 앱 열기 필요"
        case .watchAppNotReachable:
            return "워치 실시간 연결 필요"
        case .authorizationRequesting:
            return "워치 권한 요청 중"
        case .unauthorized:
            return "워치 권한 필요"
        case .authorizedIdle:
            return "권한 허용됨, 시작 전"
        case .startingWorkout:
            return "운동 세션 시작 중"
        case .collectingNoSamples:
            return "측정 중, 샘플 대기"
        case .receivingLive:
            return "실시간 심박 수신 중"
        case .error:
            return "오류"
        }
    }
}

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
    @Published var heartRateStatusText: String = RemoteHeartRateState.idle.defaultText
    @Published var isStartPending: Bool = false
    @Published var useDummyHeartRate: Bool = HeartRateManager.defaultDummyHeartRateEnabled {
        didSet {
            updateDummyMode()
        }
    }

    private var sumBpm: Double = 0
    private var sampleCount: Int = 0
    private var session: WCSession?
    private var pendingPing: Bool = false
    private var currentPingId: String?
    private var pingTimeoutWorkItem: DispatchWorkItem?
    private let pingTimeout: TimeInterval = 10
    private var dummyTimer: Timer?
    private var dummyBpm: Int = 95
    private var dummyDirection: Int = 1
    private var isActivatingSession: Bool = false
    private var remoteState: RemoteHeartRateState = .idle
    private var remoteStateDetail: String?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.chogm.timer",
        category: "PhoneHeartRate"
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
        let supported = WCSession.isSupported()
        isSessionSupported = supported
        guard supported else { return }

        let wcSession = WCSession.default
        wcSession.delegate = self
        session = wcSession

        logger.info("WCSession supported: \(supported, privacy: .public)")
        ensureSessionActivated()
        updateSessionState()
        applyRemoteState(.idle)
    }

    func start() {
        resetMetrics()
        if useDummyHeartRate {
            applyRemoteState(.collectingNoSamples)
            startDummyHeartRate()
            return
        }

        applyRemoteState(.startRequested)
        sendInteractiveCommand("start")
    }

    func stop() {
        stopDummyHeartRate()
        if useDummyHeartRate {
            applyRemoteState(.idle)
            return
        }

        applyRemoteState(.authorizedIdle)
        sendInteractiveCommand("stop")
    }

    func reset() {
        stopDummyHeartRate()
        resetMetrics()
        applyRemoteState(.idle)
    }

    func setDummyHeartRateEnabled(_ enabled: Bool) {
        useDummyHeartRate = enabled
    }

    func refreshConnectionStatus() {
        ensureSessionActivated()
        updateSessionState()
    }

    func pingWatch() {
        guard WCSession.isSupported() else {
            updatePingStatus(result: "세션 미지원", success: false)
            return
        }
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
        guard session.isPaired, session.isWatchAppInstalled else {
            updatePingStatus(result: "워치 앱 미설치", success: false)
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
                applyRemoteState(.collectingNoSamples)
                startDummyHeartRate()
            }
        } else {
            stopDummyHeartRate()
            resetMetrics()
            applyRemoteState(.idle)
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

        logger.debug(
            "WC state activation=\(activationText, privacy: .public) paired=\(isPaired, privacy: .public) installed=\(isInstalled, privacy: .public) reachable=\(isReachable, privacy: .public)"
        )

        DispatchQueue.main.async {
            self.isSessionSupported = true
            self.isWatchPaired = isPaired
            self.isWatchAppInstalled = isInstalled
            self.isReachable = isReachable
            self.activationStateText = activationText
            if self.pendingPing, isReachable, let pingId = self.currentPingId {
                self.sendPingMessage(session, pingId: pingId)
            }
        }
    }

    private func ensureSessionActivated() {
        guard WCSession.isSupported(), let session else { return }
        guard !isActivatingSession else { return }
        guard session.activationState == .notActivated else { return }

        logger.info("Activating WCSession")
        isActivatingSession = true
        session.activate()
    }

    private func canSend(to session: WCSession) -> Bool {
        guard WCSession.isSupported() else { return false }
        guard session.activationState == .activated else { return false }
        guard session.isPaired, session.isWatchAppInstalled else { return false }
        return true
    }

    private func canPing(_ session: WCSession) -> Bool {
        guard canSend(to: session) else {
            if !session.isPaired || !session.isWatchAppInstalled {
                updatePingStatus(result: "워치 앱 미설치", success: false)
            }
            return false
        }

        return true
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
        guard canPing(session) else { return }
        let payload: [String: Any] = ["command": "ping", "pingId": pingId]
        logger.debug("Sending ping message id=\(pingId, privacy: .public)")
        session.sendMessage(payload, replyHandler: { [weak self] reply in
            self?.handlePong(reply)
        }, errorHandler: { [weak self] error in
            self?.logger.error("Ping sendMessage failed: \(error.localizedDescription, privacy: .public)")
            self?.pendingPing = true
            self?.updatePingProgress("실시간 연결 대기")
        })
    }

    private func sendPingUserInfo(_ session: WCSession, pingId: String) {
        guard canPing(session) else { return }
        let payload: [String: Any] = ["command": "ping", "pingId": pingId]
        logger.debug("Queueing ping userInfo id=\(pingId, privacy: .public)")
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
        logger.debug("Received pong success=\(success, privacy: .public)")
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
        let rounded = Int(bpm.rounded())
        currentBpm = rounded
        lastHeartRateDate = Date()
        sumBpm += bpm
        sampleCount += 1
        averageBpm = Int((sumBpm / Double(sampleCount)).rounded())
        applyRemoteState(.receivingLive)
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

    private func sendInteractiveCommand(_ command: String) {
        guard WCSession.isSupported() else {
            applyRemoteState(.watchAppNotReachable)
            return
        }
        guard let session else {
            applyRemoteState(.watchAppNotReachable)
            return
        }

        ensureSessionActivated()
        guard canSend(to: session) else {
            applyRemoteState(.watchAppNotReachable)
            return
        }
        guard session.isReachable else {
            logger.info("Skipping command \(command, privacy: .public): watch app is not reachable")
            applyRemoteState(.watchAppNotActive)
            return
        }

        logger.info("Sending command \(command, privacy: .public)")
        session.sendMessage(["command": command], replyHandler: nil) { [weak self] error in
            self?.logger.error("Command \(command, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            self?.applyRemoteState(.error, detail: error.localizedDescription)
        }
    }

    private func sendMessageOrContext(_ payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        guard let session else { return }

        ensureSessionActivated()
        guard canSend(to: session) else { return }

        if session.isReachable {
            logger.debug("Sending live payload type=\((payload["type"] as? String) ?? "unknown", privacy: .public)")
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                self?.logger.error("sendMessage failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            do {
                logger.debug("Updating application context type=\((payload["type"] as? String) ?? "unknown", privacy: .public)")
                try session.updateApplicationContext(payload)
            } catch {
                logger.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func applyRemoteState(_ state: RemoteHeartRateState, detail: String? = nil) {
        remoteState = state
        remoteStateDetail = detail

        let text: String
        if let detail, !detail.isEmpty, state != .receivingLive {
            text = "\(state.defaultText) (\(detail))"
        } else {
            text = state.defaultText
        }

        DispatchQueue.main.async {
            self.isCollecting = state.isCollecting
            self.isStartPending = state.isStartPending
            self.heartRateStatusText = text
            if !state.isCollecting {
                self.lastHeartRateDate = state == .idle ? nil : self.lastHeartRateDate
            }
        }
    }
}

extension HeartRateManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        isActivatingSession = false
        logger.info(
            "WC activation completed state=\(Self.activationStateText(activationState), privacy: .public) error=\(error?.localizedDescription ?? "none", privacy: .public)"
        )
        updateSessionState()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        isActivatingSession = false
        logger.info("WC session became inactive")
        updateSessionState()
    }

    func sessionDidDeactivate(_ session: WCSession) {
        isActivatingSession = false
        logger.info("WC session deactivated; reactivating")
        ensureSessionActivated()
        updateSessionState()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        logger.debug("Received WC message keys=\(message.keys.sorted().joined(separator: ","), privacy: .public)")
        handleHeartRateMessage(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        logger.debug("Received WC userInfo keys=\(userInfo.keys.sorted().joined(separator: ","), privacy: .public)")
        handleHeartRateMessage(userInfo)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        logger.debug("Received WC applicationContext keys=\(applicationContext.keys.sorted().joined(separator: ","), privacy: .public)")
        handleHeartRateMessage(applicationContext)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        logger.info("WC reachability changed reachable=\(session.isReachable, privacy: .public)")
        updateSessionState()
        guard pendingPing, session.isReachable, let currentPingId else { return }
        DispatchQueue.main.async { [weak self] in
            self?.sendPingMessage(session, pingId: currentPingId)
        }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        logger.info("WC watch state changed")
        updateSessionState()
    }

    private func handleHeartRateMessage(_ message: [String: Any]) {
        guard !useDummyHeartRate else { return }

        if message["pong"] as? Bool != nil {
            handlePong(message)
            return
        }

        if let stateValue = message["heartRateState"] as? String,
           let state = RemoteHeartRateState(rawValue: stateValue) {
            applyRemoteState(state, detail: message["heartRateDetail"] as? String)
        }

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
    @Published var heartRateStatusText: String = "지원 안 됨"
    @Published var isStartPending: Bool = false
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
