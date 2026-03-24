import SwiftUI
import UserNotifications
#if os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

struct AmrapTabView: View {
    let mode: WorkoutMode
    @Binding var selectedMode: WorkoutMode
    @Binding var isModePickerVisible: Bool
    @Binding var isTimerSessionActive: Bool
    @EnvironmentObject private var heartRateManager: HeartRateManager
    @FocusState private var isExerciseFieldFocused: Bool

    @State private var totalMinutes: Int = 20
    @State private var countdown: Int? = nil
    @State private var remainingSeconds: Int = 0
    @State private var timer: Timer? = nil
    @State private var isRunning: Bool = false
#if os(iOS) && !targetEnvironment(macCatalyst)
    @State private var activity: Activity<HIITAttributes>? = nil
#endif
    @State private var exerciseInput: String = ""
    @State private var rounds: Int = 0
    @State private var endAlertEnabled: Bool = true
    @State private var lastSyncedExerciseSummary: String = ""

    private let minuteOptions = Array(1...60)

    private var exercises: [String] {
        TimerUtilities.parseExercises(exerciseInput)
    }

    private var exerciseSummary: String {
        exercises.isEmpty ? "운동 목록 없음" : exercises.joined(separator: " / ")
    }

    var body: some View {
        ZStack {
            dismissalBackground

            VStack(spacing: 24) {
                if countdown == nil {
                    AmrapSettingsView(
                        minuteOptions: minuteOptions,
                        totalMinutes: $totalMinutes,
                        endAlertEnabled: $endAlertEnabled,
                        exerciseInput: $exerciseInput,
                        exerciseFieldFocus: $isExerciseFieldFocused,
                        onStart: {
                            dismissKeyboard()
                            startCountdown()
                        }
                    )
                } else if let cd = countdown, cd > 0 {
                    countdownView(cd)
                } else if isRunning {
                    AmrapRunningView(
                        rounds: rounds,
                        exercises: exercises,
                        remainingTimeText: TimerUtilities.formatTime(remainingSeconds),
                        currentBpm: heartRateManager.currentBpm,
                        onStop: stopTimer
                    )
                } else {
                    completeView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if isRunning {
                    rounds += 1
                    sendRunningState()
                }
            }
        )
        .onAppear(perform: updateModePickerVisibility)
        .onChange(of: isRunning, initial: false) { _, _ in updateModePickerVisibility() }
        .onChange(of: countdown, initial: false) { _, _ in updateModePickerVisibility() }
        .onReceive(NotificationCenter.default.publisher(for: TimerExternalControl.notificationName)) { _ in
            handleExternalStopRequest()
        }
    }

    private func countdownView(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 64, weight: .bold))
            .foregroundStyle(TimerTheme.primaryText)
            .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
    }

    private var completeView: some View {
        VStack(spacing: 12) {
            Text("완료!")
                .font(.title)
                .foregroundStyle(TimerTheme.primaryText)
            Text("완료 라운드 \(rounds)")
                .font(.headline)
                .foregroundStyle(TimerTheme.secondaryText)
            if let average = heartRateManager.averageBpm {
                HeartRateMetricView(title: "평균 심박", bpm: average)
            }
            exerciseListView
            Button("다시 시작") {
                resetAll()
            }
            .buttonStyle(.borderedProminent)
            .tint(TimerTheme.actionTint)
        }
    }

    private func updateModePickerVisibility() {
        if selectedMode == mode {
            isTimerSessionActive = isRunning || ((countdown ?? 0) > 0)
        }
        isModePickerVisible = !isRunning && countdown == nil
    }

    private var dismissalBackground: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissKeyboard)
    }

    private func dismissKeyboard() {
        isExerciseFieldFocused = false
    }

    private func startCountdown() {
        startCountdownTimer {
            startAmrapTimer(total: totalMinutes)
        }
    }

    private func startCountdownTimer(then startAction: @escaping () -> Void) {
        countdown = 5
        isRunning = false
        sendCountdownState()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if let cd = countdown, cd > 1 {
                countdown = cd - 1
                sendCountdownState()
            } else {
                timer?.invalidate()
                startAction()
            }
        }
    }

    private func startAmrapTimer(total: Int) {
        remainingSeconds = total * 60
        isRunning = true
        countdown = 0
        rounds = 0
        heartRateManager.start()
        startLiveActivity(total: total)
        if endAlertEnabled {
            scheduleEndNotification(total: total)
        } else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
        TimerUtilities.playBeep()
        sendRunningState()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if remainingSeconds > 0 {
                remainingSeconds -= 1
                sendRunningState()
            } else {
                timer?.invalidate()
                isRunning = false
                heartRateManager.stop()
                if endAlertEnabled {
                    TimerUtilities.playBeep()
                }
                endLiveActivity()
                sendCompleteState()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        isRunning = false
        countdown = nil
        rounds = 0
        lastSyncedExerciseSummary = ""
        heartRateManager.stop()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        endLiveActivity()
        sendIdleState()
    }

    private func handleExternalStopRequest() {
        guard isRunning || ((countdown ?? 0) > 0) else { return }
        stopTimer()
    }

    private func resetAll() {
        countdown = nil
        isRunning = false
        timer?.invalidate()
        remainingSeconds = 0
        rounds = 0
        lastSyncedExerciseSummary = ""
        heartRateManager.reset()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        endLiveActivity()
        sendIdleState()
    }

    private func sendCountdownState() {
        guard let cd = countdown else { return }
        heartRateManager.sendTimerState(
            mode: TimerSyncMode.amrap,
            phase: TimerSyncPhase.countdown,
            displaySeconds: cd,
            headline: "카운트다운",
            exercise: exercisePayload(force: true)
        )
    }

    private func sendRunningState() {
        heartRateManager.sendTimerState(
            mode: TimerSyncMode.amrap,
            phase: TimerSyncPhase.running,
            displaySeconds: remainingSeconds,
            headline: "라운드 \(rounds)",
            exercise: exercisePayload(force: false)
        )
    }

    private func sendCompleteState() {
        heartRateManager.sendTimerState(
            mode: TimerSyncMode.amrap,
            phase: TimerSyncPhase.complete,
            displaySeconds: 0,
            headline: "완료 라운드 \(rounds)",
            exercise: exercisePayload(force: true)
        )
    }

    private func sendIdleState() {
        heartRateManager.sendTimerState(
            mode: TimerSyncMode.amrap,
            phase: TimerSyncPhase.idle,
            displaySeconds: 0,
            headline: "",
            exercise: ""
        )
    }

    private func exercisePayload(force: Bool) -> String? {
        if force || exerciseSummary != lastSyncedExerciseSummary {
            lastSyncedExerciseSummary = exerciseSummary
            return exerciseSummary
        }
        return nil
    }

    private var exerciseListView: some View {
        VStack(spacing: 6) {
            Text("운동 목록")
                .font(.headline)
                .foregroundStyle(TimerTheme.secondaryText)
            if exercises.isEmpty {
                Text("운동 목록 없음")
                    .font(.subheadline)
                    .foregroundStyle(TimerTheme.secondaryText)
            } else {
                ForEach(Array(exercises.enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(TimerTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
    }

    private func scheduleEndNotification(total: Int) {
        let content = UNMutableNotificationContent()
        content.title = "타이머 알림"
        content.body = "운동이 끝났습니다!"
        content.sound = .default
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(total * 60), repeats: false)
        let request = UNNotificationRequest(identifier: "amrap_end", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

#if os(iOS) && !targetEnvironment(macCatalyst)
    private func startLiveActivity(total: Int) {
        let attr = HIITAttributes(mode: TimerSyncMode.amrap, totalMinutes: total, intervalMinutes: 0)
        let state = HIITAttributes.ContentState(
            displaySeconds: remainingSeconds,
            label: "남은 시간",
            isRunning: true,
            isCountdown: true,
            sentAt: Date()
        )
        let content = ActivityContent(state: state, staleDate: nil)
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = try? Activity<HIITAttributes>.request(attributes: attr, content: content, pushType: nil)
        }
    }

    private func updateLiveActivity() {
        guard let activity else { return }
        let state = HIITAttributes.ContentState(
            displaySeconds: remainingSeconds,
            label: "남은 시간",
            isRunning: isRunning,
            isCountdown: true,
            sentAt: Date()
        )
        let content = ActivityContent(state: state, staleDate: nil)
        Task {
            await activity.update(content)
        }
    }

    private func endLiveActivity() {
        guard let activity else { return }
        let state = HIITAttributes.ContentState(
            displaySeconds: remainingSeconds,
            label: "남은 시간",
            isRunning: false,
            isCountdown: true,
            sentAt: Date()
        )
        let content = ActivityContent(state: state, staleDate: nil)
        Task {
            await activity.end(content, dismissalPolicy: .immediate)
            self.activity = nil
        }
    }
#else
    private func startLiveActivity(total: Int) {}
    private func updateLiveActivity() {}
    private func endLiveActivity() {}
#endif
}
