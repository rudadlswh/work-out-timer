import Foundation
import Combine

#if canImport(WatchConnectivity)
import WatchConnectivity

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

    private var sumBpm: Double = 0
    private var sampleCount: Int = 0
    private var session: WCSession?

    override init() {
        super.init()
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
        sendCommand("start")
    }

    func stop() {
        isCollecting = false
        sendCommand("stop")
    }

    func reset() {
        isCollecting = false
        resetMetrics()
    }

    func refreshConnectionStatus() {
        updateSessionState()
    }

    func pingWatch() {
        guard let session else {
            updatePingStatus(result: "세션 없음", success: false)
            return
        }
        guard session.isReachable else {
            updatePingStatus(result: "워치 앱 실행 필요", success: false)
            return
        }
        isPinging = true
        session.sendMessage(["command": "ping"], replyHandler: { [weak self] reply in
            let success = reply["pong"] as? Bool ?? false
            self?.updatePingStatus(result: success ? "성공" : "응답 이상", success: success)
        }, errorHandler: { [weak self] _ in
            self?.updatePingStatus(result: "실패", success: false)
        })
    }

    private func resetMetrics() {
        currentBpm = nil
        averageBpm = nil
        lastHeartRateDate = nil
        sumBpm = 0
        sampleCount = 0
    }

    private func updateSessionState() {
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
        DispatchQueue.main.async {
            self.isSessionSupported = true
            self.isWatchPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable
            self.activationStateText = activationText
        }
    }

    private func updatePingStatus(result: String, success: Bool) {
        DispatchQueue.main.async {
            self.isPinging = false
            self.lastPingStatus = result
            self.lastPingSucceeded = success
            self.lastPingDate = Date()
        }
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
        let payload: [String: Any] = [
            "type": "timerState",
            "mode": mode,
            "phase": phase,
            "displaySeconds": max(0, displaySeconds),
            "headline": headline,
            "exercise": exercise ?? ""
        ]
        sendMessageOrContext(payload)
    }

    private func sendCommand(_ command: String) {
        let payload = ["command": command]
        sendMessageOrUserInfo(payload)
    }

    private func sendMessageOrUserInfo(_ payload: [String: Any]) {
        guard let session else { return }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func sendMessageOrContext(_ payload: [String: Any]) {
        guard let session else { return }
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
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        updateSessionState()
    }

    private func handleHeartRateMessage(_ message: [String: Any]) {
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

    func start() {}
    func stop() {}
    func reset() {}
    func refreshConnectionStatus() {}
    func pingWatch() {}
    func sendTimerState(mode: String, phase: String, displaySeconds: Int, headline: String, exercise: String?) {}
}
#endif
