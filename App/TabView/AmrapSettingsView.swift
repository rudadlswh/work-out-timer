import SwiftUI

struct AmrapSettingsView: View {
    let minuteOptions: [Int]
    @Binding var totalMinutes: Int
    @Binding var endAlertEnabled: Bool
    @Binding var exerciseInput: String
    let exerciseFieldFocus: FocusState<Bool>.Binding
    let onStart: () -> Void

    var body: some View {
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
                    .focused(exerciseFieldFocus)
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
            Button("시작", action: onStart)
                .buttonStyle(.borderedProminent)
                .tint(TimerTheme.actionTint)
        }
    }
}
