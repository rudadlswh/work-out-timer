import SwiftUI
import UserNotifications

struct AmrapTabView: View {
    @Binding var isModePickerVisible: Bool

    @State private var totalMinutes: Int = 5
    @State private var countdown: Int? = nil
    @State private var remainingSeconds: Int = 0
    @State private var timer: Timer? = nil
    @State private var isRunning: Bool = false
    @State private var exerciseInput: String = ""
    @State private var rounds: Int = 0
    @State private var endAlertEnabled: Bool = true

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
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if isRunning {
                    rounds += 1
                }
            }
        )
        .onAppear(perform: updateModePickerVisibility)
        .onChange(of: isRunning) { _ in updateModePickerVisibility() }
        .onChange(of: countdown) { _ in updateModePickerVisibility() }
    }

    private var inputView: some View {
        VStack(spacing: 12) {
            Text("AMRAP 타이머 설정")
                .font(.title2)
                .foregroundStyle(TimerTheme.primaryText)
            HStack(spacing: 12) {
                Text("총 시간(분):")
                    .foregroundStyle(TimerTheme.secondaryText)
                Picker("총 시간(분)", selection: $totalMinutes) {
                    ForEach(minuteOptions, id: \.self) { min in
                        Text("\(min)분").tag(min)
                    }
                }
                .pickerStyle(.menu)
                Button(action: { endAlertEnabled.toggle() }) {
                    HStack(spacing: 6) {
                        Text("끝 알람")
                            .font(.subheadline)
                            .foregroundStyle(TimerTheme.secondaryText)
                        Image(systemName: endAlertEnabled ? "checkmark.square.fill" : "square")
                            .foregroundStyle(endAlertEnabled ? TimerTheme.actionTint : TimerTheme.secondaryText)
                    }
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .center, spacing: 6) {
                Text("운동 목록")
                    .font(.subheadline)
                    .foregroundStyle(TimerTheme.secondaryText)
                TextEditor(text: $exerciseInput)
                    .scrollContentBackground(.hidden)
                    .frame(height: 90)
                    .padding(8)
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
        VStack(spacing: 20) {
            Text("라운드 \(rounds)")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(TimerTheme.primaryText)
            if exercises.isEmpty {
                Text("운동 목록 없음")
                    .font(.headline)
                    .foregroundStyle(TimerTheme.secondaryText)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(exercises.enumerated()), id: \.offset) { _, item in
                        Text(item)
                            .font(.headline)
                            .foregroundStyle(TimerTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
            Text(TimerUtilities.formatTime(remainingSeconds))
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(TimerTheme.primaryText)
                .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
            Text("더블탭: 라운드 +1")
                .font(.footnote)
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
            Text("완료 라운드 \(rounds)")
                .font(.headline)
                .foregroundStyle(TimerTheme.secondaryText)
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
            startAmrapTimer(total: totalMinutes)
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

    private func startAmrapTimer(total: Int) {
        remainingSeconds = total * 60
        isRunning = true
        countdown = 0
        rounds = 0
        if endAlertEnabled {
            scheduleEndNotification(total: total)
        } else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
        TimerUtilities.playBeep()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            } else {
                timer?.invalidate()
                isRunning = false
                if endAlertEnabled {
                    TimerUtilities.playBeep()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        isRunning = false
        countdown = nil
        rounds = 0
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private func resetAll() {
        countdown = nil
        isRunning = false
        timer?.invalidate()
        remainingSeconds = 0
        rounds = 0
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
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
}
