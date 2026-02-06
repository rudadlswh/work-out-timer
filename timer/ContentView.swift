import SwiftUI
import UserNotifications

enum WorkoutMode: String, CaseIterable, Identifiable {
    case emom = "EMOM"
    case amrap = "AMRAP"
    case forTime = "FOR TIME"

    var id: String { rawValue }
}

struct ContentView: View {
    @State private var workoutMode: WorkoutMode = .emom
    @State private var isModePickerVisible: Bool = true

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                gradient: Gradient(colors: [TimerTheme.backgroundTop, TimerTheme.backgroundBottom]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if isModePickerVisible {
                Picker("운동 방식", selection: $workoutMode) {
                    ForEach(WorkoutMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 16)
                .padding(.horizontal)
                .zIndex(1)
            }

            modeView
        }
        .tint(TimerTheme.actionTint)
        .onAppear(perform: requestNotificationPermission)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .inactive || newPhase == .background {
                // 옵션: 알림 예약 유지 또는 정리
            }
        }
    }

    @ViewBuilder
    private var modeView: some View {
        switch workoutMode {
        case .emom:
            EmomTabView(isModePickerVisible: $isModePickerVisible)
        case .amrap:
            AmrapTabView(isModePickerVisible: $isModePickerVisible)
        case .forTime:
            ForTimeTabView(isModePickerVisible: $isModePickerVisible)
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            // 필요시 granted 체크
        }
    }
}

#Preview {
    ContentView()
}
