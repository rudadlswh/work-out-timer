import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var heartRateManager: HeartRateManager
    @Environment(\.dismiss) private var dismiss

    private var isLinked: Bool {
        heartRateManager.isSessionSupported
            && heartRateManager.isWatchPaired
            && heartRateManager.isWatchAppInstalled
    }

    private var linkStatusText: String {
        guard heartRateManager.isSessionSupported else { return "지원 안 됨" }
        return isLinked ? "연동됨" : "연동 안 됨"
    }

    private var linkStatusColor: Color {
        guard heartRateManager.isSessionSupported else { return TimerTheme.secondaryText }
        return isLinked ? Color.green : TimerTheme.stopTint
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var pingStatusText: String {
        heartRateManager.isPinging ? "진행 중" : heartRateManager.lastPingStatus
    }

    private var pingStatusColor: Color {
        if heartRateManager.isPinging {
            return TimerTheme.secondaryText
        }
        if heartRateManager.lastPingSucceeded == true {
            return Color.green
        }
        if heartRateManager.lastPingSucceeded == false {
            return TimerTheme.stopTint
        }
        return TimerTheme.secondaryText
    }

    private var lastPingTimeText: String {
        guard let date = heartRateManager.lastPingDate else { return "없음" }
        return Self.timeFormatter.string(from: date)
    }

    private var lastHeartRateTimeText: String {
        guard let date = heartRateManager.lastHeartRateDate else { return "없음" }
        return Self.timeFormatter.string(from: date)
    }

    var body: some View {
        ZStack {
            TimerBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    statusCard
                    heartRateCard
                    helpCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("닫기") {
                    dismiss()
                }
                .foregroundStyle(TimerTheme.actionTint)
            }
        }
        .onAppear {
            heartRateManager.refreshConnectionStatus()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Apple Watch 연동 상태")
                .font(.title3.bold())
                .foregroundStyle(TimerTheme.primaryText)
            Text("아이폰과 워치 연결 상태를 확인할 수 있습니다.")
                .font(.subheadline)
                .foregroundStyle(TimerTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow(title: "연동 상태", value: linkStatusText, valueColor: linkStatusColor)
            statusRow(title: "페어링", value: supportAwareText(heartRateManager.isWatchPaired))
            statusRow(title: "워치 앱 설치", value: supportAwareText(heartRateManager.isWatchAppInstalled))
            statusRow(title: "실시간 연결", value: supportAwareText(heartRateManager.isReachable))
            statusRow(title: "세션 상태", value: heartRateManager.activationStateText)
            statusRow(title: "핑 상태", value: pingStatusText, valueColor: pingStatusColor)
            statusRow(title: "마지막 핑", value: lastPingTimeText)

            Button("상태 새로고침") {
                heartRateManager.refreshConnectionStatus()
            }
            .buttonStyle(.bordered)
            .tint(TimerTheme.actionTint)

            Button("핑 테스트") {
                heartRateManager.pingWatch()
            }
            .buttonStyle(.bordered)
            .tint(TimerTheme.actionTint)
            .disabled(heartRateManager.isPinging)
        }
        .padding(16)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("연동이 안 될 때")
                .font(.headline)
                .foregroundStyle(TimerTheme.primaryText)
            Text("- 아이폰이 워치와 페어링되어 있는지 확인하세요.")
            Text("- 워치 앱이 설치되어 있고, Bluetooth/Wi-Fi가 켜져 있는지 확인하세요.")
            Text("- 실시간 연결은 워치 앱이 실행 중일 때만 예로 표시됩니다.")
        }
        .font(.subheadline)
        .foregroundStyle(TimerTheme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("심박수 확인")
                .font(.headline)
                .foregroundStyle(TimerTheme.primaryText)
            statusRow(title: "측정 상태", value: heartRateManager.isCollecting ? "측정 중" : "대기")
            statusRow(title: "현재 심박", value: heartRateManager.currentBpm.map { "\($0) bpm" } ?? "미수신")
            statusRow(title: "평균 심박", value: heartRateManager.averageBpm.map { "\($0) bpm" } ?? "미수신")
            statusRow(title: "마지막 수신", value: lastHeartRateTimeText)

            Button(heartRateManager.isCollecting ? "심박 측정 중지" : "심박 측정 시작") {
                if heartRateManager.isCollecting {
                    heartRateManager.stop()
                } else {
                    heartRateManager.start()
                }
            }
            .buttonStyle(.bordered)
            .tint(heartRateManager.isCollecting ? TimerTheme.stopTint : TimerTheme.actionTint)

            Text("워치 앱이 전면 실행 중일 때 실시간 심박이 수신됩니다.")
                .font(.caption)
                .foregroundStyle(TimerTheme.secondaryText)
        }
        .padding(16)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func statusRow(title: String, value: String, valueColor: Color = TimerTheme.primaryText) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(TimerTheme.secondaryText)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func supportAwareText(_ flag: Bool) -> String {
        guard heartRateManager.isSessionSupported else { return "지원 안 됨" }
        return flag ? "예" : "아니오"
    }
}

#Preview {
    SettingsView()
        .environmentObject(HeartRateManager())
}
