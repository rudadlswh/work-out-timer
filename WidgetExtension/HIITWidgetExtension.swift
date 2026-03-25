import WidgetKit
import ActivityKit
import SwiftUI
import AppIntents

struct HIITWidgetEntry: TimelineEntry {
    let date: Date
}

struct HIITWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HIITWidgetEntry {
        HIITWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (HIITWidgetEntry) -> Void) {
        completion(HIITWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HIITWidgetEntry>) -> Void) {
        let entry = HIITWidgetEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct EmomWidgetTab: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("EMOM")
                .font(.headline)
            Text("준비 완료")
                .font(.caption)
        }
    }
}

struct AmrapWidgetTab: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("AMRAP")
                .font(.headline)
            Text("준비 완료")
                .font(.caption)
        }
    }
}

struct HIITWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack {
            content
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.15),
                    Color(red: 0.20, green: 0.25, blue: 0.30)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            VStack(spacing: 6) {
                Text("WODy")
                    .font(.headline)
                Text("EMOM • AMRAP")
                    .font(.caption)
            }
            .padding()
        default:
            HStack(spacing: 12) {
                EmomWidgetTab()
                Divider()
                    .background(Color.white.opacity(0.2))
                AmrapWidgetTab()
            }
            .padding()
        }
    }
}

struct HIITWidget: Widget {
    let kind = "HIITWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HIITWidgetProvider()) { _ in
            HIITWidgetView()
        }
        .configurationDisplayName("WODy")
        .description("WOD 타이머를 빠르게 시작하세요.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HIITActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HIITAttributes.self) { context in
            // Lock screen/banner UI
            let timerDate = timerDate(from: context.state)
            let showsStopAction = shouldShowStopAction(for: context.state)
            VStack(spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("남은 시간")
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(timerDate, style: .timer)
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: .infinity)

                if showsStopAction {
                    Button(intent: StopTimerLiveActivityIntent()) {
                        Label("종료", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityLabel("타이머 종료")
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        } dynamicIsland: { context in
            let timerDate = timerDate(from: context.state)
            let isEmom = context.attributes.mode == "EMOM"
            let showsStopAction = shouldShowStopAction(for: context.state)
            return DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("남은 시간")
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Text(timerDate, style: .timer)
                                .font(.title2.monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .padding(.horizontal, 6)
                        if showsStopAction {
                            Button(intent: StopTimerLiveActivityIntent()) {
                                Label("종료", systemImage: "stop.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .accessibilityLabel("타이머 종료")
                        }
                    }
                }
            } compactLeading: {
                if isEmom {
                    Text(context.state.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(timerDate, style: .timer)
                        .monospacedDigit()
                }
            } compactTrailing: {
                if isEmom {
                    Text(timerDate, style: .timer)
                        .monospacedDigit()
                } else {
                    Text(context.attributes.mode)
                }
            } minimal: {
                Text(timerDate, style: .timer)
                    .monospacedDigit()
            }
        }
    }
}

private func timerDate(from state: HIITAttributes.ContentState) -> Date {
    if state.isCountdown {
        return state.sentAt.addingTimeInterval(TimeInterval(max(0, state.displaySeconds)))
    }
    return state.sentAt.addingTimeInterval(TimeInterval(-max(0, state.displaySeconds)))
}

private func shouldShowStopAction(for state: HIITAttributes.ContentState) -> Bool {
    state.isRunning || state.isCountdown
}

struct StopTimerLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Timer"
    static var description = IntentDescription("Ends the active timer session.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        await TimerSessionTermination.requestStopFromLiveActivity()
        return .result()
    }
}

#if APP_EXTENSION
@main
struct HIITWidgetBundle: WidgetBundle {
    var body: some Widget {
        HIITWidget()
        HIITActivityWidget()
    }
}
#endif
