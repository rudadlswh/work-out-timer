import AVFoundation
import Foundation

enum TimerUtilities {
    static func playBeep() {
        AudioServicesPlaySystemSound(1052)
    }

    static func formatTime(_ sec: Int) -> String {
        let minutes = sec / 60
        let seconds = sec % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func parseExercises(_ input: String) -> [String] {
        input
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
