import WidgetKit
import ActivityKit
import SwiftUI

enum WidgetTab: String, CaseIterable, Identifiable {
    case emom = "EMOM"
    case amrap = "AMRAP"
    var id: String { rawValue }
}

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
    @State private var selectedTab: WidgetTab = .emom

    var body: some View {
        VStack {
            Picker("위젯 탭", selection: $selectedTab) {
                ForEach(WidgetTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding([.top, .horizontal])

            Spacer()

            switch selectedTab {
            case .emom:
                EmomWidgetTab()
            case .amrap:
                AmrapWidgetTab()
            }

            Spacer()
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
}

struct HIITWidget: Widget {
    let kind = "HIITWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HIITWidgetProvider()) { _ in
            HIITWidgetView()
        }
        .configurationDisplayName("HIIT 타이머")
        .description("빠르게 타이머를 시작하세요.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HIITActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HIITAttributes.self) { context in
            // Lock screen/banner UI
            VStack {
                Text("다음 인터벌까지")
                Text("\(context.state.nextBeep)초")
                    .font(.largeTitle)
                    .monospacedDigit()
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.center) {
                    VStack {
                        Text("다음 인터벌까지")
                        Text("\(context.state.nextBeep)초")
                            .font(.title)
                            .monospacedDigit()
                    }
                }
            } compactLeading: {
                Text("\(context.state.nextBeep)s")
                    .monospacedDigit()
            } compactTrailing: {
                Text("HIIT")
            } minimal: {
                Text("\(context.state.nextBeep)")
                    .monospacedDigit()
            }
        }
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
