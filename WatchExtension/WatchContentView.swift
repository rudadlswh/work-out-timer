import SwiftUI

enum WatchWorkoutMode: String, CaseIterable, Identifiable {
    case emom = "EMOM"
    case amrap = "AMRAP"
    case forTime = "FOR TIME"

    var id: String { rawValue }
}

struct WatchContentView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager
    @State private var workoutMode: WatchWorkoutMode = .emom
    @State private var isLocalTabLocked: Bool = false

    private var isTabLocked: Bool {
        isLocalTabLocked || workoutManager.phoneTimerState != nil
    }

    var body: some View {
        TabView(selection: $workoutMode) {
            WatchEmomView(isTabLocked: $isLocalTabLocked)
                .tag(WatchWorkoutMode.emom)
            WatchAmrapView(isTabLocked: $isLocalTabLocked)
                .tag(WatchWorkoutMode.amrap)
            WatchForTimeView(isTabLocked: $isLocalTabLocked)
                .tag(WatchWorkoutMode.forTime)
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .modifier(TabSwipeLockModifier(isLocked: isTabLocked))
        .onChange(of: workoutManager.phoneTimerState) { _, newValue in
            guard let modeString = newValue?.mode,
                  let mode = WatchWorkoutMode(rawValue: modeString) else { return }
            workoutMode = mode
        }
    }
}

private struct TabSwipeLockModifier: ViewModifier {
    let isLocked: Bool

    func body(content: Content) -> some View {
        let minimumDistance: CGFloat = isLocked ? 10 : .greatestFiniteMagnitude
        return content.highPriorityGesture(
            DragGesture(minimumDistance: minimumDistance).onChanged { _ in },
            including: .gesture
        )
    }
}

#Preview {
    WatchContentView()
        .environmentObject(WatchWorkoutManager())
}
