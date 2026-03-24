#if os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit
import Foundation
import notify
import UserNotifications

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

struct HIITAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var displaySeconds: Int     // 표시할 초
        var label: String           // 표시 라벨
        var isRunning: Bool         // 실행 상태
        var isCountdown: Bool       // 카운트다운 여부
        var sentAt: Date            // 마지막 업데이트 시각
    }
    var mode: String               // 타이머 모드
    var totalMinutes: Int          // 총 분
    var intervalMinutes: Int       // 인터벌 분
}

enum TimerExternalControl {
    static let notificationName = Notification.Name("com.chogm.timer.externalStopRequested")
    static let darwinNotificationName = "com.chogm.timer.externalStopRequested"
}

enum TimerSessionTermination {
    static func requestStopFromLiveActivity() async {
        postExternalStopSignal()
        await endAllLiveActivitiesImmediately()
        clearTimerNotifications()
        sendIdleStateToWatch()
    }

    static func clearTimerNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    static func endAllLiveActivitiesImmediately() async {
        let state = HIITAttributes.ContentState(
            displaySeconds: 0,
            label: "",
            isRunning: false,
            isCountdown: false,
            sentAt: Date()
        )
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in Activity<HIITAttributes>.activities {
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }

    static func sendIdleStateToWatch() {
#if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.activationState == .notActivated {
            session.activate()
        }
        guard session.activationState == .activated else { return }
        guard session.isPaired, session.isWatchAppInstalled else { return }

        let payload: [String: Any] = [
            "type": "timerState",
            "mode": "",
            "phase": "idle",
            "displaySeconds": 0,
            "headline": "",
            "exercise": ""
        ]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
        do {
            try session.updateApplicationContext(payload)
        } catch {
            // Best-effort idle sync path for external stop action.
        }
        session.transferUserInfo(payload)
#endif
    }

    private static func postExternalStopSignal() {
        notify_post(TimerExternalControl.darwinNotificationName)
    }
}
#else
import Foundation

struct HIITAttributes {
    public struct ContentState: Codable, Hashable {
        var displaySeconds: Int     // 표시할 초
        var label: String           // 표시 라벨
        var isRunning: Bool         // 실행 상태
        var isCountdown: Bool       // 카운트다운 여부
        var sentAt: Date            // 마지막 업데이트 시각
    }
    var mode: String               // 타이머 모드
    var totalMinutes: Int          // 총 분
    var intervalMinutes: Int       // 인터벌 분
}
#endif
