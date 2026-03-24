import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

enum WorkoutMode: String, CaseIterable, Identifiable {
    case emom = "EMOM"
    case amrap = "AMRAP"
    case forTime = "FOR TIME"

    var id: String { rawValue }
}

struct ContentView: View {
    @State private var workoutMode: WorkoutMode = .emom
    @State private var isModePickerVisible: Bool = true
    @State private var isTimerSessionActive: Bool = false
    @State private var isSettingsPresented: Bool = false
    @State private var showOnboarding: Bool = false

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @AppStorage("shouldShowOnboarding") private var shouldShowOnboarding: Bool = false

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

            TabView(selection: workoutModeSelection) {
                EmomTabView(
                    mode: .emom,
                    selectedMode: $workoutMode,
                    isModePickerVisible: $isModePickerVisible,
                    isTimerSessionActive: $isTimerSessionActive
                )
                    .tag(WorkoutMode.emom)
                AmrapTabView(
                    mode: .amrap,
                    selectedMode: $workoutMode,
                    isModePickerVisible: $isModePickerVisible,
                    isTimerSessionActive: $isTimerSessionActive
                )
                    .tag(WorkoutMode.amrap)
                ForTimeTabView(
                    mode: .forTime,
                    selectedMode: $workoutMode,
                    isModePickerVisible: $isModePickerVisible,
                    isTimerSessionActive: $isTimerSessionActive
                )
                    .tag(WorkoutMode.forTime)
            }
#if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .modifier(TabSwipeLockModifier(isLocked: isTimerSessionActive))
            .background(PageSwipeInteractionBridge(isLocked: isTimerSessionActive))
#endif

            settingsButton
        }
        .tint(TimerTheme.actionTint)
        .toolbar { keyboardToolbar }
        .onAppear(perform: requestNotificationPermission)
        .onChange(of: workoutMode, initial: false) { _, _ in
            dismissActiveKeyboard()
        }
        .onChange(of: scenePhase, initial: false) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                // 옵션: 알림 예약 유지 또는 정리
            }
        }
        .onAppear {
            if !hasSeenOnboarding || shouldShowOnboarding {
                showOnboarding = true
                shouldShowOnboarding = false
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                SettingsView()
            }
            .tint(TimerTheme.actionTint)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasSeenOnboarding = true
                showOnboarding = false
            }
            .interactiveDismissDisabled()
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

    @ToolbarContentBuilder
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("완료") {
                dismissActiveKeyboard()
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            // 필요시 granted 체크
        }
    }

    private var workoutModeSelection: Binding<WorkoutMode> {
        Binding(
            get: { workoutMode },
            set: { newValue in
                guard !isTimerSessionActive || newValue == workoutMode else { return }
                workoutMode = newValue
            }
        )
    }

    private func dismissActiveKeyboard() {
#if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }
}

private struct TabSwipeLockModifier: ViewModifier {
    let isLocked: Bool

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            return content.scrollDisabled(isLocked)
        } else {
            let minimumDistance: CGFloat = isLocked ? 10 : .greatestFiniteMagnitude
            return content.highPriorityGesture(
                DragGesture(minimumDistance: minimumDistance).onChanged { _ in },
                including: .gesture
            )
        }
    }
}

#if os(iOS)
private struct PageSwipeInteractionBridge: UIViewRepresentable {
    let isLocked: Bool

    final class Coordinator {
        weak var pagingScrollView: UIScrollView?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let pagingScrollView = findPagingScrollView(from: uiView) else { return }

            if context.coordinator.pagingScrollView !== pagingScrollView {
                context.coordinator.pagingScrollView?.isScrollEnabled = true
                context.coordinator.pagingScrollView?.panGestureRecognizer.isEnabled = true
                context.coordinator.pagingScrollView = pagingScrollView
            }

            pagingScrollView.isScrollEnabled = !isLocked
            pagingScrollView.panGestureRecognizer.isEnabled = !isLocked
        }
    }

    private func findPagingScrollView(from view: UIView) -> UIScrollView? {
        if let pageController = view.enclosingViewController(of: UIPageViewController.self),
           let scrollView = firstPagingScrollView(in: pageController.view) {
            return scrollView
        }

        var current: UIView? = view
        while let candidate = current {
            if let scrollView = firstPagingScrollView(in: candidate) {
                return scrollView
            }
            current = candidate.superview
        }

        return nil
    }

    private func firstPagingScrollView(in root: UIView) -> UIScrollView? {
        if let scrollView = root as? UIScrollView, scrollView.isPagingEnabled {
            return scrollView
        }

        for subview in root.subviews {
            if let match = firstPagingScrollView(in: subview) {
                return match
            }
        }

        return nil
    }
}

private extension UIView {
    func enclosingViewController<T: UIViewController>(of type: T.Type) -> T? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? T {
                return controller
            }
            responder = current.next
        }
        return nil
    }
}
#endif

#Preview {
    ContentView()
        .environmentObject(HeartRateManager())
}
