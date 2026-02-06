import SwiftUI
import ActivityKit
import UserNotifications

struct EmomTabView: View {
    @Binding var isModePickerVisible: Bool

    @State private var intervalMinutes: Int = 1
    @State private var totalMinutes: Int = 5
    @State private var countdown: Int? = nil
    @State private var remainingSeconds: Int = 0
    @State private var nextBeep: Int = 0
    @State private var timer: Timer? = nil
    @State private var isRunning: Bool = false
    @State private var activity: Activity<HIITAttributes>? = nil
    @State private var exerciseInput: String = ""

    private let minuteOptions = Array(1...60)

    private var exercises: [String] {
        TimerUtilities.parseExercises(exerciseInput)
    }

    var body: some View {
        VStack(spacing: 24) {
            if countdown == nil {
                inputView
            } else if let cd = countdown, cd > 0 {
                countdownView(cd)
            } else if isRunning {
                runningView
            } else {
                completeView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: updateModePickerVisibility)
        .onChange(of: isRunning) { _ in updateModePickerVisibility() }
        .onChange(of: countdown) { _ in updateModePickerVisibility() }
    }

    private var inputView: some View {
        VStack(spacing: 12) {
            Text("EMOM 타이머 설정")
                .font(.title2)
                .foregroundStyle(TimerTheme.primaryText)
            HStack {
                Text("인터벌(분):")
                    .foregroundStyle(TimerTheme.secondaryText)
                Picker("인터벌(분)", selection: $intervalMinutes) {
                    ForEach(minuteOptions, id: \.self) { min in
                        Text("\(min)분").tag(min)
                    }
                }
                .pickerStyle(.menu)
            }
            HStack(spacing: 12) {
                Text("총 시간(분):")
                    .foregroundStyle(TimerTheme.secondaryText)
                Picker("총 시간(분)", selection: $totalMinutes) {
                    ForEach(minuteOptions, id: \.self) { min in
                        Text("\(min)분").tag(min)
                    }
                }
                .pickerStyle(.menu)
            }
            VStack(alignment: .center, spacing: 6) {
                Text("운동 목록(쉼표로 구분)")
                    .font(.subheadline)
                    .foregroundStyle(TimerTheme.secondaryText)
                TextField("플랭크, 스내치, 버피", text: $exerciseInput)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .padding(10)
                    .background(Color.black.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .foregroundStyle(TimerTheme.primaryText)
                    .tint(TimerTheme.actionTint)
                    .padding(.horizontal, 12)
            }
            Button("시작") {
                startCountdown()
            }
            .buttonStyle(.borderedProminent)
            .tint(TimerTheme.actionTint)
        }
    }

    private func countdownView(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 64, weight: .bold))
            .foregroundStyle(TimerTheme.primaryText)
            .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
    }

    private var runningView: some View {
        let rounds = max(1, ((totalMinutes * 60 - remainingSeconds) / (intervalMinutes * 60)) + 1)
        let roundLabel = intervalMinutes == 1 ? "\(rounds)분" : "\(rounds)라운드"
        let currentExercise = exercises.isEmpty
            ? "운동 없음"
            : exercises[(rounds - 1) % exercises.count]

        return VStack(spacing: 32) {
            Text(roundLabel)
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(TimerTheme.primaryText)
                .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
            VStack(spacing: 8) {
                Text("이번 동작")
                    .font(.headline)
                    .foregroundStyle(TimerTheme.secondaryText)
                Text(currentExercise)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(TimerTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(TimerUtilities.formatTime(nextBeep))
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(TimerTheme.secondaryText)
            Button("중지") {
                stopTimer()
            }
            .buttonStyle(.bordered)
            .tint(TimerTheme.stopTint)
        }
    }

    private var completeView: some View {
        VStack(spacing: 12) {
            Text("완료!")
                .font(.title)
                .foregroundStyle(TimerTheme.primaryText)
            Button("다시 시작") {
                resetAll()
            }
            .buttonStyle(.borderedProminent)
            .tint(TimerTheme.actionTint)
        }
    }

    private func updateModePickerVisibility() {
        isModePickerVisible = !isRunning && countdown == nil
    }

    private func startCountdown() {
        startCountdownTimer {
            startEmomTimer(interval: intervalMinutes, total: totalMinutes)
        }
    }

    private func startCountdownTimer(then startAction: @escaping () -> Void) {
        countdown = 5
        isRunning = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if let cd = countdown, cd > 1 {
                countdown = cd - 1
            } else {
                timer?.invalidate()
                startAction()
            }
        }
    }

    private func startEmomTimer(interval: Int, total: Int) {
        remainingSeconds = total * 60
        scheduleIntervalNotifications(interval: interval, total: total)
        nextBeep = interval * 60
        isRunning = true
        countdown = 0
        startLiveActivity(interval: interval, total: total)
        TimerUtilities.playBeep()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if remainingSeconds > 0 {
                remainingSeconds -= 1
                nextBeep -= 1
                if nextBeep == 0 {
                    TimerUtilities.playBeep()
                    nextBeep = interval * 60
                }
                updateLiveActivity()
            } else {
                timer?.invalidate()
                isRunning = false
                endLiveActivity()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        isRunning = false
        countdown = nil
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        endLiveActivity()
    }

    private func resetAll() {
        countdown = nil
        isRunning = false
        timer?.invalidate()
        remainingSeconds = 0
        nextBeep = 0
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        endLiveActivity()
    }

    private func scheduleIntervalNotifications(interval: Int, total: Int) {
        let content = UNMutableNotificationContent()
        content.title = "타이머 알림"
        content.body = "운동/휴식 구간이 끝났습니다!"
        content.sound = .default
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        let count = total / interval
        for i in 1...count {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(i * interval * 60), repeats: false)
            let request = UNNotificationRequest(identifier: "hiit_\(i)", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func startLiveActivity(interval: Int, total: Int) {
        let attr = HIITAttributes(totalMinutes: total, intervalMinutes: interval)
        let state = HIITAttributes.ContentState(remainingSeconds: total * 60, nextBeep: interval * 60, isRunning: true)
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            Task {
                activity = try? await Activity<HIITAttributes>.request(attributes: attr, contentState: state, pushType: nil)
            }
        }
    }

    private func updateLiveActivity() {
        guard let activity else { return }
        let state = HIITAttributes.ContentState(remainingSeconds: remainingSeconds, nextBeep: nextBeep, isRunning: isRunning)
        Task {
            await activity.update(using: state)
        }
    }

    private func endLiveActivity() {
        guard let activity else { return }
        Task {
            await activity.end(dismissalPolicy: .immediate)
            self.activity = nil
        }
    }
}
