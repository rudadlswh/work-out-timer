import Foundation
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
    case authorizedIdle
    case collectingNoSamples
    case error
}

final class WatchWorkoutManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutManager()

    @Published var currentBpm: Int?
    @Published var averageBpm: Int?
    @Published var isRunning: Bool = false
    @Published var phoneTimerState: PhoneTimerState?
    @Published var useDummyHeartRate: Bool = false

    private var wcSession: WCSession?
    private var isAppActive: Bool = WKExtension.shared().applicationState == .active
    private var shouldResumeOnActive: Bool = false
    private var lastSentState: WatchHeartRateState?
    private var lastSentStateDetail: String?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.chogm.timer.watch",
        category: "WatchHeartRate"
    )

    override init() {
        super.init()
        configureConnectivity()
        logger.info("Review build integration disabled")
    }

    func handleApplicationDidBecomeActive() {
        isAppActive = true
        logger.info("Watch app became active")
        sendCurrentStateSnapshot(reason: "app active")
        resumePendingStartIfNeeded()
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

    func startWorkout() {
        guard isAppActive else {
            shouldResumeOnActive = true
            logger.info("Deferring workout start until watch app is active")
            sendState(.watchAppNotActive)
            return
        }

        if isRunning {
            logger.debug("Ignoring start: workout already running")
            return
        }

        resetMetrics()
        shouldResumeOnActive = false
        isRunning = true

        // TODO: Re-enable HealthKit after App Review fix.
        sendState(.collectingNoSamples, detail: "review-disabled")
    }

    func stopWorkout() {
        shouldResumeOnActive = false
        guard isRunning else {
            sendState(.authorizedIdle)
            return
        }

        isRunning = false
        resetMetrics()
        sendState(.authorizedIdle)
    }

    private func resumePendingStartIfNeeded() {
        guard shouldResumeOnActive else { return }
        guard phoneTimerState?.phase == "running" || isRunning else {
            shouldResumeOnActive = false
            return
        }
        logger.info("Resuming deferred workout start")
        startWorkout()
    }

    private func resetMetrics() {
        currentBpm = nil
        averageBpm = nil
    }

    private func canSendToPhone(_ session: WCSession) -> Bool {
        guard session.activationState == .activated else { return false }
        return session.isCompanionAppInstalled
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
        if isRunning {
            sendState(.collectingNoSamples, detail: reason)
        } else {
            sendState(.authorizedIdle, detail: reason)
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
