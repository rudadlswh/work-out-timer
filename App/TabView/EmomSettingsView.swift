import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct EmomSettingsView: View {
    let minuteOptions: [Int]
    @Binding var intervalMinutes: Int
    @Binding var totalMinutes: Int
    @Binding var exerciseInput: String
    let exerciseFieldFocus: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onStart: () -> Void

    var body: some View {
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
                TextField("", text: $exerciseInput)
                    .disableAutocorrection(true)
#if canImport(UIKit)
                    .textInputAutocapitalization(.never)
#endif
                    .focused(exerciseFieldFocus)
                    .submitLabel(.done)
                    .onSubmit(onSubmit)
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
            Button("시작", action: onStart)
                .buttonStyle(.borderedProminent)
                .tint(TimerTheme.actionTint)
        }
    }
}
