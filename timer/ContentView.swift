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
    @State private var isSettingsPresented: Bool = false

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .top) {
            TimerBackgroundView()

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

            TabView(selection: $workoutMode) {
                EmomTabView(isModePickerVisible: $isModePickerVisible)
                    .tag(WorkoutMode.emom)
                AmrapTabView(isModePickerVisible: $isModePickerVisible)
                    .tag(WorkoutMode.amrap)
                ForTimeTabView(isModePickerVisible: $isModePickerVisible)
                    .tag(WorkoutMode.forTime)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            settingsButton
        }
        .tint(TimerTheme.actionTint)
        .onAppear(perform: requestNotificationPermission)
        .onChange(of: scenePhase, initial: false) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                // 옵션: 알림 예약 유지 또는 정리
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                SettingsView()
            }
            .tint(TimerTheme.actionTint)
        }
    }

    private var settingsButton: some View {
        HStack {
            Spacer()
            Button(action: { isSettingsPresented = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TimerTheme.primaryText)
                    .padding(10)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }
            .accessibilityLabel("설정")
        }
        .padding(.top, isModePickerVisible ? 64 : 16)
        .padding(.trailing, 16)
        .zIndex(2)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            // 필요시 granted 체크
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(HeartRateManager())
}
